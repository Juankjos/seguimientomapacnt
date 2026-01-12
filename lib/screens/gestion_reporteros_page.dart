// lib/screens/gestion_reporteros_page.dart
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

  Future<void> _cargar({String q = ''}) async {
    setState(() {
      _cargando = _items.isEmpty;
      _error = null;
    });

    try {
      final res = await ApiService.getReporterosAdmin(q: q);
      if (!mounted) return;
      setState(() {
        _items = res;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
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

  Widget _avatarDefault({
    required int id,
    required String nombre,
    double radius = 36,
  }) {
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

  Future<void> _mostrarDialogCrearReportero() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CrearUsuarioDialog(),
    );

    if (created == true) {
      await _cargar(q: _searchCtrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuario creado')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final showTopLoader = !_cargando && _items.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión'),
        actions: [
          IconButton(
            tooltip: 'Añadir usuario',
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
          if (showTopLoader) const LinearProgressIndicator(minHeight: 2),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar usuario…',
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
                            final roleLabel = (r.role == 'admin') ? 'Administrador' : 'Reportero';

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
                                    const SizedBox(height: 6),
                                    Text(
                                      roleLabel,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.65),
                                      ),
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

class _CrearUsuarioDialog extends StatefulWidget {
  const _CrearUsuarioDialog();

  @override
  State<_CrearUsuarioDialog> createState() => _CrearUsuarioDialogState();
}

class _CrearUsuarioDialogState extends State<_CrearUsuarioDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  bool _creando = false;
  String _role = 'reportero';
  String? _error;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    if (_creando) return;
    if (!_formKey.currentState!.validate()) return;

    final nombre = _nombreCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    final pass2 = _pass2Ctrl.text.trim();

    if (pass != pass2) {
      setState(() => _error = 'Las contraseñas no coinciden');
      return;
    }

    final normalizedRole = (_role == 'admin') ? 'admin' : 'reportero';

    setState(() {
      _creando = true;
      _error = null;
    });

    try {
      await ApiService.createReportero(
        nombre: nombre,
        password: pass,
        role: normalizedRole,
      );

      FocusManager.instance.primaryFocus?.unfocus();

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creando = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !_creando,
      child: AlertDialog(
        title: const Text('Añadir Usuario'),
        content: Form(
          key: _formKey,
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  enabled: !_creando,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'El nombre es requerido';
                    if (v.trim().length < 2) return 'Nombre demasiado corto';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  enabled: !_creando,
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return 'La contraseña es requerida';
                    if (s.length < 6) return 'Mínimo 6 caracteres';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pass2Ctrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar contraseña',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.done,
                  enabled: !_creando,
                  onFieldSubmitted: (_) => _creando ? null : _crear(),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return 'Confirma la contraseña';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Rol',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.85),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Reportero'),
                      selected: _role == 'reportero',
                      onSelected: _creando ? null : (_) => setState(() => _role = 'reportero'),
                    ),
                    ChoiceChip(
                      label: const Text('Administrador'),
                      selected: _role == 'admin',
                      onSelected: _creando ? null : (_) => setState(() => _role = 'admin'),
                    ),
                  ],
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _creando ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: _creando ? null : _crear,
            icon: _creando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add),
            label: Text(_creando ? 'Creando…' : 'Crear'),
          ),
        ],
      ),
    );
  }
}
