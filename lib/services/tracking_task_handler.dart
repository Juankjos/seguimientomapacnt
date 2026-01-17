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
  bool _fatalAuth = false;
  Timer? _reconnectTimer;

  bool _startingSession = false;
  DateTime? _startRequestedAt;

  DateTime? _lastSentAt;
  double? _lastLat;
  double? _lastLon;

  bool _retriedWithLatestToken = false;
  bool _suppressReconnectOnce = false;

  void _log(String s) {
    // ignore: avoid_print
    print('[TRACKING_TASK] $s');
    try {
      FlutterForegroundTask.updateService(notificationText: s);
    } catch (_) {}
  }

  bool _parseBoolish(dynamic v) {
    if (v is bool) return v;
    final s = v?.toString().trim().toLowerCase() ?? '';
    return s == '1' || s == 'true' || s == 'yes' || s == 'si';
  }

  Future<void> _refreshTokenFromStore() async {
    final latest = await FlutterForegroundTask.getData<String>(key: 'ws_token_latest');
    if (latest != null && latest.trim().isNotEmpty) {
      _token = latest.trim();
      final pfx = _token!.length >= 8 ? _token!.substring(0, 8) : _token!;
      _log('Token refrescado: $pfx...');
    }
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    DartPluginRegistrant.ensureInitialized();

    _stopping = false;
    _fatalAuth = false;
    _retriedWithLatestToken = false;
    _suppressReconnectOnce = false;

    final raw = await FlutterForegroundTask.getData<String>(key: 'tracking_payload');
    if (raw == null) {
      _log('Sin payload de tracking.');
      return;
    }

    final payload = jsonDecode(raw) as Map<String, dynamic>;
    _wsUrl = payload['ws_url'] as String?;
    _token = payload['token'] as String?;
    _noticiaId = (payload['noticia_id'] as num?)?.toInt();
    _saveHistory = _parseBoolish(payload['save_history']);

    // ✅ obliga token latest antes de validar/conectar
    await _refreshTokenFromStore();

    if ((_wsUrl ?? '').isEmpty || (_token ?? '').isEmpty || (_noticiaId ?? 0) <= 0) {
      _log('Payload inválido (ws_url/token/noticia_id).');
      await FlutterForegroundTask.stopService();
      return;
    }

    _log('Iniciando WS...');
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
        await Future.delayed(const Duration(milliseconds: 200));
      }
    } catch (_) {}

    await _disposeWs();
  }

  Future<void> _connectWs() async {
    if (_wsUrl == null || _token == null) return;
    if (_stopping || _fatalAuth) return;

    // ✅ refresca token latest antes de conectar (también en reconexiones)
    await _refreshTokenFromStore();

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
              _log('Autenticado en WS.');
              final c = _authedCompleter;
              if (c != null && !c.isCompleted) c.complete();
              return;
            }

            if (type == 'tracking_started') {
              _sessionId = (msg['session_id'] as num).toInt();
              _startingSession = false;
              _startRequestedAt = null;
              _log('Sesión iniciada: $_sessionId');
              return;
            }

            if (type == 'error') {
              final m = msg['message']?.toString() ?? '';
              _log('WS error: $m');

              final lower = m.toLowerCase();
              final isAuthFail = lower.contains('token inválido') ||
                  lower.contains('token invalido') ||
                  lower.contains('expirado');

              if (isAuthFail) {
                if (!_retriedWithLatestToken) {
                  _retriedWithLatestToken = true;
                  _suppressReconnectOnce = true;
                  _log('Auth fail -> reintentando 1 vez con ws_token_latest…');

                  unawaited(() async {
                    await _refreshTokenFromStore();
                    await _disposeWs();
                    await _connectWs();
                    await _waitAuthed();
                    await _ensureSessionStarted();
                  }());
                  return;
                }

                _fatalAuth = true;
                unawaited(_disposeWs());
                unawaited(FlutterForegroundTask.stopService());
                return;
              }

              _scheduleReconnect();
              return;
            }
          } catch (e) {
            _log('Parse error: $e');
          }
        },
        onError: (e) {
          _log('WS onError: $e');
          if (_suppressReconnectOnce) {
            _suppressReconnectOnce = false;
            return;
          }
          _scheduleReconnect();
        },
        onDone: () {
          _log('WS cerrado.');
          if (_suppressReconnectOnce) {
            _suppressReconnectOnce = false;
            return;
          }
          _scheduleReconnect();
        },
        cancelOnError: true,
      );

      await ch.ready.timeout(const Duration(seconds: 8));
    } catch (e) {
      _log('No se pudo conectar WS: $e');
      _scheduleReconnect();
    }
  }

  Future<void> _waitAuthed() async {
    final c = _authedCompleter;
    if (c == null) return;

    try {
      await c.future.timeout(const Duration(seconds: 8));
    } catch (_) {
      _log('No llegó authed a tiempo.');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_stopping || _fatalAuth) return;
    if (_reconnecting) return;

    _reconnecting = true;
    _reconnectTimer?.cancel();

    _reconnectTimer = Timer(const Duration(seconds: 5), () async {
      _reconnecting = false;
      if (_stopping || _fatalAuth) return;

      await _disposeWs();
      await _connectWs();
      await _waitAuthed();
      await _ensureSessionStarted();
    });
  }

  Future<void> _ensureSessionStarted() async {
    if (_stopping || _fatalAuth) return;
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
      _log('Enviando tracking_start noticia=$_noticiaId');
      _ws!.sink.add(jsonEncode({
        'type': 'tracking_start',
        'noticia_id': _noticiaId,
        'save_history': _saveHistory,
      }));
    } catch (_) {}
  }

  Future<void> _tickSendLocation() async {
    if (_stopping || _fatalAuth) return;

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
        'ts': now.toUtc().toIso8601String(),
      }));

      _log('Env loc: $lat,$lon sid=$_sessionId');
    } catch (e) {
      _log('GPS error: $e');
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
