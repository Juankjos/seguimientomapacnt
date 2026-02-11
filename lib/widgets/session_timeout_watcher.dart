// lib/widgets/session_timeout_watcher.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/session_service.dart';
import '../screens/login_screen.dart';

class SessionTimeoutWatcher extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const SessionTimeoutWatcher({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  @override
  State<SessionTimeoutWatcher> createState() => _SessionTimeoutWatcherState();
}

class _SessionTimeoutWatcherState extends State<SessionTimeoutWatcher>
    with WidgetsBindingObserver {
  Timer? _logoutTimer;
  Timer? _pulseTimer;

  bool _loggingOut = false;
  int? _scheduledExpMs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 1) al iniciar
    unawaited(_refreshSchedule(checkNow: true));

    // 2) pulso para detectar login/logout sin reiniciar app
    _pulseTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refreshSchedule());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _logoutTimer?.cancel();
    _pulseTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // al volver de background, validar y reprogramar
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshSchedule(checkNow: true));
    }
  }

  Future<void> _refreshSchedule({bool checkNow = false}) async {
    final prefs = await SharedPreferences.getInstance();

    final loggedIn = prefs.getBool('auth_logged_in') ?? false;
    final expMs = prefs.getInt('auth_session_exp_utc') ?? 0;

    if (!loggedIn || expMs <= 0) {
      _logoutTimer?.cancel();
      _scheduledExpMs = null;
      return;
    }

    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final remainingMs = expMs - nowMs;

    if (checkNow && remainingMs <= 0) {
      await _logout(reason: 'Sesión expirada');
      return;
    }

    // si ya está programado para el mismo exp, no reprogramar
    if (_scheduledExpMs == expMs && _logoutTimer != null) return;

    _logoutTimer?.cancel();
    _scheduledExpMs = expMs;

    if (remainingMs <= 0) {
      await _logout(reason: 'Sesión expirada');
      return;
    }

    _logoutTimer = Timer(Duration(milliseconds: remainingMs), () {
      unawaited(_logout(reason: 'Sesión expirada'));
    });
  }

  Future<void> _logout({required String reason}) async {
    if (_loggingOut) return;
    _loggingOut = true;

    await SessionService.clearSession();

    _logoutTimer?.cancel();
    _scheduledExpMs = null;

    final ctx = widget.navigatorKey.currentContext;
    if (ctx != null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(reason)),
      );
    }

    final nav = widget.navigatorKey.currentState;
    if (nav != null) {
      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (r) => false,
      );
    }

    _loggingOut = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
