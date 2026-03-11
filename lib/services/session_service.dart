// lib/services/session_service.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../services/api_service.dart';

class SessionService {
  static const _kLoggedIn = 'auth_logged_in';
  static const _kWsToken = 'ws_token';
  static const _kRole = 'auth_role';
  static const _kReporteroId = 'auth_reportero_id';
  static const _kNombre = 'auth_nombre';

  static const _kLoginAtUtc = 'auth_login_at_utc';
  static const _kExpUtc = 'auth_session_exp_utc';
  static const _kExpRaw = 'auth_session_exp_raw';

  static const _kPuedeCrear = 'auth_puede_crear_noticias';
  static const _kVerGestionNoticias = 'auth_puede_ver_gestion_noticias';
  static const _kVerEstadisticas = 'auth_puede_ver_estadisticas';
  static const _kVerRastreoGeneral = 'auth_puede_ver_rastreo_general';
  static const _kVerEmpleadoMes = 'auth_puede_ver_empleado_mes';
  static const _kVerGestion = 'auth_puede_ver_gestion';
  static const _kVerClientes = 'auth_puede_ver_clientes';

  static DateTime? _parseServerExpToUtc(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    // login.php manda: "YYYY-MM-DD HH:MM:SS"
    // lo convertimos a "YYYY-MM-DDTHH:MM:SS" para DateTime.tryParse
    final normalized = s.contains('T') ? s : s.replaceFirst(' ', 'T');
    final dt = DateTime.tryParse(normalized);
    if (dt == null) return null;

    // Como no trae timezone, DateTime lo interpreta como local.
    // Convertimos a UTC para comparar con now().toUtc()
    return dt.toUtc();
  }

  static Future<void> setSessionExpiryFromServerOr8h({String? wsTokenExp}) async {
    final prefs = await SharedPreferences.getInstance();

    final nowUtc = DateTime.now().toUtc();

    DateTime expUtc;
    final parsed = _parseServerExpToUtc((wsTokenExp ?? '').toString());
    if (parsed != null) {
      expUtc = parsed;
      await prefs.setString(_kExpRaw, wsTokenExp!.toString());
    } else {
      expUtc = nowUtc.add(const Duration(hours: 8));
      await prefs.remove(_kExpRaw);
    }

    await prefs.setInt(_kLoginAtUtc, nowUtc.millisecondsSinceEpoch);
    await prefs.setInt(_kExpUtc, expUtc.millisecondsSinceEpoch);
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kLoggedIn) ?? false;
  }

  static Future<bool> isExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool(_kLoggedIn) ?? false;
    if (!loggedIn) return true;

    final expMs = prefs.getInt(_kExpUtc) ?? 0;
    if (expMs <= 0) return true;

    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    return nowMs >= expMs;
  }

  static Future<DateTime?> getExpiryUtc() async {
    final prefs = await SharedPreferences.getInstance();
    final expMs = prefs.getInt(_kExpUtc) ?? 0;
    if (expMs <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(expMs, isUtc: true);
  }

  static Future<void> _stopTrackingService() async {
    if (kIsWeb) return;
    try {
      FlutterForegroundTask.sendDataToTask('STOP_TRACKING');
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (_) {}
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  static bool _toBool(dynamic x) {
    if (x == null) return false;
    if (x is bool) return x;
    if (x is num) return x.toInt() == 1;
    final s = x.toString().trim().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes' || s == 'si';
  }

  static Future<void> saveLoginPayload(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();

    final wsToken = (data['ws_token'] ?? '').toString();
    final role = (data['role'] ?? 'reportero').toString();
    final reporteroId = (data['reportero_id'] is num)
        ? (data['reportero_id'] as num).toInt()
        : int.tryParse((data['reportero_id'] ?? '0').toString()) ?? 0;
    final nombre = (data['nombre'] ?? '').toString();

    if (wsToken.isEmpty || reporteroId <= 0) {
      throw Exception('Payload de login inválido (sin token o id)');
    }

    await prefs.setBool(_kLoggedIn, true);
    await prefs.setString(_kWsToken, wsToken);
    await prefs.setString(_kRole, role);
    await prefs.setInt(_kReporteroId, reporteroId);
    await prefs.setString(_kNombre, nombre);

    // permisos
    final puedeCrear = _toBool(data['puede_crear_noticias']);
    await prefs.setBool(_kPuedeCrear, puedeCrear);

    await prefs.setBool(_kVerGestionNoticias, _toBool(data['puede_ver_gestion_noticias']));
    await prefs.setBool(_kVerEstadisticas, _toBool(data['puede_ver_estadisticas']));
    await prefs.setBool(_kVerRastreoGeneral, _toBool(data['puede_ver_rastreo_general']));
    await prefs.setBool(_kVerEmpleadoMes, _toBool(data['puede_ver_empleado_mes']));
    await prefs.setBool(_kVerGestion, _toBool(data['puede_ver_gestion']));
    await prefs.setBool(_kVerClientes, _toBool(data['puede_ver_clientes']));

    // Expiración
    await setSessionExpiryFromServerOr8h(wsTokenExp: data['ws_token_exp']?.toString());

    // memoria runtime
    ApiService.wsToken = wsToken;

    if (!kIsWeb) {
      try {
        await FlutterForegroundTask.saveData(key: 'ws_token_latest', value: wsToken);
      } catch (_) {}
    }
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();

    await _stopTrackingService();

    await prefs.setBool(_kLoggedIn, false);

    await prefs.remove(_kWsToken);
    await prefs.remove(_kRole);
    await prefs.remove(_kReporteroId);
    await prefs.remove(_kNombre);

    await prefs.remove(_kLoginAtUtc);
    await prefs.remove(_kExpUtc);
    await prefs.remove(_kExpRaw);

    await prefs.remove(_kPuedeCrear);
    await prefs.remove(_kVerGestionNoticias);
    await prefs.remove(_kVerEstadisticas);
    await prefs.remove(_kVerRastreoGeneral);
    await prefs.remove(_kVerEmpleadoMes);
    await prefs.remove(_kVerGestion);
    await prefs.remove(_kVerClientes);

    ApiService.wsToken = '';

    if (!kIsWeb) {
      try {
        await FlutterForegroundTask.saveData(key: 'ws_token_latest', value: '');
      } catch (_) {}
    }
  }
}
