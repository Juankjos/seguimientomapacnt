// lib/screens/update_perfil_page.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';

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

    // Opcional: si no cambió nada, evitar request
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

      // Regresamos el nuevo nombre para actualizar UI en NoticiasPage
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Actualizar perfil'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

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

                const SizedBox(height: 20),
                SizedBox(
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
