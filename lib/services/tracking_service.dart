import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/tracking_task_handler.dart';

class TrackingService {
  static bool _running = false;
  static int? _runningNoticiaId;
  static String? _runningToken;

  static String _pfx(String s) => s.length >= 8 ? '${s.substring(0, 8)}...' : s;

  /// ✅ Regla (CORREGIDA):
  /// 1) ApiService.wsToken (mem) si existe
  /// 2) paramToken si existe (esto es CLAVE para pisar prefs viejas)
  /// 3) prefs ws_token como último recurso
  static Future<String> _resolveLatestToken(String paramToken) async {
    final prefs = await SharedPreferences.getInstance();

    final prefsToken = (prefs.getString('ws_token') ?? '').trim();
    final memToken = (ApiService.wsToken ?? '').trim();
    final argToken = paramToken.trim();

    String effective = '';

    if (memToken.isNotEmpty) {
      effective = memToken;
    } else if (argToken.isNotEmpty) {
      effective = argToken;
    } else if (prefsToken.isNotEmpty) {
      effective = prefsToken;
    }

    // ✅ sincroniza a prefs si cambió
    if (effective.isNotEmpty && effective != prefsToken) {
      await prefs.setString('ws_token', effective);
    }

    // ✅ sincroniza a memoria
    if (effective.isNotEmpty) {
      ApiService.wsToken = effective;
    }

    // ✅ fuente de verdad para el isolate (ForegroundTask)
    if (effective.isNotEmpty) {
      await FlutterForegroundTask.saveData(key: 'ws_token_latest', value: effective);
    }

    if (kDebugMode) {
      debugPrint(
        '[TrackingService] mem=${_pfx(memToken)} arg=${_pfx(argToken)} prefs=${_pfx(prefsToken)} -> use=${_pfx(effective)}',
      );
    }

    return effective;
  }

  static Future<void> start({
    required String wsUrl,
    required String token,
    required int noticiaId,
    bool saveHistory = false,
  }) async {
    if (noticiaId <= 0) return;

    final effectiveToken = await _resolveLatestToken(token);

    if (effectiveToken.isEmpty) {
      if (kDebugMode) debugPrint('[TrackingService] Token vacío, no se inicia tracking.');
      return;
    }

    // ✅ si ya corre igual, no reiniciar
    if (_running && _runningNoticiaId == noticiaId && _runningToken == effectiveToken) {
      return;
    }

    if (_running) {
      await stop();
    }

    final payload = jsonEncode({
      'ws_url': wsUrl,
      'token': effectiveToken, // fallback (handler prefiere ws_token_latest)
      'noticia_id': noticiaId,
      'save_history': saveHistory,
    });

    await FlutterForegroundTask.saveData(key: 'tracking_payload', value: payload);

    await FlutterForegroundTask.startService(
      notificationTitle: 'Trayecto en curso',
      notificationText: 'Conectando…',
      callback: startCallback,
    );

    _running = true;
    _runningNoticiaId = noticiaId;
    _runningToken = effectiveToken;
  }

  static Future<void> stop() async {
    try {
      FlutterForegroundTask.sendDataToTask('STOP_TRACKING');
      await Future.delayed(const Duration(milliseconds: 250));
    } catch (_) {}

    await FlutterForegroundTask.stopService();
    _running = false;
    _runningNoticiaId = null;
    _runningToken = null;
  }
}
