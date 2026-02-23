// lib/screens/cronometro_nota_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;
import 'package:timezone/timezone.dart' as tz;

import '../models/noticia.dart';
import '../services/api_service.dart';

class CronometroNotaPage extends StatefulWidget {
  final Noticia noticia;
  final String role;

  const CronometroNotaPage({
    super.key,
    required this.noticia,
    required this.role,
  });

  @override
  State<CronometroNotaPage> createState() => _CronometroNotaPageState();
}

class _CronometroNotaPageState extends State<CronometroNotaPage>
    with WidgetsBindingObserver {
  late Noticia _noticia;

  Timer? _ticker;

  bool _saving = false;
  bool _startedOnce = false;

  // ====== Estado persistible ======
  int? _startEpochMs;
  int _accumulatedMs = 0;

  bool get _running => _startEpochMs != null;

  static const _kRunning = 'nota_timer_running';
  static const _kStartMs = 'nota_timer_start_ms';
  static const _kAccMs = 'nota_timer_acc_ms';
  static const _kNoticiaId = 'nota_timer_noticia_id';
  static const _kNoticiaTitulo = 'nota_timer_noticia_titulo';

  // ====== Notificación 15 min ======
  static const String _timerChannelId = 'tvc_timer_high';
  static const String _timerChannelName = 'Cronómetro';
  static const String _timerChannelDesc = 'Alertas del cronómetro de notas';

  // DEBUG PRUEBAS
  final fln.FlutterLocalNotificationsPlugin _notifs =
      fln.FlutterLocalNotificationsPlugin();

  int get _notif15Id => 900000000 + _noticia.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _noticia = widget.noticia;
    _restoreTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      if (_running) _startTicker();
      setState(() {});
    } else if (state == AppLifecycleState.paused) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _restoreTimer() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRunning = prefs.getBool(_kRunning) ?? false;
    final savedId = prefs.getInt(_kNoticiaId);
    final savedStart = prefs.getInt(_kStartMs);
    final savedAcc = prefs.getInt(_kAccMs) ?? 0;

    if (savedId == _noticia.id && savedRunning && savedStart != null) {
      setState(() {
        _startEpochMs = savedStart;
        _accumulatedMs = savedAcc;
        _startedOnce = true;
      });
      _startTicker();
      await _schedule15MinWarningIfNeeded();
    } else {
      setState(() {
        _startEpochMs = null;
        _accumulatedMs = 0;
      });
    }
  }

  Future<void> _persistTimer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kNoticiaId, _noticia.id);
    await prefs.setString(_kNoticiaTitulo, _noticia.noticia);
    await prefs.setBool(_kRunning, _running);

    if (_startEpochMs != null) {
      await prefs.setInt(_kStartMs, _startEpochMs!);
    } else {
      await prefs.remove(_kStartMs);
    }

    await prefs.setInt(_kAccMs, _accumulatedMs);
  }

  Future<void> _clearPersistedTimer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRunning);
    await prefs.remove(_kStartMs);
    await prefs.remove(_kAccMs);
    await prefs.remove(_kNoticiaId);
    await prefs.remove(_kNoticiaTitulo);

    await _cancel15MinWarning();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  Duration get _elapsed {
    final now = DateTime.now().millisecondsSinceEpoch;
    final runningMs = (_startEpochMs != null) ? (now - _startEpochMs!) : 0;
    return Duration(milliseconds: _accumulatedMs + runningMs);
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${two(h)}:${two(m)}:${two(s)}';
  }

  Future<void> _cancel15MinWarning() async {
    if (kIsWeb) return;
    try {
      await _notifs.cancel(id: _notif15Id);
    } catch (_) {}
  }

  Future<void> _schedule15MinWarningIfNeeded() async {
    if (kIsWeb) return;
    if (_startEpochMs == null) return;

    DateTime warnAt;
    int? limitMinForMsg;


    final limitMin = _noticia.limiteTiempoMinutos;
    if (limitMin == null || limitMin <= 15) return;

    final warnAtEpochMs = _startEpochMs! + ((limitMin - 15) * 60 * 1000);
    warnAt = DateTime.fromMillisecondsSinceEpoch(warnAtEpochMs);

    if (warnAt.isBefore(DateTime.now())) return;
    limitMinForMsg = limitMin;

    await _cancel15MinWarning();

    final details = fln.NotificationDetails(
      android: fln.AndroidNotificationDetails(
        _timerChannelId,
        _timerChannelName,
        channelDescription: _timerChannelDesc,
        importance: fln.Importance.high,
        priority: fln.Priority.high,
        icon: 'ic_stat_notification',
      ),
      iOS: const fln.DarwinNotificationDetails(),
    );

    final payload = jsonEncode({
      'tipo': 'timer_15m',
      'noticia_id': _noticia.id,
    });

    final body =
    'A "${_noticia.noticia}" le quedan 15 minutos para llegar al límite de $limitMinForMsg min.';

    final tz.TZDateTime tzWhen = tz.TZDateTime.from(warnAt, tz.local);
    try {
      await _notifs.zonedSchedule(
        id: _notif15Id,
        title: 'Cronómetro: 15 min restantes',
        body: body,
        scheduledDate: tzWhen,
        notificationDetails: details,
        androidScheduleMode: fln.AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
    } catch (_) {
      await _notifs.zonedSchedule(
        id: _notif15Id,
        title: 'Cronómetro: 15 min restantes',
        body: body,
        scheduledDate: tzWhen,
        notificationDetails: details,
        androidScheduleMode: fln.AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    }
  }

  Future<void> _start() async {
    if (_saving) return;
    if (_running) return;

    final prefs = await SharedPreferences.getInstance();
    final running = prefs.getBool(_kRunning) ?? false;
    final savedId = prefs.getInt(_kNoticiaId);
    final savedStart = prefs.getInt(_kStartMs);

    final otroActivo = running && savedStart != null && savedId != null && savedId != _noticia.id;
    if (otroActivo && mounted) {
      final titulo = (prefs.getString(_kNoticiaTitulo) ?? '').trim();
      final display = titulo.isNotEmpty ? titulo : 'ID: $savedId';

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Cronómetro activo'),
          content: Text(
            'Ya tienes un cronómetro activo en otra nota:\n'
            '$display\n\n'
            'Finalízalo antes de iniciar uno nuevo.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      _startedOnce = true;
      _startEpochMs = DateTime.now().millisecondsSinceEpoch;
    });

    await _persistTimer();
    await _schedule15MinWarningIfNeeded();
    _startTicker();
  }

  void _stopVisualTickerOnly() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<bool> _confirmarFinalizar() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalizar nota'),
        content: const Text('¿Seguro que deseas finalizar y guardar el tiempo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sí, finalizar'),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _finalizarNota() async {
    if (_saving) return;

    if (_noticia.tiempoEnNota != null) {
      Navigator.pop(context, _noticia);
      return;
    }

    if (!_startedOnce) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero debes iniciar el cronómetro.')),
      );
      return;
    }

    if (!_running) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El cronómetro no está corriendo.')),
      );
      return;
    }

    final ok = await _confirmarFinalizar();
    if (!ok) return;

    setState(() => _saving = true);

    _stopVisualTickerOnly();

    final secs = _elapsed.inSeconds;

    if (secs <= 0) {
      setState(() => _saving = false);
      _startTicker(); // 🔧 reanuda UI si algo salió raro
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El tiempo debe ser mayor a 0 segundos.')),
      );
      return;
    }

    try {
      final updated = await ApiService.guardarTiempoEnNota(
        noticiaId: _noticia.id,
        role: widget.role,
        segundos: secs,
      );

      if (!mounted) return;

      await _clearPersistedTimer();

      setState(() {
        _noticia = updated;
        _saving = false;
        _startEpochMs = null;
        _accumulatedMs = 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tiempo guardado: ${_fmt(Duration(seconds: secs))}')),
      );

      Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);

      // 🔧 Si falló el guardado, el cronómetro sigue corriendo: reanuda el ticker
      if (_running) _startTicker();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar tiempo: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final yaGuardado = _noticia.tiempoEnNota != null;

    return PopScope(
      canPop: !_saving,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (_saving) return;

        if (_running) {
          final salir = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Salir del cronómetro'),
              content: const Text('El cronómetro está corriendo. ¿Deseas salir?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Quedarme'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Salir'),
                ),
              ],
            ),
          );

          if (salir == true && mounted) {
            _stopVisualTickerOnly();
            Navigator.pop(context);
          }
          return;
        }

        if (mounted) Navigator.pop(context, _noticia);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Cronometrar Nota')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _fmt(_elapsed),
                  style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 18),
                if (yaGuardado) ...[
                  Text(
                    'Esta nota ya tiene tiempo registrado: ${_fmt(Duration(seconds: _noticia.tiempoEnNota!))}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, _noticia),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Volver'),
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (_running || _saving) ? null : _start,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Iniciar'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_running && !_saving) ? _finalizarNota : null,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.flag),
                      label: Text(_saving ? 'Guardando...' : 'Finalizar Nota'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}