// lib/screens/editar_reportero_page.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth_controller.dart';
import '../models/reportero_admin.dart';
import '../services/api_service.dart';

const double _kWebMaxContentWidth = 1100;
const double _kWebWideBreakpoint = 980;

bool _isWebWide(BuildContext context) =>
    kIsWeb && MediaQuery.of(context).size.width >= _kWebWideBreakpoint;

double _hPad(BuildContext context) => _isWebWide(context) ? 20 : 16;

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
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: theme.dividerColor.withOpacity(0.70),
        width: 0.9,
      ),
    );

class EditarReporteroPage extends StatefulWidget {
  final ReporteroAdmin reportero;

  const EditarReporteroPage({super.key, required this.reportero});

  @override
  State<EditarReporteroPage> createState() => _EditarReporteroPageState();
}

class _EditarReporteroPageState extends State<EditarReporteroPage> {
  late final TextEditingController _nombreCtrl;
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late String _role;
  late bool _puedeCrearNoticias;

  bool _guardando = false;
  bool _borrando = false;

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.reportero.nombre);

    _role = (widget.reportero.role).trim();
    if (_role != 'admin' && _role != 'reportero') _role = 'reportero';

    _puedeCrearNoticias = widget.reportero.puedeCrearNoticias;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
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

  Widget _avatarDefault({
    required int id,
    required String nombre,
    double radius = 52,
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

  Future<void> _guardar() async {
    if (_guardando) return;
    if (!_formKey.currentState!.validate()) return;

    final nombre = _nombreCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    final pass2 = _pass2Ctrl.text.trim();

    String? passwordToSend;
    if (pass.isNotEmpty || pass2.isNotEmpty) {
      if (pass.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La contraseña debe tener al menos 6 caracteres')),
        );
        return;
      }
      if (pass != pass2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Las contraseñas no coinciden')),
        );
        return;
      }
      passwordToSend = pass;
    }

    setState(() => _guardando = true);

    try {
      await ApiService.updateReporteroAdmin(
        reporteroId: widget.reportero.id,
        nombre: nombre,
        password: passwordToSend,
        role: _role,
        puedeCrearNoticias: _puedeCrearNoticias,
      );

      final prefs = await SharedPreferences.getInstance();
      final myId = prefs.getInt('auth_reportero_id') ?? 0;

      if (myId == widget.reportero.id) {
        await prefs.setBool('auth_puede_crear_noticias', _puedeCrearNoticias);
        AuthController.puedeCrearNoticias.value = _puedeCrearNoticias;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cambios guardados')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _borrar() async {
    if (_borrando) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar usuario'),
        content: const Text(
          '¿Seguro que deseas borrar este reportero? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _borrando = true);

    try {
      await ApiService.deleteReportero(reporteroId: widget.reportero.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reportero borrado')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al borrar: $e')),
      );
    } finally {
      if (mounted) setState(() => _borrando = false);
    }
  }

  Widget _card(ThemeData theme, Widget child) {
    return Card(
      elevation: kIsWeb ? 0.6 : 2,
      shape: _softShape(theme),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = _isWebWide(context);

    final leftCard = _card(
      theme,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: _avatarDefault(
              id: widget.reportero.id,
              nombre: _nombreCtrl.text,
              radius: 52,
            ),
          ),
          const SizedBox(height: 18),

          TextFormField(
            controller: _nombreCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'El nombre es requerido';
              return null;
            },
          ),
          const SizedBox(height: 14),

          DropdownButtonFormField<String>(
            value: _role,
            decoration: const InputDecoration(
              labelText: 'Rol',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'reportero', child: Text('Reportero')),
              DropdownMenuItem(value: 'admin', child: Text('Administrador')),
            ],
            onChanged: _guardando ? null : (v) => setState(() => _role = (v ?? 'reportero')),
          ),
        ],
      ),
    );

    final rightCard = _card(
      theme,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.dividerColor),
            ),
            child: SwitchListTile.adaptive(
              value: _puedeCrearNoticias,
              onChanged: _guardando ? null : (v) => setState(() => _puedeCrearNoticias = v),
              title: const Text('Puede crear noticias'),
              subtitle: const Text('Si está activo, podrá "Crear noticia" desde Agenda.'),
            ),
          ),

          const SizedBox(height: 14),

          TextFormField(
            controller: _passCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Nueva contraseña',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),

          TextFormField(
            controller: _pass2Ctrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirmar nueva contraseña',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_guardando ? 'Guardando…' : 'Guardar cambios'),
            ),
          ),

          const SizedBox(height: 14),
          const Divider(height: 24),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _borrando ? null : _borrar,
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              icon: _borrando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete),
              label: Text(_borrando ? 'Borrando…' : 'Borrar reportero'),
            ),
          ),
        ],
      ),
    );

    final content = Form(
      key: _formKey,
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: leftCard),
                const SizedBox(width: 12),
                Expanded(flex: 7, child: rightCard),
              ],
            )
          : Column(
              children: [
                leftCard,
                const SizedBox(height: 12),
                rightCard,
              ],
            ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Editar: ${widget.reportero.nombre}'),
        actions: [
          IconButton(
            tooltip: 'Guardar',
            onPressed: _guardando ? null : _guardar,
            icon: const Icon(Icons.save),
          )
        ],
      ),
      body: _wrapWebWidth(
        _maybeScrollbar(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(_hPad(context)),
            child: content,
          ),
        ),
      ),
    );
  }
}
