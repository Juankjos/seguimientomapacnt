// session_gate.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();

    final loggedIn = prefs.getBool('auth_logged_in') ?? false;
    final token = prefs.getString('ws_token') ?? '';
    final role = prefs.getString('auth_role') ?? '';
    final reporteroId = prefs.getInt('auth_reportero_id') ?? 0;
    final nombre = prefs.getString('auth_nombre') ?? '';

    // Si no hay sesión válida -> login
    if (!loggedIn || token.isEmpty || role.isEmpty || reporteroId <= 0) {
      setState(() {
        _target = const LoginScreen();
        _loading = false;
      });
      return;
    }

    // ✅ restaura token a memoria para WS / API
    ApiService.wsToken = token;

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
