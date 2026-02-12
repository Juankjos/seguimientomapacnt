// lib/screens/noticias_page.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/noticia.dart';
import '../services/api_service.dart';
import '../theme_controller.dart';
import 'agenda_page.dart';
import 'login_screen.dart';
import 'noticia_detalle_page.dart';
import 'tomar_noticias_page.dart';
import 'update_perfil_page.dart';
import 'empleado_destacado.dart';
import 'avisos_page.dart';

const double _kWebMaxContentWidth = 1200;
const double _kWebWideBreakpoint = 980;

bool _isWebWide(BuildContext context) =>
    kIsWeb && MediaQuery.of(context).size.width >= _kWebWideBreakpoint;

double _hPad(BuildContext context) => _isWebWide(context) ? 20 : 12;

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
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: theme.dividerColor.withOpacity(0.70),
        width: 0.9,
      ),
    );

class NoticiasPage extends StatefulWidget {
  final int reporteroId;
  final String reporteroNombre;
  final String role;
  final String wsToken;

  const NoticiasPage({
    super.key,
    required this.reporteroId,
    required this.reporteroNombre,
    required this.role,
    required this.wsToken,
  });

  @override
  State<NoticiasPage> createState() => _NoticiasPageState();
}

class _NoticiasPageState extends State<NoticiasPage> {
  late Future<List<Noticia>> _futureNoticias;
  late String _nombreReportero;

  @override
  void initState() {
    super.initState();
    _nombreReportero = widget.reporteroNombre;
    _futureNoticias = ApiService.getNoticias(widget.reporteroId);
  }

  Future<void> _refrescar() async {
    setState(() {
      _futureNoticias = ApiService.getNoticias(widget.reporteroId);
    });

    try {
      await _futureNoticias;
    } catch (_) {}
  }

  // ---------- ACCIONES (reusables: drawer / panel web) ----------

  Future<void> _mostrarPerfil({bool closeDrawer = false}) async {
    if (closeDrawer) Navigator.pop(context);

    final nuevoNombre = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => UpdatePerfilPage(
          reporteroId: widget.reporteroId,
          nombreActual: _nombreReportero,
        ),
      ),
    );

    if (nuevoNombre != null && nuevoNombre.trim().isNotEmpty && mounted) {
      setState(() => _nombreReportero = nuevoNombre.trim());
    }
  }

  Future<void> _tomarNoticias({bool closeDrawer = false}) async {
    if (closeDrawer) Navigator.pop(context);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TomarNoticiasPage(
          reporteroId: widget.reporteroId,
          reporteroNombre: widget.reporteroNombre,
        ),
      ),
    );

    await _refrescar();
  }

  Future<void> _irAgenda({bool closeDrawer = false}) async {
    if (closeDrawer) Navigator.pop(context);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AgendaPage(
          reporteroId: widget.reporteroId,
          reporteroNombre: widget.reporteroNombre,
        ),
      ),
    );
  }

  Future<void> _irAvisos({bool closeDrawer = false}) async {
    if (closeDrawer) Navigator.pop(context);

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AvisosPage()),
    );
  }

  void _mostrarAjustes({bool closeDrawer = false}) {
    if (closeDrawer) Navigator.pop(context);

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

  Future<void> _irEmpleadoDestacado({bool closeDrawer = false}) async {
    if (closeDrawer) Navigator.pop(context);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmpleadoDestacadoPage(
          role: widget.role,
          myReporteroId: widget.reporteroId,
        ),
      ),
    );
  }

  void _confirmarSalir({bool closeDrawer = false}) {
    if (closeDrawer) Navigator.pop(context);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro que deseas Cerrar Sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
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
                accountName: Text(_nombreReportero),
                accountEmail: const Text('Reportero'),
                currentAccountPicture: CircleAvatar(
                  child: Text(
                    _nombreReportero.isNotEmpty ? _nombreReportero[0].toUpperCase() : '?',
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Perfil'),
                onTap: () => _mostrarPerfil(closeDrawer: true),
              ),
              ListTile(
                leading: const Icon(Icons.notifications),
                title: const Text('Avisos'),
                onTap: () => _irAvisos(closeDrawer: true),
              ),
              ListTile(
                leading: const Icon(Icons.assignment),
                title: const Text('Tomar Noticias'),
                onTap: () => _tomarNoticias(closeDrawer: true),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Agenda'),
                onTap: () => _irAgenda(closeDrawer: true),
              ),
              ListTile(
                leading: const Icon(Icons.star_rounded),
                title: const Text('Empleado del Mes'),
                onTap: () => _irEmpleadoDestacado(closeDrawer: true),
              ),
              ListTile(
                leading: Icon(modoActual == ThemeMode.light ? Icons.light_mode : Icons.dark_mode),
                title: const Text('Color de App'),
                onTap: () => _mostrarAjustes(closeDrawer: true),
              ),
              const Spacer(),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Salir', style: TextStyle(color: Colors.red)),
                onTap: () => _confirmarSalir(closeDrawer: true),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // ---------- LISTA (reusable) ----------

  Widget _buildLista() {
    return RefreshIndicator(
      onRefresh: _refrescar,
      child: FutureBuilder<List<Noticia>>(
        future: _futureNoticias,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 220),
                Center(child: CircularProgressIndicator()),
              ],
            );
          }

          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text('Error: ${snapshot.error}'),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _refrescar,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            );
          }

          final noticias = snapshot.data ?? [];

          if (noticias.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 220),
                Center(child: Text('No hay tareas asignadas.')),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(_hPad(context)),
            itemCount: noticias.length,
            itemBuilder: (context, index) {
              final n = noticias[index];

              return Card(
                elevation: kIsWeb ? 0.6 : 2,
                shape: _softShape(Theme.of(context)),
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  title: Text(
                    n.noticia,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
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
                    await _refrescar();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ---------- PANEL LATERAL (solo web wide) ----------

  Widget _buildWebSidePanel() {
    final theme = Theme.of(context);

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.themeMode,
      builder: (context, modoActual, _) {
        return Card(
          elevation: 0.6,
          shape: _softShape(theme),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      child: Text(_nombreReportero.isNotEmpty ? _nombreReportero[0].toUpperCase() : '?'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _nombreReportero,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.person),
                    label: const Text('Perfil'),
                    onPressed: () => _mostrarPerfil(),
                  ),
                ),
                const SizedBox(height: 8),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.notifications),
                    label: const Text('Avisos'),
                    onPressed: () => _irAvisos(),
                  ),
                ),

                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.assignment),
                    label: const Text('Tomar Noticias'),
                    onPressed: () => _tomarNoticias(),
                  ),
                ),
                const SizedBox(height: 8),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('Agenda'),
                    onPressed: () => _irAgenda(),
                  ),
                ),
                const SizedBox(height: 8),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.star_rounded),
                    label: const Text('Empleado del Mes'),
                    onPressed: () => _irEmpleadoDestacado(),
                  ),
                ),
                const SizedBox(height: 8),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: Icon(modoActual == ThemeMode.light ? Icons.light_mode : Icons.dark_mode),
                    label: const Text('Color de App'),
                    onPressed: () => _mostrarAjustes(),
                  ),
                ),

                const Divider(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar'),
                    onPressed: _refrescar,
                  ),
                ),

                const Spacer(),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    icon: const Icon(Icons.logout),
                    label: const Text('Salir'),
                    onPressed: _confirmarSalir,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- BUILD ----------

  @override
  Widget build(BuildContext context) {
    final wide = _isWebWide(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Tareas de ${_nombreReportero}'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _refrescar,
          ),
        ],
      ),

      // Drawer solo en mobile / web angosto
      drawer: wide ? null : _buildDrawer(),

      body: wide
          ? _wrapWebWidth(
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 8,
                    child: _maybeScrollbar(child: _buildLista()),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(12, 12, _hPad(context), 12),
                    child: SizedBox(width: 360, child: _buildWebSidePanel()),
                  ),
                ],
              ),
            )
          : _buildLista(),
    );
  }
}
