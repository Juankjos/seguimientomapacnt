import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/noticia.dart';
import '../services/api_service.dart';

const _kPrefsKeyNoticiasNuevas = 'noticias_nuevas_timestamps';
const _kNuevaDuracionMs = 1 * 60 * 1000;

class TomarNoticiasPage extends StatefulWidget {
  final int reporteroId;
  final String reporteroNombre;

  const TomarNoticiasPage({
    super.key,
    required this.reporteroId,
    required this.reporteroNombre,
  });

  @override
  State<TomarNoticiasPage> createState() => _TomarNoticiasPageState();
}

class _TomarNoticiasPageState extends State<TomarNoticiasPage> {
  bool _loading = false;
  String? _error;
  List<Noticia> _noticias = [];
  Set<int> _nuevasNoticias = {};

  Map<String, int> _timestamps = {};

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _cargarNoticias();
    _iniciarTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ------------ SharedPreferences helpers ------------

  Future<Map<String, int>> _cargarTimestampsGuardados() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKeyNoticiasNuevas);
    if (raw == null || raw.isEmpty) return {};

    try {
      final Map<String, dynamic> decoded = jsonDecode(raw);
      return decoded.map((key, value) => MapEntry(key, value as int));
    } catch (_) {
      return {};
    }
  }

  Future<void> _guardarTimestamps(Map<String, int> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsKeyNoticiasNuevas, jsonEncode(map));
  }

  // ------------ Timer para actualizar el estado "nuevo" en tiempo real ------------

  void _iniciarTimer() {
    _timer?.cancel();
    // Revisamos cada 5 segundos, se puede ajustar
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _actualizarEstadoNuevasPorTiempo();
    });
  }

  Future<void> _actualizarEstadoNuevasPorTiempo() async {
    if (_timestamps.isEmpty || _noticias.isEmpty) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;

    bool huboCambiosTimestamps = false;

    _timestamps.removeWhere((key, ts) {
      final expired = nowMs - ts > _kNuevaDuracionMs;
      if (expired) huboCambiosTimestamps = true;
      return expired;
    });

    final nuevas = <int>{};
    for (final n in _noticias) {
      final key = n.id.toString();
      final ts = _timestamps[key];
      if (ts != null && nowMs - ts <= _kNuevaDuracionMs) {
        nuevas.add(n.id);
      }
    }

    if (!setEquals(_nuevasNoticias, nuevas)) {
      setState(() {
        _nuevasNoticias = nuevas;
      });
    }

    if (huboCambiosTimestamps) {
      await _guardarTimestamps(_timestamps);
    }
  }

  // ------------ Carga de noticias desde backend ------------

  Future<void> _cargarNoticias() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      var timestamps = await _cargarTimestampsGuardados();

      timestamps.removeWhere((key, ts) => nowMs - ts > _kNuevaDuracionMs);

      final list = await ApiService.getNoticiasDisponibles();

      final nuevas = <int>{};

      for (final n in list) {
        final key = n.id.toString();

        if (!timestamps.containsKey(key)) {
          timestamps[key] = nowMs;
          nuevas.add(n.id);
        } else {
          final ts = timestamps[key]!;
          if (nowMs - ts <= _kNuevaDuracionMs) {
            nuevas.add(n.id);
          }
        }
      }

      await _guardarTimestamps(timestamps);

      setState(() {
        _noticias = list;
        _nuevasNoticias = nuevas;
        _timestamps = timestamps;
      });

      _actualizarEstadoNuevasPorTiempo();
    } catch (e) {
      setState(() {
        _error = 'Error al cargar noticias: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  // ------------ Lógica para tomar noticias ------------

  Future<void> _confirmarTomar(Noticia noticia) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tomar noticia'),
        content: Text(
          '¿Seguro que deseas tomar la noticia:\n\n"${noticia.noticia}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await _tomarNoticia(noticia);
    }
  }

  Future<void> _tomarNoticia(Noticia noticia) async {
    try {
      await ApiService.tomarNoticia(
        reporteroId: widget.reporteroId,
        noticiaId: noticia.id,
      );

      setState(() {
        _noticias.removeWhere((n) => n.id == noticia.id);
        _nuevasNoticias.remove(noticia.id);
        _timestamps.remove(noticia.id.toString());
      });

      await _guardarTimestamps(_timestamps);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Has tomado la noticia "${noticia.noticia}".'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo tomar la noticia: $e'),
        ),
      );
    }
  }

  // ------------ UI ------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tomar noticias'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _cargarNoticias,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargarNoticias,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 40),
          Center(child: Text(_error!)),
        ],
      );
    }

    if (_noticias.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 40),
          Center(child: Text('No hay noticias por ahora')),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _noticias.length,
      itemBuilder: (context, index) {
        final n = _noticias[index];
        final esNueva = _nuevasNoticias.contains(n.id);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          color: esNueva ? const Color(0xFFE3F2FD) : null, // azul claro
          child: ListTile(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (esNueva)
                  const Text(
                    '¡Nueva noticia!',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(255, 124, 30, 28),
                    ),
                  ),
                Text(
                  n.noticia,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (n.descripcion != null &&
                    n.descripcion!.trim().isNotEmpty)
                  Text(n.descripcion!),
                if (n.cliente != null &&
                    n.cliente!.trim().isNotEmpty)
                  Text('Cliente: ${n.cliente}'),
              ],
            ),
            trailing: const Icon(Icons.add_circle_outline),
            onTap: () => _confirmarTomar(n),
          ),
        );
      },
    );
  }
}
