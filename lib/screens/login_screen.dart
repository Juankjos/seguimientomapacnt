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

  final FocusNode _nombreFocus = FocusNode();
  final FocusNode _passFocus = FocusNode();

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

  Future<void> _setSessionExpiry8h() async {
    final prefs = await SharedPreferences.getInstance();

    final nowUtc = DateTime.now().toUtc();
    final expUtc = nowUtc.add(const Duration(hours: 8));

    await prefs.setInt('auth_login_at_utc', nowUtc.millisecondsSinceEpoch);
    await prefs.setInt('auth_session_exp_utc', expUtc.millisecondsSinceEpoch);

    if (kDebugMode) {
      debugPrint('[Login] session exp UTC (8h): $expUtc');
    }
  }

  Future<void> configurarTopicsFCM({
    required String role,
    required int reporteroId,
  }) async {
    if (kIsWeb) return;
    final fcm = FirebaseMessaging.instance;

    await fcm.requestPermission(alert: true, badge: true, sound: true);

    final prefs = await SharedPreferences.getInstance();
    final lastReporteroId = prefs.getInt('last_reportero_id');
    final lastRole = prefs.getString('last_role');

    if (lastRole == 'reportero') {
      await fcm.unsubscribeFromTopic('rol_reportero');
      if (lastReporteroId != null) {
        await fcm.unsubscribeFromTopic('reportero_$lastReporteroId');
      }
    } else if (lastRole == 'admin') {
      await fcm.unsubscribeFromTopic('rol_admin');
    }

    if (role == 'reportero') {
      await fcm.subscribeToTopic('rol_reportero');
      await fcm.subscribeToTopic('reportero_$reporteroId');
    } else if (role == 'admin') {
      await fcm.subscribeToTopic('rol_admin');
    }

    await prefs.setInt('last_reportero_id', reporteroId);
    await prefs.setString('last_role', role);
  }

  Future<void> _doLogin() async {
    if (_loading) return;

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
        await _setSessionExpiry8h();

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

        final bool irAgenda = (role == 'admin');

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
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _passwordController.dispose();
    _nombreFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;

    final bool isDesktopLike = kIsWeb ? (w >= 700) : (w >= 900);
    final double maxWidth = isDesktopLike ? 520 : double.infinity;

    final content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Card(
        elevation: isDesktopLike ? 2 : 0,
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.dividerColor.withOpacity(0.8), width: 0.8),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktopLike ? 22 : 16,
            vertical: isDesktopLike ? 22 : 16,
          ),
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.newspaper, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      'Noticias CNT',
                      style: TextStyle(
                        fontSize: isDesktopLike ? 18 : 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: _nombreController,
                  focusNode: _nombreFocus,
                  enabled: !_loading,
                  decoration: const InputDecoration(
                    labelText: 'Usuario',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  onSubmitted: (_) => _passFocus.requestFocus(),
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: _passwordController,
                  focusNode: _passFocus,
                  enabled: !_loading,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _loading ? null : _doLogin(),
                ),

                const SizedBox(height: 16),

                if (_errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.error.withOpacity(0.35),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: theme.colorScheme.error),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                SizedBox(
                  width: double.infinity,
                  height: isDesktopLike ? 46 : 44,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _doLogin,
                    icon: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(_loading ? 'Entrando…' : 'Entrar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final topPad = MediaQuery.of(context).padding.top;
          final bottomPad = MediaQuery.of(context).padding.bottom;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              isDesktopLike ? 24 : 16,
              16,
              16 + bottomPad,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - topPad - bottomPad),
              child: Center(
                child: isDesktopLike
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(height: (h * 0.06).clamp(12.0, 36.0)),
                          content,
                          SizedBox(height: (h * 0.06).clamp(12.0, 36.0)),
                        ],
                      )
                    : content,
              ),
            ),
          );
        },
      ),
    );
  }
}
