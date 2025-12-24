import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/noticia.dart';
import '../services/api_service.dart';
import '../services/api_service.dart' show ReporteroBusqueda;
import 'noticia_detalle_page.dart';

class NoticiasSinAsignarPage extends StatefulWidget {
  const NoticiasSinAsignarPage({super.key});

  @override
  State<NoticiasSinAsignarPage> createState() => _NoticiasSinAsignarPageState();
}

class _NoticiasSinAsignarPageState extends State<NoticiasSinAsignarPage> {
  bool _cargando = true;
  String? _error;

  List<Noticia> _items = [];

  bool _modoSeleccion = false;
  final Set<int> _seleccion = {};

  bool _asignando = false;
  bool _huboCambios = false;

  String _fmtFecha(DateTime? dt) {
    if (dt == null) return 'Sin fecha';
    return DateFormat("d MMM y, h:mm a", 'es_MX').format(dt);
  }

  bool _borrando = false;

  Future<void> _borrarSeleccion() async {
    if (_borrando || _asignando) return;

    if (_seleccion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos una noticia')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar noticia(s)'),
        content: Text(
          '¿Seguro que deseas borrar ${_seleccion.length} noticia(s)?\n'
          'Solo se borrarán las que sigan sin reportero asignado.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _borrando = true);

    // loader modal
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }

    int okCount = 0;
    int failCount = 0;
    final fails = <String>[];

    final ids = _seleccion.toList();

    try {
      for (final noticiaId in ids) {
        try {
          await ApiService.deleteNoticiaSinAsignar(noticiaId: noticiaId);
          okCount++;
        } catch (e) {
          failCount++;
          fails.add('#$noticiaId');
        }
      }
    } finally {
      if (mounted) Navigator.pop(context); // cierra loader
      if (mounted) setState(() => _borrando = false);
    }

    if (!mounted) return;

    if (okCount > 0) _huboCambios = true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failCount == 0
              ? 'Borradas: $okCount'
              : 'Borradas: $okCount • Fallaron: $failCount (${fails.take(5).join(", ")}${fails.length > 5 ? "…" : ""})',
        ),
      ),
    );

    _limpiarSeleccion();
    await _cargar();
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      // Trae todas (modo admin) y filtra las que NO tienen reportero asignado
      final all = await ApiService.getNoticiasAdmin();
      final sinAsignar = all.where((n) => n.reportero.trim().isEmpty).toList();

      setState(() {
        _items = sinAsignar;
        _cargando = false;
      });

      // si ya no existen ids seleccionados, limpiarlos
      _seleccion.removeWhere((id) => !_items.any((n) => n.id == id));
      if (_seleccion.isEmpty && _modoSeleccion) {
        setState(() => _modoSeleccion = false);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  void _toggleSeleccion(int id) {
    setState(() {
      if (_seleccion.contains(id)) {
        _seleccion.remove(id);
      } else {
        _seleccion.add(id);
      }
      if (_seleccion.isEmpty) _modoSeleccion = false;
    });
  }

  void _entrarSeleccion(int id) {
    setState(() {
      _modoSeleccion = true;
      _seleccion.add(id);
    });
  }

  void _limpiarSeleccion() {
    setState(() {
      _seleccion.clear();
      _modoSeleccion = false;
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
      _huboCambios = true;
      await _cargar();
    }
  }

  Future<ReporteroBusqueda?> _elegirReportero() async {
    final searchCtrl = TextEditingController(text: '');
    Future<List<ReporteroBusqueda>> future = ApiService.buscarReporteros('');

    return showModalBottomSheet<ReporteroBusqueda>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            void doSearch(String q) {
              setModalState(() {
                future = ApiService.buscarReporteros(q.trim());
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.70,
                child: Column(
                  children: [
                    const SizedBox(height: 6),
                    const Text(
                      'Elegir reportero',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: searchCtrl,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Buscar reportero…',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: searchCtrl.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    searchCtrl.clear();
                                    doSearch('');
                                  },
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onChanged: (_) => setModalState(() {}),
                        onSubmitted: doSearch,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: FutureBuilder<List<ReporteroBusqueda>>(
                        future: future,
                        builder: (ctx, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (snap.hasError) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text('Error: ${snap.error}'),
                              ),
                            );
                          }
                          final list = snap.data ?? [];
                          if (list.isEmpty) {
                            return const Center(child: Text('No se encontraron reporteros.'));
                          }

                          return ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final r = list[i];
                              return ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    r.nombre.isNotEmpty ? r.nombre[0].toUpperCase() : '?',
                                  ),
                                ),
                                title: Text(r.nombre),
                                onTap: () => Navigator.pop(ctx, r),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _asignarSeleccion() async {
    if (_asignando) return;

    if (_seleccion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos una noticia')),
      );
      return;
    }

    final reportero = await _elegirReportero();
    if (reportero == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Asignar noticias'),
        content: Text(
          '¿Asignar ${_seleccion.length} noticia(s) a "${reportero.nombre}"?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Asignar')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _asignando = true);

    // loader modal
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }

    int okCount = 0;
    int failCount = 0;
    final fails = <String>[];

    final ids = _seleccion.toList();

    try {
      for (final noticiaId in ids) {
        try {
          await ApiService.tomarNoticia(
            reporteroId: reportero.id,
            noticiaId: noticiaId,
          );
          okCount++;
        } catch (e) {
          failCount++;
          fails.add('#$noticiaId');
        }
      }
    } finally {
      if (mounted) Navigator.pop(context); // cierra loader
      if (mounted) setState(() => _asignando = false);
    }

    if (!mounted) return;

    if (okCount > 0) _huboCambios = true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failCount == 0
              ? 'Asignadas: $okCount'
              : 'Asignadas: $okCount • Fallaron: $failCount (${fails.take(5).join(", ")}${fails.length > 5 ? "…" : ""})',
        ),
      ),
    );

    _limpiarSeleccion();
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final canAsignar = _seleccion.isNotEmpty && !_asignando && !_borrando;
    final canBorrar  = _seleccion.isNotEmpty && !_borrando && !_asignando;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        Navigator.pop(context, _huboCambios);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_modoSeleccion
              ? 'Seleccionadas: ${_seleccion.length}'
              : 'Noticias sin asignar'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _huboCambios),
          ),
          actions: [
            IconButton(
              tooltip: 'Refrescar',
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
            ),
            if (_modoSeleccion)
              IconButton(
                tooltip: 'Limpiar selección',
                onPressed: _limpiarSeleccion,
                icon: const Icon(Icons.close),
              ),
            if (!_modoSeleccion && _items.isNotEmpty)
              IconButton(
                tooltip: 'Seleccionar',
                onPressed: () => setState(() => _modoSeleccion = true),
                icon: const Icon(Icons.checklist),
              ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: FloatingActionButton.extended(
                    heroTag: 'fab_borrar',
                    onPressed: canBorrar ? _borrarSeleccion : null,
                    backgroundColor: canBorrar ? Colors.red : Colors.grey.shade400,
                    foregroundColor: canBorrar ? Colors.white : Colors.grey.shade800,
                    icon: _borrando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete),
                    label: Text(_borrando ? 'Borrando…' : 'Borrar noticia'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FloatingActionButton.extended(
                    heroTag: 'fab_asignar',
                    onPressed: canAsignar ? _asignarSeleccion : null,
                    backgroundColor: canAsignar ? null : Colors.grey.shade400,
                    foregroundColor: canAsignar ? null : Colors.grey.shade800,
                    icon: _asignando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_add_alt_1),
                    label: Text(_asignando ? 'Asignando…' : 'Asignar'),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : _items.isEmpty
                    ? const Center(child: Text('No hay noticias sin asignar.'))
                    : RefreshIndicator(
                        onRefresh: _cargar,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final n = _items[i];
                            final selected = _seleccion.contains(n.id);

                            return InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () async {
                                if (_modoSeleccion) {
                                  _toggleSeleccion(n.id);
                                } else {
                                  await _abrirDetalle(n);
                                }
                              },
                              onLongPress: () {
                                if (!_modoSeleccion) _entrarSeleccion(n.id);
                                else _toggleSeleccion(n.id);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary.withOpacity(0.10)
                                      : Theme.of(context).colorScheme.surface,
                                  border: Border.all(
                                    color: selected
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.black.withOpacity(0.10),
                                  ),
                                ),
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    if (_modoSeleccion)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 10),
                                        child: Checkbox(
                                          value: selected,
                                          onChanged: (_) => _toggleSeleccion(n.id),
                                        ),
                                      )
                                    else
                                      const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            n.noticia,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Cita: ${_fmtFecha(n.fechaCita)}',
                                            style: TextStyle(color: Colors.grey.shade700),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            n.domicilio ?? 'Sin domicilio',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: Colors.grey.shade700),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    if (!_modoSeleccion)
                                      const Icon(Icons.chevron_right),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    );
  }
}
