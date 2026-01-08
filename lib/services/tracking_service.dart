// lib/services/tracking_service.dart

import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'tracking_task_handler.dart';

class TrackingService {
  static bool _running = false;
  static int? _runningNoticiaId;

  static Future<void> start({
    required String wsUrl,
    required String token,
    required int noticiaId,
    bool saveHistory = false,
  }) async {
    if (_running && _runningNoticiaId == noticiaId) return;

    if (_running) {
      await stop();
    }

    final payload = jsonEncode({
      'ws_url': wsUrl,
      'token': token,
      'noticia_id': noticiaId,
      'save_history': saveHistory,
    });

    await FlutterForegroundTask.saveData(key: 'tracking_payload', value: payload);

    await FlutterForegroundTask.startService(
      notificationTitle: 'Trayecto en curso',
      notificationText: 'Rastreo activo cada 7 segundos',
      callback: startCallback,
    );

    _running = true;
    _runningNoticiaId = noticiaId;
  }

  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
    _running = false;
    _runningNoticiaId = null;
  }
}
