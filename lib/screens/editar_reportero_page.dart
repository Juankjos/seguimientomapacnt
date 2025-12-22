import 'package:flutter/material.dart';

import '../models/reportero_admin.dart';
import '../services/api_service.dart';

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

  bool _guardando = false;
  bool _borrando = false;

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.reportero.nombre);
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
      Colors.blue, Colors.green, Colors.orange, Colors.purple,
      Colors.teal, Colors.indigo, Colors.red, Colors.brown,
    ];
    return colors[id % colors.length];
  }

  Widget _avatarDefault({required int id, required String nombre, double radius = 52}) {
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
      );

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
        title: const Text('Borrar reportero'),
        content: const Text('¿Seguro que deseas borrar este reportero? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
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

  @override
  Widget build(BuildContext context) {
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
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
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
              onChanged: (_) => setState(() {}), // para actualizar inicial en avatar
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'El nombre es requerido';
                return null;
              },
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
      ),
    );
  }
}
