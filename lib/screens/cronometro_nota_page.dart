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
  final Stopwatch _sw = Stopwatch();
  Timer? _ticker;

  bool _running = false;
  bool _saving = false;

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${two(h)}:${two(m)}:${two(s)}';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _start() {
    if (_running || _saving) return;
    setState(() => _running = true);
    _sw.start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<void> _finalizarNota() async {
    if (_saving) return;

    _sw.stop();
    _ticker?.cancel();
    setState(() {
      _running = false;
      _saving = true;
    });

    final secs = _sw.elapsed.inSeconds;
    if (secs <= 0) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El tiempo debe ser mayor a 0 segundos.')),
      );
      return;
    }

    try {
      final updated = await ApiService.guardarTiempoEnNota(
        noticiaId: widget.noticia.id,
        role: widget.role,
        segundos: secs,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tiempo guardado: ${_fmt(Duration(seconds: secs))}')),
      );

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
    final yaGuardado = widget.noticia.tiempoEnNota != null;

    return Scaffold(
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

              if (yaGuardado)
                const Text(
                  'Esta nota ya tiene tiempo registrado.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),

              if (!yaGuardado) ...[
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
                    onPressed: _saving ? null : _finalizarNota,
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
    );
  }
}
