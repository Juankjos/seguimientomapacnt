// lib/screens/agenda_page.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth_controller.dart';
import '../models/noticia.dart';
import '../services/api_service.dart';
import 'noticia_detalle_page.dart';
import 'crear_noticia_page.dart';
import 'login_screen.dart';
import 'update_perfil_page.dart';
import 'gestion_reporteros_page.dart';
import 'gestion_noticias_page.dart';
import 'estadisticas_screen.dart';

enum AgendaView { year, month, day }

class MesEfemeride {
  final IconData icon;
  final Color color;
  final String tooltip;

  MesEfemeride({
    required this.icon,
    required this.color,
    required this.tooltip,
  });
}

MesEfemeride efemerideMes(int month, ThemeData theme) {
  switch (month) {
    case 1:
      return MesEfemeride(
        icon: Icons.celebration,
        color: const Color(0xFFF94144),
        tooltip: 'Año Nuevo',
      );
    case 2:
      return MesEfemeride(
        icon: Icons.favorite,
        color: const Color(0xFFF3722C),
        tooltip: 'Día del Amor y la Amistad',
      );
    case 3:
      return MesEfemeride(
        icon: Icons.emoji_nature,
        color: const Color(0xFFF8961E),
        tooltip: 'Primavera',
      );
    case 4:
      return MesEfemeride(
        icon: Icons.face_outlined,
        color: const Color(0xFFF9844A),
        tooltip: 'Día del Niño',
      );
    case 5:
      return MesEfemeride(
        icon: Icons.face_2_rounded,
        color: const Color(0xFFF9C74F),
        tooltip: 'Día de las Madres',
      );
    case 6:
      return MesEfemeride(
        icon: Icons.wb_sunny,
        color: const Color(0xFF90BE6D),
        tooltip: 'Verano',
      );
    case 7:
      return MesEfemeride(
        icon: Icons.beach_access,
        color: const Color(0xFF43AA8B),
        tooltip: 'Vacaciones de verano',
      );
    case 8:
      return MesEfemeride(
        icon: Icons.school,
        color: const Color(0xFF4D908E),
        tooltip: 'Regreso a clases',
      );
    case 9:
      return MesEfemeride(
        icon: Icons.flag,
        color: const Color(0xFF577590),
        tooltip: 'Independencia de México',
      );
    case 10:
      return MesEfemeride(
        icon: Icons.nights_stay,
        color: const Color(0xFF277DA1),
        tooltip: 'Día de Muertos',
      );
    case 11:
      return MesEfemeride(
        icon: Icons.local_florist,
        color: const Color(0xFF4D908E),
        tooltip: 'Día de Muertos',
      );
    case 12:
      return MesEfemeride(
        icon: Icons.ice_skating_outlined,
        color: const Color(0xFFF94144),
        tooltip: 'Navidad',
      );
    default:
      return MesEfemeride(
        icon: Icons.event,
        color: theme.colorScheme.primary,
        tooltip: 'Mes',
      );
  }
}

class AgendaPage extends StatefulWidget {
  final int reporteroId;
  final String reporteroNombre;
  final bool esAdmin;
  final bool? puedeCrearNoticias;

  const AgendaPage({
    super.key,
    required this.reporteroId,
    required this.reporteroNombre,
    this.esAdmin = false,
    this.puedeCrearNoticias,
  });

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  bool _loading = false;
  String? _error;

  final Map<DateTime, List<Noticia>> _eventosPorDia = {};

  AgendaView _vista = AgendaView.month;

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  late int _selectedMonthInYear;
  late String _nombreActual;

  // ---- Ajustes SOLO de dimensiones para Chrome/Web ----
  static const double _kWebMaxContentWidth = 1200;
  static const double _kWebWideBreakpoint = 980;

  bool _isWebWide(BuildContext context) =>
      kIsWeb && MediaQuery.of(context).size.width >= _kWebWideBreakpoint;

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

  double _hPad(BuildContext context) => _isWebWide(context) ? 20 : 12;
  double _selectorHPad(BuildContext context) => _isWebWide(context) ? 20 : 16;

  // ---- helpers visuales (sin cambiar lógica) ----
  ShapeBorder _softShape(ThemeData theme) => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.dividerColor.withOpacity(0.65),
          width: 0.9,
        ),
      );

  Widget _cardShell({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(10),
    double? elevation,
    Color? color,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: elevation ?? (kIsWeb ? 0.5 : 1),
      color: color ?? theme.colorScheme.surface,
      shape: _softShape(theme),
      child: Padding(padding: padding, child: child),
    );
  }

  Widget _maybeScrollbar({required Widget child}) {
    if (!kIsWeb) return child;
    return Scrollbar(
      thumbVisibility: true,
      interactive: true,
      child: child,
    );
  }

  Color _gridLineColor(ThemeData theme) {
    final base = theme.colorScheme.onSurface;
    final opacity = theme.brightness == Brightness.dark ? 0.10 : 0.08;
    return base.withOpacity(opacity);
  }

  Widget _calDayCell({
    required ThemeData theme,
    required DateTime day,
    required bool wide,
    bool isSelected = false,
    bool isToday = false,
    bool isOutside = false,
  }) {
    final bool isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

    final Color border = isSelected
        ? theme.colorScheme.secondary.withOpacity(0.25)
        : _gridLineColor(theme);

    final Color bg = isSelected
        ? theme.colorScheme.secondary.withOpacity(theme.brightness == Brightness.dark ? 0.35 : 0.22)
        : isToday
            ? theme.colorScheme.primary.withOpacity(theme.brightness == Brightness.dark ? 0.22 : 0.12)
            : Colors.transparent;

    Color textColor;
    if (isSelected) {
      textColor = theme.colorScheme.onSecondary;
    } else if (isToday) {
      textColor = theme.colorScheme.primary;
    } else if (isOutside) {
      textColor = theme.colorScheme.onSurface.withOpacity(0.35);
    } else if (isWeekend) {
      textColor = theme.colorScheme.error.withOpacity(0.95);
    } else {
      textColor = theme.colorScheme.onSurface;
    }

    final double fontSize = wide ? 13 : 12;

    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border, width: 0.55),
      ),
      child: Text(
        '${day.day}',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: (isSelected || isToday) ? FontWeight.w800 : FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  // ---- Panel lateral (Vista Día, escritorio) ----
  Widget _pill({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.dividerColor.withOpacity(0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w800, color: fg, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _daySidePanel({
    required ThemeData theme,
    required DateTime dia,
    required List<Noticia> eventos,
  }) {
    final total = eventos.length;
    final pendientes = eventos.where((e) => e.pendiente == true).length;
    final cerradas = total - pendientes;

    final preview = eventos.take(6).toList();

    return _cardShell(
      padding: const EdgeInsets.all(12),
      elevation: 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Resumen del día',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_nombreMes(dia.month)} ${dia.day}, ${dia.year}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface.withOpacity(0.75),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill(
                theme: theme,
                icon: Icons.list_alt,
                label: '$total Total',
                bg: theme.colorScheme.primaryContainer,
                fg: theme.colorScheme.onPrimaryContainer,
              ),
              _pill(
                theme: theme,
                icon: Icons.schedule,
                label: '$pendientes Pendientes',
                bg: theme.colorScheme.surfaceVariant.withOpacity(0.55),
                fg: theme.colorScheme.onSurface.withOpacity(0.88),
              ),
              _pill(
                theme: theme,
                icon: Icons.check_circle,
                label: '$cerradas Cerradas',
                bg: theme.colorScheme.secondaryContainer,
                fg: theme.colorScheme.onSecondaryContainer,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: theme.dividerColor.withOpacity(0.5)),
          const SizedBox(height: 10),
          Text(
            'Vista rápida',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.onSurface.withOpacity(0.88),
            ),
          ),
          const SizedBox(height: 8),
          if (total == 0)
            Text(
              'No hay noticias para este día.',
              style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.65)),
            )
          else
            ...preview.map((n) {
              final cerrada = n.pendiente == false;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      cerrada ? Icons.check_circle : Icons.schedule,
                      size: 16,
                      color: cerrada ? theme.colorScheme.secondary : theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        n.noticia,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              );
            }),
          if (total > preview.length) ...[
            const SizedBox(height: 6),
            Text(
              '…y ${total - preview.length} más',
              style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.60), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _nombreActual = widget.reporteroNombre;
    _selectedMonthInYear = _focusedDay.month;

    _initPermisoCrearNoticias();
    _refrescarPermisoCrearNoticiasDesdeServidor(showError: false);
    _cargarNoticias();
  }

  Future<void> _initPermisoCrearNoticias() async {
    if (widget.puedeCrearNoticias != null) {
      AuthController.puedeCrearNoticias.value = widget.puedeCrearNoticias!;
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool('auth_puede_crear_noticias') ??
          prefs.getBool('last_puede_crear_noticias') ??
          false;
      AuthController.puedeCrearNoticias.value = v;
    } catch (_) {
      AuthController.puedeCrearNoticias.value = false;
    }
  }

  Future<void> _refrescarPermisoCrearNoticiasDesdeServidor({bool showError = false}) async {
    try {
      final v = await ApiService.getPermisoCrearNoticias();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auth_puede_crear_noticias', v);
      await prefs.setBool('last_puede_crear_noticias', v);

      AuthController.puedeCrearNoticias.value = v;
    } catch (e) {
      if (showError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No pude refrescar permiso: $e')),
        );
      }
    }
  }

  DateTime _soloFecha(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  Future<void> _abrirPerfilAdmin() async {
    Navigator.pop(context);

    final nuevoNombre = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => UpdatePerfilPage(
          reporteroId: widget.reporteroId,
          nombreActual: _nombreActual,
        ),
      ),
    );

    if (nuevoNombre != null && nuevoNombre.trim().isNotEmpty && mounted) {
      setState(() => _nombreActual = nuevoNombre.trim());
    }
  }

  Future<void> _limpiarSesionLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('ws_token');
      await prefs.remove('auth_reportero_id');
      await prefs.remove('auth_nombre');
      await prefs.remove('auth_role');
      await prefs.remove('auth_puede_crear_noticias');
      await prefs.setBool('auth_logged_in', false);
    } catch (_) {}
    AuthController.puedeCrearNoticias.value = false;
  }

  void _confirmarCerrarSesion() {
    Navigator.pop(context);

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
            onPressed: () async {
              Navigator.pop(context);
              await _limpiarSesionLocal();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
            child: const Text('Cerrar Sesión'),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerAdmin() {
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(_nombreActual),
            accountEmail: const Text('Admin'),
            currentAccountPicture: CircleAvatar(
              child: Text(
                _nombreActual.isNotEmpty ? _nombreActual[0].toUpperCase() : 'A',
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Perfil'),
            onTap: _abrirPerfilAdmin,
          ),
          ListTile(
            leading: const Icon(Icons.article),
            title: const Text('Gestión Noticias'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GestionNoticiasPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: const Text('Estadísticas'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EstadisticasScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.manage_accounts),
            title: const Text('Gestión'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GestionReporterosPage()),
              );
            },
          ),
          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red)),
            onTap: _confirmarCerrarSesion,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _cargarNoticias() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final noticias = widget.esAdmin
          ? await ApiService.getNoticiasAdmin()
          : await ApiService.getNoticiasAgenda(widget.reporteroId);

      _eventosPorDia.clear();

      for (final n in noticias) {
        if (n.fechaCita == null) continue;
        final fechaClave = _soloFecha(n.fechaCita!);
        _eventosPorDia.putIfAbsent(fechaClave, () => []);
        _eventosPorDia[fechaClave]!.add(n);
      }

      setState(() {
        _selectedDay = _selectedDay ?? _soloFecha(_focusedDay);
      });
    } catch (e) {
      setState(() {
        _error = 'Error al cargar agenda: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  List<Noticia> _eventosDeDia(DateTime day) {
    final clave = _soloFecha(day);
    return _eventosPorDia[clave] ?? [];
  }

  List<Noticia> _eventosDelMes(DateTime mesRef) {
    final List<Noticia> result = [];
    _eventosPorDia.forEach((fecha, lista) {
      if (fecha.year == mesRef.year && fecha.month == mesRef.month) {
        result.addAll(lista);
      }
    });

    result.sort((a, b) {
      final fa = a.fechaCita ?? DateTime(2100);
      final fb = b.fechaCita ?? DateTime(2100);
      return fa.compareTo(fb);
    });

    return result;
  }

  String _nombreMes(int month) {
    const nombres = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    return nombres[month - 1];
  }

  String _formatearFechaCorta(DateTime fecha) {
    final d = fecha.day.toString().padLeft(2, '0');
    final m = fecha.month.toString().padLeft(2, '0');
    final y = fecha.year.toString();
    return '$d/$m/$y';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AuthController.puedeCrearNoticias,
      builder: (context, showFabCrear, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text('Agenda de ${widget.reporteroNombre}'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Actualizar',
                onPressed: _loading
                    ? null
                    : () async {
                        await _refrescarPermisoCrearNoticiasDesdeServidor(showError: false);
                        await _cargarNoticias();
                      },
              ),
            ],
          ),
          drawer: widget.esAdmin ? _buildDrawerAdmin() : null,
          body: _wrapWebWidth(_buildBody(showFabCrear: showFabCrear)),
          floatingActionButton: showFabCrear
              ? FloatingActionButton.extended(
                  icon: const Icon(Icons.add),
                  label: const Text('Crear noticia'),
                  onPressed: () async {
                    final creado = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(builder: (_) => const CrearNoticiaPage()),
                    );
                    if (creado == true) {
                      await _refrescarPermisoCrearNoticiasDesdeServidor(showError: false);
                      await _cargarNoticias();
                    }
                  },
                )
              : null,
        );
      },
    );
  }

  Widget _buildBody({required bool showFabCrear}) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text(_error!));
    }

    if (_eventosPorDia.isEmpty) {
      return const Center(child: Text('No hay citas registradas en la agenda.'));
    }

    return Container(
      color: kIsWeb ? theme.colorScheme.surface : null,
      child: Column(
        children: [
          const SizedBox(height: 10),
          _buildSelectorVista(),
          const SizedBox(height: 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: KeyedSubtree(
                key: ValueKey(_vista),
                child: _buildVistaActual(showFabCrear: showFabCrear),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorVista() {
    final theme = Theme.of(context);
    final wide = _isWebWide(context);

    final segmented = SegmentedButton<AgendaView>(
      segments: const [
        ButtonSegment(
          value: AgendaView.year,
          label: Text('Año'),
          icon: Icon(Icons.calendar_view_month),
        ),
        ButtonSegment(
          value: AgendaView.month,
          label: Text('Mes'),
          icon: Icon(Icons.calendar_month),
        ),
        ButtonSegment(
          value: AgendaView.day,
          label: Text('Día'),
          icon: Icon(Icons.view_day),
        ),
      ],
      selected: <AgendaView>{_vista},
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        padding: MaterialStatePropertyAll(
          EdgeInsets.symmetric(horizontal: wide ? 18 : 12, vertical: wide ? 12 : 10),
        ),
      ),
      onSelectionChanged: (set) {
        setState(() => _vista = set.first);
      },
    );

    final shell = _cardShell(
      elevation: 0,
      color: theme.colorScheme.surface,
      padding: EdgeInsets.symmetric(horizontal: wide ? 10 : 8, vertical: wide ? 8 : 6),
      child: Row(
        children: [
          const SizedBox(width: 10),
          Expanded(child: segmented),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _selectorHPad(context)),
      child: wide
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: shell,
              ),
            )
          : shell,
    );
  }

  Widget _buildVistaActual({required bool showFabCrear}) {
    switch (_vista) {
      case AgendaView.year:
        return _buildVistaYear(showFabCrear: showFabCrear);
      case AgendaView.month:
        return _buildVistaMonth(showFabCrear: showFabCrear);
      case AgendaView.day:
        return _buildVistaDay(showFabCrear: showFabCrear);
    }
  }

  // ---------- Vista Año ----------
  Widget _buildVistaYear({required bool showFabCrear}) {
    final year = _focusedDay.year;
    final theme = Theme.of(context);

    final Map<int, int> eventosPorMes = {};
    _eventosPorDia.forEach((fecha, lista) {
      if (fecha.year == year) {
        eventosPorMes.update(
          fecha.month,
          (value) => value + lista.length,
          ifAbsent: () => lista.length,
        );
      }
    });

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _hPad(context)),
          child: _cardShell(
            elevation: 0.5,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Año anterior',
                  onPressed: () {
                    setState(() {
                      _focusedDay = DateTime(year - 1, _selectedMonthInYear, 1);
                    });
                  },
                ),
                Text(
                  '$year',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Año siguiente',
                  onPressed: () {
                    setState(() {
                      _focusedDay = DateTime(year + 1, _selectedMonthInYear, 1);
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Builder(
            builder: (context) {
              final bottomSafe = MediaQuery.of(context).padding.bottom;
              final fabClearance = showFabCrear ? 110.0 : 0.0;

              return LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  int crossAxisCount = 3;
                  double aspect = 0.95;

                  if (kIsWeb) {
                    if (w >= 1200) {
                      crossAxisCount = 6;
                      aspect = 1.15;
                    } else if (w >= 980) {
                      crossAxisCount = 5;
                      aspect = 1.10;
                    } else if (w >= 720) {
                      crossAxisCount = 4;
                      aspect = 1.02;
                    }
                  }

                  final grid = GridView.builder(
                    padding: EdgeInsets.fromLTRB(
                      _hPad(context),
                      2,
                      _hPad(context),
                      8 + fabClearance + bottomSafe,
                    ),
                    physics: const AlwaysScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: aspect,
                    ),
                    itemCount: 12,
                    itemBuilder: (context, index) {
                      final month = index + 1;
                      final count = eventosPorMes[month] ?? 0;
                      final nombreMes = _nombreMes(month);
                      final bool tieneEventos = count > 0;
                      final bool esSeleccionado = month == _selectedMonthInYear;

                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          setState(() {
                            _focusedDay = DateTime(year, month, 1);
                            _vista = AgendaView.month;
                            _selectedMonthInYear = month;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: esSeleccionado
                                ? theme.colorScheme.primaryContainer
                                : tieneEventos
                                    ? theme.colorScheme.primaryContainer.withOpacity(0.75)
                                    : theme.colorScheme.surface,
                            border: Border.all(
                              color: esSeleccionado
                                  ? theme.colorScheme.primary
                                  : (tieneEventos ? theme.colorScheme.primary : theme.dividerColor),
                              width: esSeleccionado ? 2.0 : (tieneEventos ? 1.2 : 0.8),
                            ),
                            boxShadow: [
                              BoxShadow(
                                blurRadius: esSeleccionado ? 7 : 4,
                                offset: const Offset(0, 2),
                                color: Colors.black.withOpacity(esSeleccionado ? 0.14 : 0.07),
                              )
                            ],
                          ),
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Builder(
                                builder: (context) {
                                  final efem = efemerideMes(month, theme);
                                  return Tooltip(
                                    message: efem.tooltip,
                                    child: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: efem.color,
                                      child: Icon(efem.icon, size: 18, color: Colors.white),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 10),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  nombreMes,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceVariant.withOpacity(0.55),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  tieneEventos ? '$count noticias' : 'Sin noticias',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: tieneEventos
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface.withOpacity(0.70),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );

                  return _maybeScrollbar(child: grid);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------- Vista Mes ----------
  Widget _buildVistaMonth({required bool showFabCrear}) {
    final theme = Theme.of(context);
    final eventosMes = _eventosDelMes(_focusedDay);
    final wide = _isWebWide(context);

    int cmpFecha(Noticia a, Noticia b) {
      final da = a.fechaCita ?? DateTime(9999);
      final db = b.fechaCita ?? DateTime(9999);
      final c = da.compareTo(db);
      if (c != 0) return c;
      return a.id.compareTo(b.id);
    }

    final pendientes = eventosMes.where((n) => n.pendiente == true).toList()..sort(cmpFecha);
    final cerradas = eventosMes.where((n) => n.pendiente == false).toList()..sort(cmpFecha);
    final eventosMesOrdenados = [...pendientes, ...cerradas];

    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final fabClearance = showFabCrear ? 110.0 : 0.0;

    Widget buildCalendarCard() {
      return _cardShell(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (context, calConstraints) {
            final double headerAndWeekdaysApprox = wide ? 100.0 : 92.0;
            const int rows = 6;

            final double computedRowHeight =
                (calConstraints.maxHeight - headerAndWeekdaysApprox) / rows;

            final double rowHeight = computedRowHeight.clamp(32.0, wide ? 54.0 : 46.0);

            return TableCalendar<Noticia>(
              locale: 'es_MX',
              firstDay: DateTime.utc(2000, 1, 1),
              lastDay: DateTime.utc(2100, 12, 31),
              focusedDay: _focusedDay,
              startingDayOfWeek: StartingDayOfWeek.monday,
              calendarFormat: CalendarFormat.month,
              rowHeight: rowHeight,
              daysOfWeekHeight: wide ? 20 : 18,
              selectedDayPredicate: (day) =>
                  _selectedDay != null && _soloFecha(day) == _soloFecha(_selectedDay!),
              eventLoader: _eventosDeDia,
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = _soloFecha(selectedDay);
                  _focusedDay = focusedDay;
                  _selectedMonthInYear = focusedDay.month;
                  _vista = AgendaView.day;
                });
              },
              onPageChanged: (focusedDay) {
                setState(() {
                  _focusedDay = focusedDay;
                  _selectedMonthInYear = focusedDay.month;
                });
              },
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                cellMargin: EdgeInsets.zero,
                cellPadding: EdgeInsets.zero,
                markersAlignment: Alignment.bottomRight,
                markersMaxCount: 1,
              ),
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: TextStyle(
                  fontSize: wide ? 17 : 16,
                  fontWeight: FontWeight.bold,
                ),
                titleTextFormatter: (date, locale) {
                  final mes = _nombreMes(date.month);
                  return '$mes ${date.year}';
                },
                leftChevronIcon: const Icon(Icons.chevron_left),
                rightChevronIcon: const Icon(Icons.chevron_right),
                headerPadding: const EdgeInsets.symmetric(vertical: 6),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                ),
                weekendStyle: TextStyle(
                  color: theme.colorScheme.error.withOpacity(0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (context, day, focusedDay) => _calDayCell(
                  theme: theme,
                  day: day,
                  wide: wide,
                ),
                todayBuilder: (context, day, focusedDay) => _calDayCell(
                  theme: theme,
                  day: day,
                  wide: wide,
                  isToday: true,
                ),
                selectedBuilder: (context, day, focusedDay) => _calDayCell(
                  theme: theme,
                  day: day,
                  wide: wide,
                  isSelected: true,
                ),
                outsideBuilder: (context, day, focusedDay) => _calDayCell(
                  theme: theme,
                  day: day,
                  wide: wide,
                  isOutside: true,
                ),
                markerBuilder: (context, day, events) {
                  if (events.isEmpty) return const SizedBox.shrink();
                  final count = events.length;

                  return Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                            color: Colors.black.withOpacity(0.10),
                          ),
                        ],
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      );
    }

    Widget buildListCard() {
      final list = eventosMes.isEmpty
          ? const Center(child: Text('No hay noticias registradas en este mes.'))
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(0, 6, 0, 10 + fabClearance + bottomSafe),
              itemCount: eventosMesOrdenados.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final n = eventosMesOrdenados[index];
                final fecha = n.fechaCita != null ? _formatearFechaCorta(n.fechaCita!) : 'Sin fecha';
                final bool cerrada = (n.pendiente == false);

                return ListTile(
                  dense: true,
                  visualDensity: kIsWeb ? VisualDensity.compact : null,
                  leading: Icon(
                    cerrada ? Icons.check_circle : Icons.schedule,
                    color: cerrada ? theme.colorScheme.secondary : theme.colorScheme.primary,
                  ),
                  title: Text(
                    n.noticia,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Fecha: $fecha',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NoticiaDetallePage(
                          noticia: n,
                          soloLectura: (n.pendiente == false),
                          role: widget.esAdmin ? 'admin' : 'reportero',
                        ),
                      ),
                    );
                    await _cargarNoticias();
                  },
                );
              },
            );

      return _cardShell(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_nombreMes(_focusedDay.month)} ${_focusedDay.year}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: wide ? 15 : 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${eventosMesOrdenados.length} noticias',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _maybeScrollbar(child: list)),
          ],
        ),
      );
    }

    if (wide) {
      return Padding(
        padding: EdgeInsets.fromLTRB(_hPad(context), 0, _hPad(context), 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 6, child: buildCalendarCard()),
            VerticalDivider(
              width: 14,
              thickness: 1,
              color: theme.dividerColor.withOpacity(0.20),
            ),
            Expanded(flex: 5, child: buildListCard()),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const double calendarFactor = 0.55;

        final double totalH = constraints.maxHeight;
        final double calendarH = totalH * calendarFactor;
        final double listH = totalH - calendarH - 10;

        return Column(
          children: [
            SizedBox(
              height: calendarH,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: _hPad(context)),
                child: buildCalendarCard(),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: listH < 0 ? 0 : listH,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: _hPad(context)),
                child: buildListCard(),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------- Vista Día ----------
  Widget _buildVistaDay({required bool showFabCrear}) {
    final dia = _selectedDay ?? _soloFecha(DateTime.now());
    final eventos = _eventosDeDia(dia);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final fabClearance = showFabCrear ? 110.0 : 0.0;
    final wide = _isWebWide(context);

    final header = _cardShell(
      elevation: 0,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: wide ? 14 : 12),
      color: isDark ? theme.colorScheme.surface : theme.colorScheme.surfaceVariant.withOpacity(0.35),
      child: Center(
        child: Text(
          '${_nombreMes(dia.month)} ${dia.day}, ${dia.year}',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: wide ? 17 : 16,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );

    final list = eventos.isEmpty
        ? const Center(child: Text('No hay noticias para este día.'))
        : ListView.builder(
            padding: EdgeInsets.only(bottom: 16 + fabClearance + bottomSafe),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: eventos.length,
            itemBuilder: (context, index) {
              final n = eventos[index];
              final bool cerrada = (n.pendiente == false);

              final Color? bg = cerrada
                  ? (isDark
                      ? theme.colorScheme.secondary.withOpacity(0.18)
                      : theme.colorScheme.secondary.withOpacity(0.10))
                  : null;

              final fecha = n.fechaCita != null ? _formatearFechaCorta(n.fechaCita!) : 'Sin fecha';

              return Card(
                color: bg,
                margin: EdgeInsets.symmetric(horizontal: _hPad(context), vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: kIsWeb ? 0.5 : 1,
                child: Padding(
                  padding: EdgeInsets.all(wide ? 14 : 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              n.noticia,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: wide ? 16 : 15,
                              ),
                            ),
                          ),
                          if (cerrada) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceVariant.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Cerrada',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Domicilio: ${n.domicilio ?? 'Sin domicilio'}',
                        style: TextStyle(fontSize: wide ? 13.5 : 13),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Fecha: $fecha',
                        style: TextStyle(
                          fontSize: wide ? 13.5 : 13,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Ir a detalles'),
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NoticiaDetallePage(
                                  noticia: n,
                                  soloLectura: (n.pendiente == false),
                                  role: widget.esAdmin ? 'admin' : 'reportero',
                                ),
                              ),
                            );
                            await _cargarNoticias();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );

    if (wide) {
      final side = _daySidePanel(theme: theme, dia: dia, eventos: eventos);

      return Padding(
        padding: EdgeInsets.fromLTRB(_hPad(context), 0, _hPad(context), 10),
        child: Column(
          children: [
            header,
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 7,
                    child: _maybeScrollbar(child: list),
                  ),
                  VerticalDivider(
                    width: 14,
                    thickness: 1,
                    color: theme.dividerColor.withOpacity(0.20),
                  ),
                  Expanded(
                    flex: 4,
                    child: _maybeScrollbar(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: side,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(_hPad(context), 0, _hPad(context), 10),
      child: Column(
        children: [
          header,
          const SizedBox(height: 10),
          Expanded(child: _maybeScrollbar(child: list)),
        ],
      ),
    );
  }
}
