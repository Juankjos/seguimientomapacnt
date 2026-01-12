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

  Future<void> _mostrarDialogCrearUsuario() async {
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
    double radius = 32,
  }) {
    final letter = nombre.trim().isNotEmpty ? nombre.trim()[0].toUpperCase() : '?';
    final c = _colorFromId(id);

    return CircleAvatar(
      radius: radius,
      backgroundColor: c.withOpacity(0.18),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: radius * 0.70,
          fontWeight: FontWeight.w800,
          color: c,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    // ✅ Esto evita el overflow en la grilla:
    // - en pantallas pequeñas baja a 2 columnas
    // - da más altura a cada tile cuando hay 3+ columnas
    final crossAxisCount = (width / 180).floor().clamp(2, 4);
    final childAspectRatio = (crossAxisCount >= 3) ? 0.70 : 0.95;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión'),
        actions: [
          IconButton(
            tooltip: 'Añadir usuario',
            onPressed: _mostrarDialogCrearUsuario,
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
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: childAspectRatio,
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
                                  children: [
                                    const SizedBox(height: 8),
                                    _avatarDefault(id: r.id, nombre: r.nombre, radius: 32),
                                    const SizedBox(height: 8),

                                    // ✅ Flexible evita RenderFlex overflow dentro del tile
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              r.nombre,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            roleLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withOpacity(0.65),
                                            ),
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
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;
    final h = MediaQuery.sizeOf(context).height;

    return WillPopScope(
      onWillPop: () async => !_creando,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: h * 0.90,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + viewInsetsBottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Título
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Añadir Usuario',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: _creando ? null : () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nombreCtrl,
                        enabled: !_creando,
                        decoration: const InputDecoration(
                          labelText: 'Nombre',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'El nombre es requerido';
                          if (v.trim().length < 2) return 'Nombre demasiado corto';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _passCtrl,
                        enabled: !_creando,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Contraseña',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
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
                        enabled: !_creando,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirmar contraseña',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _creando ? null : _crear(),
                        validator: (v) {
                          final s = v?.trim() ?? '';
                          if (s.isEmpty) return 'Confirma la contraseña';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      DropdownButtonFormField<String>(
                        value: _role,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Rol',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'reportero', child: Text('Reportero')),
                          DropdownMenuItem(value: 'admin', child: Text('Administrador')),
                        ],
                        onChanged: _creando ? null : (v) => setState(() => _role = v ?? 'reportero'),
                      ),
                    ],
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _creando ? null : () => Navigator.of(context).pop(false),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
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
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
