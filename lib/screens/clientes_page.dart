// lib/screens/clientes_page.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/cliente.dart';
import '../services/api_service.dart';
import 'cliente_detalle_page.dart';

class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key});

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  final _searchCtrl = TextEditingController();

  bool _cargando = true;
  String? _error;
  List<Cliente> _items = [];

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
      final res = await ApiService.getClientes(q: q);
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

  Future<void> _mostrarDialogCrearCliente() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CrearClienteDialog(),
    );

    if (created == true) {
      await _cargar(q: _searchCtrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente creado')),
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

  Widget _avatarDefault({required int id, required String nombre}) {
    final letter = nombre.trim().isNotEmpty ? nombre.trim()[0].toUpperCase() : '?';
    final c = _colorFromId(id);

    return CircleAvatar(
      backgroundColor: c.withOpacity(0.18),
      child: Text(
        letter,
        style: TextStyle(fontWeight: FontWeight.w800, color: c),
      ),
    );
  }

  Future<void> _abrirDetalle(Cliente c) async {
    if (c.id <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente inválido (sin ID).')),
      );
      return;
    }

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ClienteDetallePage(cliente: c),
      ),
    );

    if (changed == true) {
      await _cargar(q: _searchCtrl.text.trim());
    }
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
                    hintText: 'Buscar cliente, usuario, correo, empresa…',
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
                  onPressed: _mostrarDialogCrearCliente,
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
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final c = _items[i];
                          final subtitleParts = <String>[
                            if ((c.username ?? '').trim().isNotEmpty) '@${c.username!.trim()}',
                            if ((c.empresa ?? '').trim().isNotEmpty) c.empresa!.trim(),
                            if ((c.email ?? '').trim().isNotEmpty) c.email!.trim(),
                            if ((c.telefono ?? '').trim().isNotEmpty) c.telefono!.trim(),
                          ];

                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _abrirDetalle(c),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                    color: Colors.black.withOpacity(0.08),
                                  ),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _avatarDefault(id: c.id, nombre: c.nombreCompleto),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                c.nombreCompleto,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: c.activo
                                                    ? Colors.green.withOpacity(0.12)
                                                    : Colors.red.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                c.activo ? 'Activo' : 'Inactivo',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: c.activo ? Colors.green : Colors.red,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (subtitleParts.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            subtitleParts.join(' • '),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                        if ((c.domicilioPrincipal ?? '').trim().isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            c.domicilioPrincipal!,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withOpacity(0.10),
                                                borderRadius: BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                '${c.domiciliosDisponibles.length} domicilio(s)',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: Theme.of(context).colorScheme.primary,
                                                ),
                                              ),
                                            ),
                                            if ((c.email ?? '').trim().isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .secondary
                                                      .withOpacity(0.10),
                                                  borderRadius: BorderRadius.circular(999),
                                                ),
                                                child: Text(
                                                  'Correo registrado',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: Theme.of(context).colorScheme.secondary,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: [
          if (!isWebDesktop)
            IconButton(
              tooltip: 'Añadir cliente',
              onPressed: _mostrarDialogCrearCliente,
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

class _CrearClienteDialog extends StatefulWidget {
  const _CrearClienteDialog();

  @override
  State<_CrearClienteDialog> createState() => _CrearClienteDialogState();
}

class _CrearClienteDialogState extends State<_CrearClienteDialog> {
  final _formKey = GlobalKey<FormState>();

  final _usernameCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _apellidosCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _empresaCtrl = TextEditingController();
  final _dom1Ctrl = TextEditingController();
  final _dom2Ctrl = TextEditingController();
  final _dom3Ctrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  bool _creando = false;
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _nombreCtrl.dispose();
    _apellidosCtrl.dispose();
    _telefonoCtrl.dispose();
    _correoCtrl.dispose();
    _empresaCtrl.dispose();
    _dom1Ctrl.dispose();
    _dom2Ctrl.dispose();
    _dom3Ctrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  String? _validarCorreo(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'El correo es obligatorio';
    final ok = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s);
    return ok ? null : 'Correo inválido';
  }

  Future<void> _crear() async {
    if (_creando) return;
    if (!_formKey.currentState!.validate()) return;

    final username = _usernameCtrl.text.trim();
    final nombre = _nombreCtrl.text.trim();
    final apellidos = _apellidosCtrl.text.trim();
    final telefono = _telefonoCtrl.text.trim();
    final email = _correoCtrl.text.trim();
    final empresa = _empresaCtrl.text.trim();
    final domicilio1 = _dom1Ctrl.text.trim();
    final domicilio2 = _dom2Ctrl.text.trim();
    final domicilio3 = _dom3Ctrl.text.trim();
    final pass = _passCtrl.text.trim();
    final pass2 = _pass2Ctrl.text.trim();

    if (pass != pass2) {
      setState(() => _error = 'Las contraseñas no coinciden');
      return;
    }

    setState(() {
      _creando = true;
      _error = null;
    });

    try {
      await ApiService.createCliente(
        username: username,
        nombre: nombre,
        apellidos: apellidos.isEmpty ? null : apellidos,
        telefono: telefono.isEmpty ? null : telefono,
        email: email,
        empresa: empresa.isEmpty ? null : empresa,
        domicilio1: domicilio1.isEmpty ? null : domicilio1,
        domicilio2: domicilio2.isEmpty ? null : domicilio2,
        domicilio3: domicilio3.isEmpty ? null : domicilio3,
        password: pass,
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
            maxWidth: isWideWeb ? 620 : 460,
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
                        'Crear cliente',
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
                        controller: _usernameCtrl,
                        enabled: !_creando,
                        decoration: const InputDecoration(
                          labelText: 'Username *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final s = (v ?? '').trim();
                          if (s.isEmpty) return 'El username es obligatorio';
                          if (s.length < 3) return 'Muy corto';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nombreCtrl,
                        enabled: !_creando,
                        decoration: const InputDecoration(
                          labelText: 'Nombre *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final s = (v ?? '').trim();
                          if (s.isEmpty) return 'El nombre es obligatorio';
                          if (s.length < 2) return 'Nombre demasiado corto';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _apellidosCtrl,
                        enabled: !_creando,
                        decoration: const InputDecoration(
                          labelText: 'Apellidos',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _telefonoCtrl,
                        enabled: !_creando,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _correoCtrl,
                        enabled: !_creando,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Correo *',
                          border: OutlineInputBorder(),
                        ),
                        validator: _validarCorreo,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _empresaCtrl,
                        enabled: !_creando,
                        decoration: const InputDecoration(
                          labelText: 'Empresa',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _dom1Ctrl,
                        enabled: !_creando,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Domicilio 1',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _dom2Ctrl,
                        enabled: !_creando,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Domicilio 2',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _dom3Ctrl,
                        enabled: !_creando,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Domicilio 3',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passCtrl,
                        enabled: !_creando,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Contraseña *',
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
                        controller: _pass2Ctrl,
                        enabled: !_creando,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirmar contraseña *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final s = v?.trim() ?? '';
                          if (s.isEmpty) return 'Confirma la contraseña';
                          return null;
                        },
                        onFieldSubmitted: (_) => _creando ? null : _crear(),
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