// session_gate.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../services/api_service.dart';
import 'login_screen.dart';
import 'noticias_page.dart';
import 'agenda_page.dart';

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  bool _loading = true;
  Widget? _target;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _stopTrackingService() async {
    if (kIsWeb) return;
    try {
      FlutterForegroundTask.sendDataToTask('STOP_TRACKING');
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (_) {}
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();

    await _stopTrackingService();

    await prefs.setBool('auth_logged_in', false);
    await prefs.remove('ws_token');
    await prefs.remove('auth_role');
    await prefs.remove('auth_reportero_id');
    await prefs.remove('auth_nombre');

    // expiración local
    await prefs.remove('auth_login_at_utc');
    await prefs.remove('auth_session_exp_utc');

    ApiService.wsToken = '';

    if (!kIsWeb) {
      try {
        await FlutterForegroundTask.saveData(key: 'ws_token_latest', value: '');
      } catch (_) {}
    }
  }

  bool _isSessionExpired(SharedPreferences prefs) {
    final expMs = prefs.getInt('auth_session_exp_utc') ?? 0;
    if (expMs <= 0) return true;
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    return nowMs >= expMs;
  }

  Future<void> _syncTokenToForegroundStore(String token) async {
    if (kIsWeb) return;
    final t = token.trim();
    if (t.isEmpty) return;
    try {
      await FlutterForegroundTask.saveData(key: 'ws_token_latest', value: t);
    } catch (_) {}
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();

    final loggedIn = prefs.getBool('auth_logged_in') ?? false;
    final token = prefs.getString('ws_token') ?? '';
    final role = prefs.getString('auth_role') ?? '';
    final reporteroId = prefs.getInt('auth_reportero_id') ?? 0;
    final nombre = prefs.getString('auth_nombre') ?? '';

    if (!loggedIn || token.isEmpty || role.isEmpty || reporteroId <= 0) {
      setState(() {
        _target = const LoginScreen();
        _loading = false;
      });
      return;
    }

    if (_isSessionExpired(prefs)) {
      await _clearSession();
      setState(() {
        _target = const LoginScreen();
        _loading = false;
      });
      return;
    }

    ApiService.wsToken = token;

    await _syncTokenToForegroundStore(token);

    setState(() {
      if (role == 'admin') {
        _target = AgendaPage(
          reporteroId: reporteroId,
          reporteroNombre: nombre,
          esAdmin: true,
        );
      } else {
        _target = NoticiasPage(
          reporteroId: reporteroId,
          reporteroNombre: nombre,
          role: role,
          wsToken: token,
        );
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _target ?? const LoginScreen();
  }
}
