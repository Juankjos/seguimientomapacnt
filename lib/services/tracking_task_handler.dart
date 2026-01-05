// tracking_task_handler.dart
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

  bool _reconnecting = false;

  DateTime? _lastSentAt;
  double? _lastLat;
  double? _lastLon;

  Completer<void>? _authedCompleter;

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

    await _connectWs();

    await _waitAuthed();

    await _sendStart();
    await _tickSendLocation();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _tickSendLocation();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    try {
      if (_ws != null && _sessionId != null) {
        _ws!.sink.add(jsonEncode({
          'type': 'tracking_stop',
          'session_id': _sessionId,
        }));
      }
    } catch (_) {}

    await _disposeWs();
  }

  @override
  void onReceiveData(Object data) {}

  Future<void> _connectWs() async {
    if (_wsUrl == null || _token == null) return;

    _authedCompleter = Completer<void>();

    try {
      final uri = Uri.parse(_wsUrl!);
      final withToken = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'token': _token!,
      });

      _ws = WebSocketChannel.connect(withToken);
      await _ws!.ready;

      _wsSub = _ws!.stream.listen(
        (event) {
          try {
            final msg = jsonDecode(event as String) as Map<String, dynamic>;

            if (msg['type'] == 'authed') {
              if (_authedCompleter != null && !_authedCompleter!.isCompleted) {
                _authedCompleter!.complete();
              }
              return;
            }

            if (msg['type'] == 'tracking_started') {
              _sessionId = (msg['session_id'] as num).toInt();
              return;
            }

            // Si quieres, aquí puedes loguear errores del server:
            // if (msg['type'] == 'error') { ... }

          } catch (_) {}
        },
        onError: (e) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  Future<void> _waitAuthed() async {
    final c = _authedCompleter;
    if (c == null) return;

    try {
      // timeout para evitar bloqueo si el WS no responde
      await c.future.timeout(const Duration(seconds: 8));
    } catch (_) {
      // Si no se pudo authed, forzamos reconexión
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnecting) return;
    _reconnecting = true;

    Future.delayed(const Duration(seconds: 5), () async {
      _reconnecting = false;
      await _disposeWs();
      await _connectWs();
      await _waitAuthed();

      if (_sessionId == null) {
        await _sendStart();
      }
    });
  }

  Future<void> _sendStart() async {
    if (_ws == null || _noticiaId == null) return;

    try {
      _ws!.sink.add(jsonEncode({
        'type': 'tracking_start',
        'noticia_id': _noticiaId,
        'save_history': _saveHistory,
      }));
    } catch (_) {}
  }

  Future<void> _tickSendLocation() async {
    if (_ws == null) {
      _scheduleReconnect();
      return;
    }

    if (_sessionId == null) {
      // Si aún no hay session_id, intenta start (pero ya con authed hecho)
      await _sendStart();
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
    } catch (_) {}
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

    // reinicia authed (se recalcula en connect)
    _authedCompleter = null;
  }
}
