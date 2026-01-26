// lib/screens/gestion_reporteros_page.dart
import 'package:flutter/foundation.dart' show kIsWeb;
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

  static const double _kWebDesktopBreakpoint = 980;
  static const double _kWebMaxContentWidth = 1200;

  bool _isWebDesktop(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return kIsWeb && w >= _kWebDesktopBreakpoint;
  }

  Widget _wrapWebContent(Widget child) {
    if (!kIsWeb) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kWebMaxContentWidth),
        child: child,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _cargar();

    _searchCtrl.addListener(() {
      if (mounted) setState(() {});
    });
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

  SliverGridDelegate _gridDelegateForWidth(double width) {
    int crossAxisCount = (width / 180).floor().clamp(2, 4);
    double childAspectRatio = (crossAxisCount >= 3) ? 0.70 : 0.95;

    if (kIsWeb) {
      if (width < 700) {
        crossAxisCount = 3;
        childAspectRatio = 0.92;
      } else if (width < 980) {
        crossAxisCount = 4;
        childAspectRatio = 1.02;
      } else if (width < 1200) {
        crossAxisCount = 5;
        childAspectRatio = 1.10;
      } else {
        crossAxisCount = 6;
        childAspectRatio = 1.15;
      }
    }

    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: childAspectRatio,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWebDesktop = _isWebDesktop(context);

    final content = Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, isWebDesktop ? 16 : 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Buscar usuario…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpiar',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              _cargar(q: '');
                            },
                          ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onSubmitted: (v) => _cargar(q: v.trim()),
                ),
              ),
              if (isWebDesktop) ...[
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _mostrarDialogCrearUsuario,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Añadir'),
                ),
              ],
            ],
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
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            physics: const AlwaysScrollableScrollPhysics(),
                            gridDelegate: _gridDelegateForWidth(constraints.maxWidth),
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
                                      _avatarDefault(
                                        id: r.id,
                                        nombre: r.nombre,
                                        radius: isWebDesktop ? 36 : 32,
                                      ),
                                      const SizedBox(height: 10),
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
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: isWebDesktop ? 14.5 : 14,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              roleLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12.5,
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
                          );
                        },
                      ),
                    ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión'),
        actions: [
          if (!isWebDesktop)
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
      body: _wrapWebContent(content),
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
  bool _puedeCrearNoticias = false;

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
        puedeCrearNoticias: _puedeCrearNoticias,
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
    final w = MediaQuery.sizeOf(context).width;

    final isWideWeb = kIsWeb && w >= 980;

    return WillPopScope(
      onWillPop: () async => !_creando,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isWideWeb ? 520 : 420,
            maxHeight: h * 0.90,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + viewInsetsBottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        value: _puedeCrearNoticias,
                        onChanged: _creando ? null : (v) => setState(() => _puedeCrearNoticias = v),
                        title: const Text('Puede crear noticias'),
                        subtitle: const Text('Si está activo, podrá "Crear noticia" desde Agenda.'),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
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
