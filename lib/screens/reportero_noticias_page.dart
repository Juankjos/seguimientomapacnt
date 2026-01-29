// lib/screens/reportero_noticias_page.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/noticia.dart';
import '../models/reportero_admin.dart';
import '../services/api_service.dart';
import 'noticia_detalle_page.dart';

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

class ReporteroNoticiasPage extends StatefulWidget {
  final ReporteroAdmin reportero;

  const ReporteroNoticiasPage({super.key, required this.reportero});

  @override
  State<ReporteroNoticiasPage> createState() => _ReporteroNoticiasPageState();
}

class _ReporteroNoticiasPageState extends State<ReporteroNoticiasPage> {
  bool _cargando = true;
  String? _error;
  bool _reasignando = false;

  Future<void> _onReasignarPressed() async {
    if (_reasignando) return; // por seguridad
    await _abrirMenuReasignar();
  }

  List<Noticia> _items = [];

  bool _modoSeleccion = false;
  final Set<int> _seleccion = {};

  List<ReporteroAdmin> _todosReporteros = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  String _fmtFecha(DateTime? dt) {
    if (dt == null) return 'Sin fecha';
    return DateFormat("d MMM y, HH:mm", 'es_MX').format(dt);
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final noticias = await ApiService.getNoticiasPorReportero(
        reporteroId: widget.reportero.id,
        incluyeCerradas: false,
      );

      final reps = await ApiService.getReporterosAdmin(q: '');

      setState(() {
        _items = noticias;
        _todosReporteros = reps;
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  void _toggleSeleccionMode() {
    setState(() {
      _modoSeleccion = !_modoSeleccion;
      _seleccion.clear();
    });
  }

  void _toggleItem(int noticiaId) {
    setState(() {
      if (_seleccion.contains(noticiaId)) {
        _seleccion.remove(noticiaId);
      } else {
        _seleccion.add(noticiaId);
      }
    });
  }

  void _seleccionarTodo() {
    setState(() {
      _seleccion
        ..clear()
        ..addAll(_items.map((e) => e.id));
      _modoSeleccion = true;
    });
  }

  Future<void> _abrirDetalle(Noticia n) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NoticiaDetallePage(
          noticia: n,
          role: 'admin',
          soloLectura: false,
        ),
      ),
    );

    if (changed == true) {
      await _cargar();
    }
  }

  Future<void> _reasignar({required int? nuevoReporteroId}) async {
    if (_seleccion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos una noticia')),
      );
      return;
    }

    if (_reasignando) return;

    setState(() => _reasignando = true);

    try {
      await ApiService.reasignarNoticias(
        noticiaIds: _seleccion.toList(),
        nuevoReporteroId: nuevoReporteroId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nuevoReporteroId == null ? 'Noticias desasignadas' : 'Noticias reasignadas',
          ),
        ),
      );

      setState(() {
        _modoSeleccion = false;
        _seleccion.clear();
      });

      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _reasignando = false);
    }
  }

  Future<void> _abrirMenuReasignar() async {
    if (!_modoSeleccion) {
      setState(() => _modoSeleccion = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona noticias y vuelve a presionar Reasignar')),
      );
      return;
    }

    if (_seleccion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos una noticia')),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text('Reasignar'),
                subtitle: Text('Elige un reportero destino o desasigna'),
              ),
              const Divider(height: 0),
              ListTile(
                leading: const Icon(Icons.link_off),
                title: const Text('Desasignar (sin reportero)'),
                onTap: () {
                  Navigator.pop(context);
                  _reasignar(nuevoReporteroId: null);
                },
              ),
              const Divider(height: 0),
              ..._todosReporteros
                  .where((r) => r.id != widget.reportero.id)
                  .map(
                    (r) => ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(r.nombre),
                      onTap: () {
                        Navigator.pop(context);
                        _reasignar(nuevoReporteroId: r.id);
                      },
                    ),
                  ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // ===================== UI widgets =====================

  Widget _buildList() {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!),
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(child: Text('Este reportero no tiene noticias asignadas'));
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(_hPad(context), 12, _hPad(context), kIsWeb ? 12 : 90),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final n = _items[i];
        final seleccionado = _seleccion.contains(n.id);

        final subt = [
          if (n.cliente != null && n.cliente!.trim().isNotEmpty) 'Cliente: ${n.cliente}',
          'Cita: ${_fmtFecha(n.fechaCita)}',
          n.pendiente ? 'Estado: Pendiente' : 'Estado: Cerrada',
        ].join(' • ');

        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            if (_modoSeleccion) {
              _toggleItem(n.id);
            } else {
              await _abrirDetalle(n);
            }
          },
          onLongPress: () {
            if (!_modoSeleccion) setState(() => _modoSeleccion = true);
            _toggleItem(n.id);
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(
                color: seleccionado ? Theme.of(context).colorScheme.primary : Colors.black12,
                width: seleccionado ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (_modoSeleccion)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Checkbox(
                      value: seleccionado,
                      onChanged: (_) => _toggleItem(n.id),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.noticia,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subt,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sidePanel() {
    final theme = Theme.of(context);
    final canReasignar = _seleccion.isNotEmpty && !_reasignando;

    return Card(
      elevation: 0.6,
      shape: _softShape(theme),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Acciones',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.55),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.dividerColor.withOpacity(0.6), width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Seleccionadas: ${_seleccion.length}',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _modoSeleccion
                        ? 'Haz clic en varias noticias para marcarlas.'
                        : 'Activa selección para reasignar.',
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: Icon(_modoSeleccion ? Icons.close : Icons.checklist),
                label: Text(_modoSeleccion ? 'Salir de selección' : 'Modo selección'),
                onPressed: _toggleSeleccionMode,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.select_all),
                label: const Text('Seleccionar todo'),
                onPressed: _items.isEmpty ? null : _seleccionarTodo,
              ),
            ),
            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canReasignar ? _onReasignarPressed : null,
                icon: _reasignando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.swap_horiz),
                label: Text(_reasignando ? 'Reasignando…' : 'Reasignar'),
              ),
            ),

            const SizedBox(height: 10),
            const Divider(height: 20),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Refrescar'),
                onPressed: _cargar,
              ),
            ),

            const Spacer(),

            Text(
              'Tip: click normal abre detalle, click largo marca selección.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== Build =====================

  @override
  Widget build(BuildContext context) {
    final titulo = 'Noticias • ${widget.reportero.nombre}';
    final wide = _isWebWide(context);

    final canReasignar = _seleccion.isNotEmpty && !_reasignando;

    if (wide) {
      return Scaffold(
        appBar: AppBar(
          title: Text(titulo),
          actions: [
            IconButton(
              tooltip: 'Refrescar',
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _wrapWebWidth(
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 8,
                child: _maybeScrollbar(child: _buildList()),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(12, 12, _hPad(context), 12),
                child: SizedBox(
                  width: 360,
                  child: _sidePanel(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(titulo),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: _modoSeleccion ? 'Salir de selección' : 'Seleccionar',
            onPressed: _toggleSeleccionMode,
            icon: Icon(_modoSeleccion ? Icons.close : Icons.checklist),
          ),
          IconButton(
            tooltip: 'Seleccionar todo',
            onPressed: _items.isEmpty ? null : _seleccionarTodo,
            icon: const Icon(Icons.select_all),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: canReasignar ? _onReasignarPressed : null,
        backgroundColor: canReasignar ? null : Colors.grey.shade400,
        foregroundColor: canReasignar ? null : Colors.grey.shade800,
        icon: _reasignando
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.swap_horiz),
        label: Text(_reasignando ? 'Reasignando…' : 'Reasignar'),
      ),
      body: _buildList(),
    );
  }
}
