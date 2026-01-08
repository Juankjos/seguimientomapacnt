import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(TrackingTaskHandler());
}

class TrackingTaskHandler extends TaskHandler {
  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;

  String? _wsUrl;
  String? _token;
  int? _noticiaId;
  bool _saveHistory = false;

  int? _sessionId;

  bool _isAuthed = false;
  Completer<void>? _authedCompleter;

  bool _reconnecting = false;
  bool _stopping = false;
  Timer? _reconnectTimer;

  bool _startingSession = false;
  DateTime? _startRequestedAt;

  DateTime? _lastSentAt;
  double? _lastLat;
  double? _lastLon;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    DartPluginRegistrant.ensureInitialized();

    final raw = await FlutterForegroundTask.getData<String>(key: 'tracking_payload');
    if (raw == null) return;

    final payload = jsonDecode(raw) as Map<String, dynamic>;
    _wsUrl = payload['ws_url'] as String?;
    _token = payload['token'] as String?;
    _noticiaId = (payload['noticia_id'] as num?)?.toInt();
    _saveHistory = (payload['save_history'] as bool?) ?? false;

    _stopping = false;

    await _connectWs();
    await _waitAuthed();
    await _ensureSessionStarted();
    await _tickSendLocation();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_tickSendLocation());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // ✅ Reutiliza el flujo seguro de stop+close
    await _sendStopAndClose();
  }

  @override
  void onReceiveData(Object data) {
    if (data == 'STOP_TRACKING') {
      unawaited(_sendStopAndClose());
    }
  }

  Future<void> _sendStopAndClose() async {
    _stopping = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    try {
      if (_ws != null && _sessionId != null) {
        _ws!.sink.add(jsonEncode({
          'type': 'tracking_stop',
          'session_id': _sessionId,
        }));

        // ✅ deja salir el frame antes de cerrar el socket / matar el servicio
        await Future.delayed(const Duration(milliseconds: 200));
      }
    } catch (_) {}

    await _disposeWs();
  }

  Future<void> _connectWs() async {
    if (_wsUrl == null || _token == null) return;
    if (_stopping) return;

    await _disposeWs();

    _isAuthed = false;
    _authedCompleter = Completer<void>();

    try {
      final uri = Uri.parse(_wsUrl!);
      final withToken = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'token': _token!,
      });

      final ch = WebSocketChannel.connect(withToken);
      _ws = ch;

      _wsSub = ch.stream.listen(
        (event) {
          try {
            final msg = jsonDecode(event as String) as Map<String, dynamic>;
            final type = msg['type']?.toString();

            if (type == 'authed') {
              _isAuthed = true;
              final c = _authedCompleter;
              if (c != null && !c.isCompleted) c.complete();
              return;
            }

            if (type == 'tracking_started') {
              _sessionId = (msg['session_id'] as num).toInt();
              _startingSession = false;
              _startRequestedAt = null;
              return;
            }

            if (type == 'error') {
              _scheduleReconnect();
              return;
            }
          } catch (_) {}
        },
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: true,
      );

      await ch.ready.timeout(const Duration(seconds: 8));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  Future<void> _waitAuthed() async {
    final c = _authedCompleter;
    if (c == null) return;

    try {
      await c.future.timeout(const Duration(seconds: 8));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_stopping) return;
    if (_reconnecting) return;
    _reconnecting = true;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () async {
      _reconnecting = false;
      if (_stopping) return;

      await _disposeWs();
      await _connectWs();
      await _waitAuthed();
      await _ensureSessionStarted();
    });
  }

  Future<void> _ensureSessionStarted() async {
    if (_stopping) return;
    if (_ws == null || _noticiaId == null) return;
    if (!_isAuthed) return;

    if (_sessionId != null) return;

    if (_startingSession) {
      final t = _startRequestedAt;
      if (t != null) {
        final secs = DateTime.now().difference(t).inSeconds;
        if (secs < 10) return;
      }
    }

    _startingSession = true;
    _startRequestedAt = DateTime.now();

    try {
      _ws!.sink.add(jsonEncode({
        'type': 'tracking_start',
        'noticia_id': _noticiaId,
        'save_history': _saveHistory,
      }));
    } catch (_) {}
  }

  Future<void> _tickSendLocation() async {
    if (_stopping) return;

    if (_ws == null) {
      _scheduleReconnect();
      return;
    }

    if (!_isAuthed) return;

    if (_sessionId == null) {
      await _ensureSessionStarted();
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final now = DateTime.now();
      final lat = pos.latitude;
      final lon = pos.longitude;

      if (!_shouldSend(now, lat, lon)) return;

      _lastSentAt = now;
      _lastLat = lat;
      _lastLon = lon;

      _ws!.sink.add(jsonEncode({
        'type': 'tracking_location',
        'session_id': _sessionId,
        'lat': lat,
        'lon': lon,
        'accuracy': pos.accuracy,
        'speed': pos.speed,
        'heading': pos.heading,
        'ts': now.toIso8601String(),
      }));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  bool _shouldSend(DateTime now, double lat, double lon) {
    if (_lastSentAt == null || _lastLat == null || _lastLon == null) return true;

    final seconds = now.difference(_lastSentAt!).inSeconds;
    if (seconds >= 7) return true;

    final meters = Geolocator.distanceBetween(_lastLat!, _lastLon!, lat, lon);
    return meters >= 3;
  }

  Future<void> _disposeWs() async {
    await _wsSub?.cancel();
    _wsSub = null;

    try {
      await _ws?.sink.close();
    } catch (_) {}

    _ws = null;

    _sessionId = null;
    _startingSession = false;
    _startRequestedAt = null;

    _isAuthed = false;
    _authedCompleter = null;
  }
}
