// lib/screens/tomar_noticias_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, setEquals;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../models/noticia.dart';
import '../services/api_service.dart';

const _kPrefsKeyNoticiasNuevas = 'noticias_nuevas_timestamps';
const _kNuevaDuracionMs = 1 * 60 * 1000;

// ===== Web layout helpers =====
const double _kWebMaxContentWidth = 1200;
const double _kWebWideBreakpoint = 980;

bool _isWebWide(BuildContext context) =>
    kIsWeb && MediaQuery.of(context).size.width >= _kWebWideBreakpoint;

double _hPad(BuildContext context) => _isWebWide(context) ? 20 : 12;

Widget _wrapWebWidth(Widget child) {
  if (!kIsWeb) return child;
  return Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _kWebMaxContentWidth),
      child: child,
    ),
  );
}

Widget _maybeScrollbar({required Widget child}) {
  if (!kIsWeb) return child;
  return Scrollbar(thumbVisibility: true, interactive: true, child: child);
}

ShapeBorder _softShape(ThemeData theme) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: theme.dividerColor.withOpacity(0.70),
        width: 0.9,
      ),
    );

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

  void _iniciarTimer() {
    _timer?.cancel();
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
      setState(() => _nuevasNoticias = nuevas);
    }

    if (huboCambiosTimestamps) {
      await _guardarTimestamps(_timestamps);
    }
  }

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
      setState(() => _error = 'Error al cargar noticias: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtFechaHoraCita(DateTime? dt) {
    if (dt == null) return 'Sin fecha';

    final fechaRaw = DateFormat('dd/MMMM/yyyy', 'es_MX').format(dt);
    final parts = fechaRaw.split('/');
    final mes = parts.length >= 2 && parts[1].isNotEmpty
        ? '${parts[1][0].toUpperCase()}${parts[1].substring(1)}'
        : '';
    final fecha = parts.length == 3 ? '${parts[0]}/$mes/${parts[2]}' : fechaRaw;

    var hora = DateFormat('hh:mm a', 'en_US').format(dt).toLowerCase();
    hora = hora.replaceAll('am', 'a.m.').replaceAll('pm', 'p.m.');

    return '$fecha $hora';
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
        SnackBar(content: Text('Has tomado la noticia "${noticia.noticia}".')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo tomar la noticia: $e')),
      );
    }
  }

  // ------------ UI ------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = _isWebWide(context);

    final list = RefreshIndicator(
      onRefresh: _cargarNoticias,
      child: _maybeScrollbar(
        child: _buildBodyList(
          padding: EdgeInsets.all(_hPad(context)),
        ),
      ),
    );

    if (wide) {
      final rightPanel = Padding(
        padding: EdgeInsets.fromLTRB(12, 12, _hPad(context), 12),
        child: SizedBox(
          width: 360,
          child: Card(
            elevation: 0.6,
            shape: _softShape(theme),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.inbox_outlined),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Disponibles',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Actualizar',
                        onPressed: _loading ? null : _cargarNoticias,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Reportero: ${widget.reporteroNombre}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.dividerColor.withOpacity(0.6),
                        width: 0.8,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total: ${_noticias.length}',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: Text(_loading ? 'Actualizando…' : 'Actualizar lista'),
                      onPressed: _loading ? null : _cargarNoticias,
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
          title: const Text('Tomar noticias'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar',
              onPressed: _loading ? null : _cargarNoticias,
            ),
          ],
        ),
        body: _wrapWebWidth(
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 8, child: list),
              Expanded(flex: 0, child: rightPanel),
            ],
          ),
        ),
      );
    }

    // ---- Mobile / narrow ----
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
      body: list,
    );
  }

  Widget _buildBodyList({required EdgeInsets padding}) {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: const [
          SizedBox(height: 160),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: [
          const SizedBox(height: 40),
          Center(child: Text(_error!)),
        ],
      );
    }

    if (_noticias.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: const [
          SizedBox(height: 40),
          Center(child: Text('No hay noticias por ahora')),
        ],
      );
    }

    final theme = Theme.of(context);

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      itemCount: _noticias.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final n = _noticias[index];
        final esNueva = _nuevasNoticias.contains(n.id);

        final colorNueva = const Color(0xFFE3F2FD);

        return Card(
          elevation: kIsWeb ? 0.6 : 2,
          shape: _softShape(theme),
          color: esNueva ? colorNueva : null,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (esNueva)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 124, 30, 28).withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color.fromARGB(255, 124, 30, 28).withOpacity(0.35),
                      ),
                    ),
                    child: const Text(
                      '¡Nueva noticia!',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color.fromARGB(255, 124, 30, 28),
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (esNueva) const SizedBox(height: 8),
                Text(
                  n.noticia,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (n.descripcion != null && n.descripcion!.trim().isNotEmpty) ...[
                    Text(n.descripcion!),
                    const SizedBox(height: 4),
                  ],
                  Text('Cita: ${_fmtFechaHoraCita(n.fechaCita)}'),
                  if (n.cliente != null && n.cliente!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('Cliente: ${n.cliente}'),
                  ],
                ],
              ),
            ),
            trailing: const Icon(Icons.add_circle_outline),
            onTap: () => _confirmarTomar(n),
          ),
        );
      },
    );
  }
}
