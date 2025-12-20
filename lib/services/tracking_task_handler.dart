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

  // Ahorro de datos: manda si se movió >= 10m o si pasó >= 45s.
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

    await _connectWs();
    await _sendStart();

    // Primer tick (por si el servidor responde rápido)
    await _tickSendLocation();
  }

  //  v9: se llama según ForegroundTaskOptions.eventAction
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
  void onReceiveData(Object data) {
    // no-op
  }

  Future<void> _connectWs() async {
    if (_wsUrl == null || _token == null) return;

    try {
      final uri = Uri.parse(_wsUrl!);
      final withToken = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'token': _token!,
      });

      _ws = WebSocketChannel.connect(withToken);

      // ✅ IMPORTANTÍSIMO: esperar handshake
      await _ws!.ready; // :contentReference[oaicite:1]{index=1}

      _wsSub = _ws!.stream.listen(
        (event) {
          try {
            final msg = jsonDecode(event as String) as Map<String, dynamic>;
            if (msg['type'] == 'tracking_started') {
              _sessionId = (msg['session_id'] as num).toInt();
            }
            // (Opcional) loguear authed/error para diagnóstico
          } catch (_) {}
        },
        onError: (e) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (e) {
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

      // Si no hay sesión, pedirla otra vez
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

    // Si todavía no hay session_id, insiste en start (sin spamear)
    if (_sessionId == null) {
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
    } catch (_) {
      // Si falla GPS, no tronamos el servicio.
    }
  }

  bool _shouldSend(DateTime now, double lat, double lon) {
    if (_lastSentAt == null || _lastLat == null || _lastLon == null) return true;

    final seconds = now.difference(_lastSentAt!).inSeconds;
    if (seconds >= 45) return true;

    final meters = Geolocator.distanceBetween(_lastLat!, _lastLon!, lat, lon);
    return meters >= 10;
  }

  Future<void> _disposeWs() async {
    await _wsSub?.cancel();
    _wsSub = null;

    try {
      await _ws?.sink.close();
    } catch (_) {}

    _ws = null;
    _sessionId = null;
  }
}
