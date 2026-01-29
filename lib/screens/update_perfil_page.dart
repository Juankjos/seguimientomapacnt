// lib/screens/update_perfil_page.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/api_service.dart';

const double _kWebMaxContentWidth = 980;
const double _kWebWideBreakpoint = 920;

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

class UpdatePerfilPage extends StatefulWidget {
  final int reporteroId;
  final String nombreActual;

  const UpdatePerfilPage({
    super.key,
    required this.reporteroId,
    required this.nombreActual,
  });

  @override
  State<UpdatePerfilPage> createState() => _UpdatePerfilPageState();
}

class _UpdatePerfilPageState extends State<UpdatePerfilPage> {
  late final TextEditingController _nombreCtrl;
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _pass2Ctrl = TextEditingController();

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.nombreActual);
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    final pass2 = _pass2Ctrl.text.trim();

    // Validación: si escribió password, confirmar y longitud
    if (pass.isNotEmpty) {
      if (pass.length < 6) {
        _snack('La contraseña debe tener al menos 6 caracteres');
        return;
      }
      if (pass != pass2) {
        _snack('Las contraseñas no coinciden');
        return;
      }
    }

    final cambioNombre = nombre.isNotEmpty && nombre != widget.nombreActual;
    final cambioPass = pass.isNotEmpty;

    if (!cambioNombre && !cambioPass) {
      _snack('No hay cambios para guardar');
      return;
    }

    setState(() => _loading = true);

    try {
      final resp = await ApiService.updatePerfil(
        reporteroId: widget.reporteroId,
        nombre: cambioNombre ? nombre : null,
        password: cambioPass ? pass : null,
      );

      final updatedName = resp['data']?['nombre']?.toString() ?? nombre;

      if (!mounted) return;
      _snack('Perfil actualizado');

      Navigator.pop(context, updatedName);
    } catch (e) {
      if (!mounted) return;
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
          Row(
            children: [
              const Icon(Icons.person),
              const SizedBox(width: 8),
              Text(
                'Datos del perfil',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nombreCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Actual: ${widget.nombreActual}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    final rightCard = _card(
      theme,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock),
              const SizedBox(width: 8),
              Text(
                'Seguridad',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Nueva contraseña (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass2Ctrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirmar nueva contraseña',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Mínimo 6 caracteres.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    final actions = SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _loading ? null : _guardar,
        icon: _loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save),
        label: Text(_loading ? 'Guardando...' : 'Guardar cambios'),
      ),
    );

    final content = wide
        ? Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: leftCard),
                  const SizedBox(width: 12),
                  Expanded(flex: 6, child: rightCard),
                ],
              ),
              const SizedBox(height: 12),
              actions,
            ],
          )
        : Column(
            children: [
              leftCard,
              const SizedBox(height: 12),
              rightCard,
              const SizedBox(height: 12),
              actions,
            ],
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Actualizar perfil'),
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
