import 'package:flutter/material.dart';

import '../models/reportero_admin.dart';
import '../services/api_service.dart';
import 'editar_reportero_page.dart';

class GestionReporterosPage extends StatefulWidget {
  const GestionReporterosPage({super.key});

  @override
  State<GestionReporterosPage> createState() => _GestionReporterosPageState();
}

class _GestionReporterosPageState extends State<GestionReporterosPage> {
  final _searchCtrl = TextEditingController();
  bool _cargando = true;
  String? _error;

  List<ReporteroAdmin> _items = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _colorFromId(int id) {
    final colors = <Color>[
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.indigo,
      Colors.red,
      Colors.brown,
    ];
    return colors[id % colors.length];
  }

  Widget _avatarDefault({required int id, required String nombre, double radius = 36}) {
    final letter = nombre.trim().isNotEmpty ? nombre.trim()[0].toUpperCase() : '?';
    final c = _colorFromId(id);

    return CircleAvatar(
      radius: radius,
      backgroundColor: c.withOpacity(0.18),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: radius * 0.65,
          fontWeight: FontWeight.w800,
          color: c,
        ),
      ),
    );
  }

  Future<void> _cargar({String q = ''}) async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final res = await ApiService.getReporterosAdmin(q: q);
      setState(() {
        _items = res;
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  Future<void> _abrirEditor(ReporteroAdmin r) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EditarReporteroPage(reportero: r)),
    );

    if (changed == true) {
      await _cargar(q: _searchCtrl.text.trim());
    }
  }

  Future<void> _mostrarDialogCrearReportero() async {
    final nombreCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final pass2Ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        bool creando = false;

        Future<void> crear(StateSetter setLocal) async {
          if (creando) return;
          if (!formKey.currentState!.validate()) return;

          final nombre = nombreCtrl.text.trim();
          final pass = passCtrl.text.trim();
          final pass2 = pass2Ctrl.text.trim();

          if (pass != pass2) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Las contraseñas no coinciden')),
            );
            return;
          }

          setLocal(() => creando = true);

          try {
            await ApiService.createReportero(nombre: nombre, password: pass);

            if (!ctx.mounted) return;
            // Cerrar el diálogo y regresar "true"
            Navigator.pop(ctx, true);
            return; // <-- importante: NO seguir ejecutando setLocal después del pop
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error: $e')),
              );
              setLocal(() => creando = false);
            }
          }
        }

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Añadir reportero'),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: 380,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nombreCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'El nombre es requerido';
                          if (v.trim().length < 2) return 'Nombre demasiado corto';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Contraseña',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final s = v?.trim() ?? '';
                          if (s.isEmpty) return 'La contraseña es requerida';
                          if (s.length < 6) return 'Mínimo 6 caracteres';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: pass2Ctrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirmar contraseña',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final s = v?.trim() ?? '';
                          if (s.isEmpty) return 'Confirma la contraseña';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: creando ? null : () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: creando ? null : () => crear(setLocal),
                  icon: creando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add),
                  label: Text(creando ? 'Creando…' : 'Crear'),
                ),
              ],
            );
          },
        );
      },
    );

    nombreCtrl.dispose();
    passCtrl.dispose();
    pass2Ctrl.dispose();

    // Si se creó, refrescar lista
    if (created == true) {
      await _cargar(q: _searchCtrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reportero creado')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión'),
        actions: [
          IconButton(
            tooltip: 'Añadir reportero',
            onPressed: _mostrarDialogCrearReportero,
            icon: const Icon(Icons.person_add_alt_1),
          ),
          IconButton(
            tooltip: 'Refrescar',
            onPressed: () => _cargar(q: _searchCtrl.text.trim()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar reportero…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _cargar(q: '');
                          setState(() {});
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) => _cargar(q: v.trim()),
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _cargar(q: _searchCtrl.text.trim()),
                        child: GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.78,
                          ),
                          itemCount: _items.length,
                          itemBuilder: (context, i) {
                            final r = _items[i];

                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _abrirEditor(r),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: Theme.of(context).colorScheme.surface,
                                  boxShadow: [
                                    BoxShadow(
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                      color: Colors.black.withOpacity(0.08),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _avatarDefault(id: r.id, nombre: r.nombre, radius: 36),
                                    const SizedBox(height: 10),
                                    Text(
                                      r.nombre,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
