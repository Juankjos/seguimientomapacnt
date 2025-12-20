import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'noticias_page.dart';
import 'agenda_page.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _loading = false;
  String? _errorMessage;

  Future<void> _doLogin() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final data = await ApiService.login(
        _nombreController.text.trim(),
        _passwordController.text.trim(),
      );

      if (data['success'] == true) {
        final int reporteroId = int.parse(data['reportero_id'].toString());
        final String nombre = data['nombre'] ?? '';
        final String role = data['role']?.toString() ?? 'reportero';
        final String wsToken = data['ws_token']?.toString() ?? '';
        ApiService.wsToken = wsToken;

      if (!mounted) return;

      if (role == 'admin') {
        // Admin: la página principal es agenda con vista global
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AgendaPage(
              reporteroId: reporteroId,
              reporteroNombre: nombre,
              esAdmin: true, // 👈 nuevo parámetro
            ),
          ),
        );
      } else {
        // Reportero normal: flujo que ya tenías (noticias_page / home)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => NoticiasPage( // o HomeScreen si es como lo tienes
              reporteroId: reporteroId,
              reporteroNombre: nombre,
              role: role,
              wsToken: wsToken,
            ),
          ),
        );
      }
    } else {
      setState(() {
        _errorMessage = data['message']?.toString() ?? 'Error de login';
      });
    }

    } catch (e) {
      setState(() {
        _errorMessage = 'Error al conectar con el servidor: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login Seguimiento CNT'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nombreController,
              decoration: const InputDecoration(
                labelText: 'Usuario (reportero)',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Contraseña',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _doLogin,
                child: _loading
                    ? const CircularProgressIndicator()
                    : const Text('Entrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
