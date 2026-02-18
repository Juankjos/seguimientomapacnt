// lib/screens/cronometro_nota_page.dart
import 'dart:async';
import 'package:flutter/material.dart';

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

class _CronometroNotaPageState extends State<CronometroNotaPage> {
  late Noticia _noticia;

  final Stopwatch _sw = Stopwatch();
  Timer? _ticker;

  bool _running = false;
  bool _saving = false;
  bool _startedOnce = false;

  @override
  void initState() {
    super.initState();
    _noticia = widget.noticia;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sw.stop();
    super.dispose();
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${two(h)}:${two(m)}:${two(s)}';
  }

  void _start() {
    if (_saving) return;
    if (_running) return;

    setState(() {
      _running = true;
      _startedOnce = true;
    });

    _sw.start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _stopTickerAndSw() {
    _sw.stop();
    _ticker?.cancel();
    _ticker = null;
  }

  Future<bool> _confirmarFinalizar() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
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
        );
      },
    );
    return res == true;
  }

  Future<void> _finalizarNota() async {
    if (_saving) return;

    // Si ya hay tiempo registrado, solo regresamos
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

    _stopTickerAndSw();

    setState(() {
      _running = false;
      _saving = true;
    });

    final secs = _sw.elapsed.inSeconds;

    if (secs <= 0) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El tiempo debe ser mayor a 0 segundos.')),
      );
      return;
    }

    try {
      // IMPORTANTE: esto debe devolverte una Noticia ya con tiempoEnNota cargado
      final Noticia updated = await ApiService.guardarTiempoEnNota(
        noticiaId: _noticia.id,
        role: widget.role,
        segundos: secs,
      );

      if (!mounted) return;

      // Actualizamos el estado (por si no regresaras inmediatamente)
      setState(() {
        _noticia = updated;
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tiempo guardado: ${_fmt(Duration(seconds: secs))}')),
      );

      // CLAVE: regresamos la noticia actualizada al Detalle
      Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar tiempo: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final yaGuardado = _noticia.tiempoEnNota != null;

    return PopScope(
      canPop: !_saving, // bloquea back mientras guarda
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (_saving) return;

        // Si está corriendo, confirmamos antes de salir
        if (_running) {
          final salir = await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
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
              );
            },
          );

          if (salir == true && mounted) {
            _stopTickerAndSw();
            Navigator.pop(context); // sin devolver nada
          }
          return;
        }

        // Si no está corriendo, salimos normal (devolviendo _noticia por si acaso)
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
                  _fmt(_sw.elapsed),
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
