import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/noticia.dart';
import '../models/reportero_admin.dart';
import '../services/api_service.dart';
import 'noticia_detalle_page.dart';

class ReporteroNoticiasPage extends StatefulWidget {
  final ReporteroAdmin reportero;

  const ReporteroNoticiasPage({super.key, required this.reportero});

  @override
  State<ReporteroNoticiasPage> createState() => _ReporteroNoticiasPageState();
}

class _ReporteroNoticiasPageState extends State<ReporteroNoticiasPage> {
  bool _cargando = true;
  String? _error;

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
        incluyeCerradas: true,
      );

      // para el selector de reasignación
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
          soloLectura: false, // admin puede editar según tu lógica interna
        ),
      ),
    );

    // Si en el detalle se hizo algún cambio y regresó true, recargamos
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

    try {
      await ApiService.reasignarNoticias(
        noticiaIds: _seleccion.toList(),
        nuevoReporteroId: nuevoReporteroId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nuevoReporteroId == null
                ? 'Noticias desasignadas'
                : 'Noticias reasignadas',
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
    }
  }

  Future<void> _abrirMenuReasignar() async {
    // Si aún no estamos en modo selección, actívalo (como guía al usuario)
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

  @override
  Widget build(BuildContext context) {
    final titulo = 'Noticias • ${widget.reportero.nombre}';

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
        onPressed: _abrirMenuReasignar,
        icon: const Icon(Icons.swap_horiz),
        label: Text(_modoSeleccion ? 'Reasignar (${_seleccion.length})' : 'Reasignar'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)))
              : _items.isEmpty
                  ? const Center(child: Text('Este reportero no tiene noticias asignadas'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
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
                                color: seleccionado
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.black12,
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
                    ),
    );
  }
}
