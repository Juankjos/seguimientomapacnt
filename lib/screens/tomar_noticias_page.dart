import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/noticia.dart';
import '../services/api_service.dart';

const _kPrefsKeyNoticiasNuevas = 'noticias_nuevas_timestamps';
const _kNuevaDuracionMs = 10 * 60 * 1000; // 10 minutos

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
  Set<int> _nuevasNoticias = {}; // IDs de noticias que son "nuevas" visualmente

  @override
  void initState() {
    super.initState();
    _cargarNoticias();
  }

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

  Future<void> _cargarNoticias() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // 1) Cargar timestamps de primeras apariciones
      var timestamps = await _cargarTimestampsGuardados();

      // 2) Limpiar entradas viejas (>10min)
      timestamps.removeWhere((key, ts) => nowMs - ts > _kNuevaDuracionMs);

      // 3) Traer noticias disponibles del backend
      final list = await ApiService.getNoticiasDisponibles();

      final nuevas = <int>{};

      for (final n in list) {
        final key = n.id.toString();

        if (!timestamps.containsKey(key)) {
          // Primera vez que aparece en el feed → la marcamos nueva
          timestamps[key] = nowMs;
          nuevas.add(n.id);
        } else {
          final ts = timestamps[key]!;
          if (nowMs - ts <= _kNuevaDuracionMs) {
            // Aún está dentro de la ventana de 10 minutos → sigue siendo nueva
            nuevas.add(n.id);
          }
        }
      }

      // 4) Guardar de nuevo timestamps (con limpiezas + nuevas entradas)
      await _guardarTimestamps(timestamps);

      setState(() {
        _noticias = list;
        _nuevasNoticias = nuevas;
      });
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
      });

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
                  Text(
                    '¡Nueva noticia!',
                    style: const TextStyle(
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
