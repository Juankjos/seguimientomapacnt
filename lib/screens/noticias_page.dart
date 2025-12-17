//lib/screens/noticias_page.dart
import 'package:flutter/material.dart';

import '../models/noticia.dart';
import '../services/api_service.dart';
import '../theme_controller.dart';
import 'login_screen.dart';
import 'noticia_detalle_page.dart';
import 'tomar_noticias_page.dart';
import 'agenda_page.dart';

class NoticiasPage extends StatefulWidget {
  final int reporteroId;
  final String reporteroNombre;
  final String role;

  const NoticiasPage({
    super.key,
    required this.reporteroId,
    required this.reporteroNombre,
    required this.role,
  });

  @override
  State<NoticiasPage> createState() => _NoticiasPageState();
}

class _NoticiasPageState extends State<NoticiasPage> {
  late Future<List<Noticia>> _futureNoticias;

  @override
  void initState() {
    super.initState();
    _futureNoticias = ApiService.getNoticias(widget.reporteroId);
  }

  // ---------- DIALOGOS Y ACCIONES DEL MENÚ ----------

  void _mostrarPerfil() {
    Navigator.pop(context); // cierra el drawer
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Perfil'),
        content: Text('Reportero: ${widget.reporteroNombre}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _tomarNoticias() async {
    Navigator.pop(context); // cierra el drawer
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TomarNoticiasPage(
          reporteroId: widget.reporteroId,
          reporteroNombre: widget.reporteroNombre,
        ),
      ),
    );

    setState(() {
      _futureNoticias = ApiService.getNoticias(widget.reporteroId);
    });
  }

  void _mostrarAjustes() {
    Navigator.pop(context); // cierra el drawer

    final modoActual = ThemeController.themeMode.value;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Color de App'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('Tema Blanco'),
              value: ThemeMode.light,
              groupValue: modoActual,
              onChanged: (value) {
                if (value != null) {
                  ThemeController.themeMode.value = value;
                  Navigator.pop(context);
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Tema Oscuro'),
              value: ThemeMode.dark,
              groupValue: modoActual,
              onChanged: (value) {
                if (value != null) {
                  ThemeController.themeMode.value = value;
                  Navigator.pop(context);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _confirmarSalir() {
    Navigator.pop(context); // cierra el drawer

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          '¿Estás seguro que deseas Cerrar Sesión?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), // Cancelar
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // cierra el dialog
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (_) => const LoginScreen(),
                ),
                (route) => false,
              );
            },
            child: const Text('Cerrar Sesión'),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.themeMode,
      builder: (context, modoActual, _) {
        return Drawer(
          child: Column(
            children: [
              UserAccountsDrawerHeader(
                accountName: Text(widget.reporteroNombre),
                accountEmail: const Text('Reportero'),
                currentAccountPicture: CircleAvatar(
                  child: Text(
                    widget.reporteroNombre.isNotEmpty
                        ? widget.reporteroNombre[0].toUpperCase()
                        : '?',
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Perfil'),
                onTap: _mostrarPerfil,
              ),
              ListTile(
                leading: const Icon(Icons.assignment),
                title: const Text('Tomar Noticias'),
                onTap: _tomarNoticias,
              ),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Agenda'),
              onTap: () {
                  Navigator.pop(context); // cierra el drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AgendaPage(
                        reporteroId: widget.reporteroId,
                        reporteroNombre: widget.reporteroNombre,
                      ),
                    ),
                  );
                },
              ),

              ListTile(
                leading: Icon(
                  modoActual == ThemeMode.light
                      ? Icons.light_mode
                      : Icons.dark_mode,
                ),
                title: const Text('Color de App'),
                onTap: _mostrarAjustes,
              ),
              // ----------------------------------------------

              const Spacer(),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Salir',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: _confirmarSalir,
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }


  // ---------- UI PRINCIPAL ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tareas de ${widget.reporteroNombre}'),
      ),
      drawer: _buildDrawer(),
      body: FutureBuilder<List<Noticia>>(
        future: _futureNoticias,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }

          final noticias = snapshot.data ?? [];

          if (noticias.isEmpty) {
            return const Center(
              child: Text('No hay tareas asignadas.'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: noticias.length,
            itemBuilder: (context, index) {
              final n = noticias[index];

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6.0),
                child: ListTile(
                  title: Text(
                    n.noticia,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    // Abrimos el detalle y esperamos a que el usuario regrese
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NoticiaDetallePage(
                          noticia: n,
                          role: widget.role,
                          soloLectura: (n.pendiente == false),
                          ),
                      ),
                    );

                    // Al volver del detalle, recargamos las noticias desde el backend
                    setState(() {
                      _futureNoticias = ApiService.getNoticias(widget.reporteroId);
                    });
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
