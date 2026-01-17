// login_screen.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../services/api_service.dart';
import 'noticias_page.dart';
import 'agenda_page.dart';
import '../auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _loading = false;
  String? _errorMessage;

  String _pfx(String s) => s.length >= 8 ? '${s.substring(0, 8)}...' : s;

  bool _parseBoolish(dynamic v) {
    if (v is bool) return v;
    final s = v?.toString().trim().toLowerCase() ?? '';
    return s == '1' || s == 'true' || s == 'yes' || s == 'si';
  }

  Future<void> _stopAnyTrackingService() async {
    if (kIsWeb) return;
    try {
      FlutterForegroundTask.sendDataToTask('STOP_TRACKING');
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (_) {}
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  Future<void> _persistWsToken(String wsToken) async {
    final token = wsToken.trim();
    if (token.isEmpty) return;

    ApiService.wsToken = token;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ws_token', token);

    if (!kIsWeb) {
      try {
        await FlutterForegroundTask.saveData(key: 'ws_token_latest', value: token);
      } catch (_) {}
    }

    if (kDebugMode) {
      debugPrint('[Login] ws_token=${_pfx(token)} guardado mem/prefs/ws_token_latest');
    }
  }

  Future<void> _setSessionExpiry24h() async {
    final prefs = await SharedPreferences.getInstance();

    final nowUtc = DateTime.now().toUtc();
    final expUtc = nowUtc.add(const Duration(hours: 24));

    await prefs.setInt('auth_login_at_utc', nowUtc.millisecondsSinceEpoch);
    await prefs.setInt('auth_session_exp_utc', expUtc.millisecondsSinceEpoch);

    if (kDebugMode) {
      debugPrint('[Login] session exp UTC: $expUtc');
    }
  }

  Future<void> configurarTopicsFCM({
    required String role,
    required int reporteroId,
  }) async {
    final fcm = FirebaseMessaging.instance;

    await fcm.requestPermission(alert: true, badge: true, sound: true);

    final prefs = await SharedPreferences.getInstance();
    final lastReporteroId = prefs.getInt('last_reportero_id');
    final lastRole = prefs.getString('last_role');

    // 1) Limpia suscripciones previas
    if (lastRole == 'reportero') {
      await fcm.unsubscribeFromTopic('rol_reportero');
      if (lastReporteroId != null) {
        await fcm.unsubscribeFromTopic('reportero_$lastReporteroId');
      }
    } else if (lastRole == 'admin') {
      await fcm.unsubscribeFromTopic('rol_admin');
    }

    // 2) Suscripción actual
    if (role == 'reportero') {
      await fcm.subscribeToTopic('rol_reportero');
      await fcm.subscribeToTopic('reportero_$reporteroId');
    } else if (role == 'admin') {
      await fcm.subscribeToTopic('rol_admin');
    }

    // 3) Guarda estado
    await prefs.setInt('last_reportero_id', reporteroId);
    await prefs.setString('last_role', role);
  }

  Future<void> _doLogin() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final data = await ApiService.login(
        _nombreController.text.trim(),
        _passwordController.text.trim(),
      );

      if (data['success'] == true) {
        final int reporteroId = int.parse(data['reportero_id'].toString());
        final String nombre = (data['nombre'] ?? '').toString();
        final String role = (data['role'] ?? 'reportero').toString();
        final String wsToken = (data['ws_token'] ?? '').toString();

        final bool puedeCrearNoticias = _parseBoolish(data['puede_crear_noticias']);

        await _stopAnyTrackingService();

        await _persistWsToken(wsToken);

        await _setSessionExpiry24h();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('auth_reportero_id', reporteroId);
        await prefs.setString('auth_nombre', nombre);
        await prefs.setString('auth_role', role);
        await prefs.setBool('auth_logged_in', true);

        await prefs.setBool('auth_puede_crear_noticias', puedeCrearNoticias);
        await prefs.setBool('last_puede_crear_noticias', puedeCrearNoticias);

        AuthController.puedeCrearNoticias.value = puedeCrearNoticias;

        // topics FCM
        await configurarTopicsFCM(role: role, reporteroId: reporteroId);

        if (!mounted) return;

        final bool irAgenda = (role == 'admin') || puedeCrearNoticias;

        if (irAgenda) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => AgendaPage(
                reporteroId: reporteroId,
                reporteroNombre: nombre,
                esAdmin: role == 'admin',
                puedeCrearNoticias: puedeCrearNoticias,
              ),
            ),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => NoticiasPage(
                reporteroId: reporteroId,
                reporteroNombre: nombre,
                role: role,
                wsToken: wsToken,
              ),
            ),
          );
        }
      } else {
        setState(() {
          _errorMessage = data['message']?.toString() ?? 'Error de login';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al conectar con el servidor: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Noticias CNT'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nombreController,
              decoration: const InputDecoration(
                labelText: 'Usuario',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Contraseña',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _doLogin,
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Entrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
