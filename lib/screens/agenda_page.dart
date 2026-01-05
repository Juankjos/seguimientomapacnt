import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/noticia.dart';
import '../services/api_service.dart';
import 'noticia_detalle_page.dart';
import 'crear_noticia_page.dart';
import 'login_screen.dart';
import 'update_perfil_page.dart';
import 'gestion_reporteros_page.dart';
import 'gestion_noticias_page.dart';

enum AgendaView { year, month, day }

/// ------------ EFEMÉRIDES POR MES (TOP-LEVEL) ------------

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
        // Enero – Año Nuevo
        return MesEfemeride(
          icon: Icons.celebration,
          color: Color(0xFFF94144),
          tooltip: 'Año Nuevo',
        );
      case 2:
        // Febrero – San Valentín / Amor y amistad
        return MesEfemeride(
          icon: Icons.favorite,
          color: Color(0xFFF3722C),
          tooltip: 'Día del Amor y la Amistad',
        );
      case 3:
        // Marzo – Primavera / Natalicio de Benito Juárez
        return MesEfemeride(
          icon: Icons.emoji_nature ,
          color: Color(0xFFF8961E),
          tooltip: 'Primavera',
        );
      case 4:
        // Abril – Día del Niño
        return MesEfemeride(
          icon: Icons.face_outlined,
          color: Color(0xFFF9844A),
          tooltip: 'Día del Niño',
        );
      case 5:
        // Mayo – Día de las Madres
        return MesEfemeride(
          icon: Icons.face_2_rounded,
          color: Color(0xFFF9C74F),
          tooltip: 'Día de las Madres',
        );
      case 6:
        // Junio – Verano
        return MesEfemeride(
          icon: Icons.wb_sunny,
          color: Color(0xFF90BE6D),
          tooltip: 'Verano',
        );
      case 7:
        // Julio – Vacaciones de verano
        return MesEfemeride(
          icon: Icons.beach_access,
          color: Color(0xFF43AA8B),
          tooltip: 'Vacaciones de verano',
        );
      case 8:
        // Agosto – Regreso a clases
        return MesEfemeride(
          icon: Icons.school,
          color: Color(0xFF4D908E),
          tooltip: 'Regreso a clases',
        );
      case 9:
        // Septiembre – Independencia de México
        return MesEfemeride(
          icon: Icons.flag,
          color: Color(0xFF577590),
          tooltip: 'Independencia de México',
        );
      case 10:
        // Octubre – Otoño / Día de Muertos cerca
        return MesEfemeride(
          icon: Icons.nights_stay,
          color: Color(0xFF277DA1),
          tooltip: 'Día de Muertos',
        );
      case 11:
        // Noviembre – Día de Muertos / Revolución Mexicana
        return MesEfemeride(
          icon: Icons.local_florist,
          color: Color(0xFF4D908E),
          tooltip: 'Día de Muertos',
        );
      case 12:
        // Diciembre – Navidad
        return MesEfemeride(
          icon: Icons.ice_skating_outlined,
          color: Color(0xFFF94144),
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

  const AgendaPage({
    super.key,
    required this.reporteroId,
    required this.reporteroNombre,
    this.esAdmin = false,
  });

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  bool _loading = false;
  String? _error;

  // Noticias por día (clave = fecha sin hora)
  final Map<DateTime, List<Noticia>> _eventosPorDia = {};

  // Vista actual
  AgendaView _vista = AgendaView.month;

  // Día y mes enfocados
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  // Último mes visitado (para marcar en vista Año)
  late int _selectedMonthInYear;
  late String _nombreActual;

  @override
  void initState() {
    super.initState();
    _nombreActual = widget.reporteroNombre;
    _selectedMonthInYear = _focusedDay.month;
    _cargarNoticias();
  }

  DateTime _soloFecha(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  Future<void> _abrirPerfilAdmin() async {
    Navigator.pop(context); // cierra drawer

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

  void _confirmarCerrarSesion() {
    Navigator.pop(context); // cierra drawer

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
              Navigator.pop(context); // cierra dialog
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
        // Asumimos que fechaCita es opcional
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

  // Todas las noticias del mes actual (según _focusedDay)
  List<Noticia> _eventosDelMes(DateTime mesRef) {
    final List<Noticia> result = [];
    _eventosPorDia.forEach((fecha, lista) {
      if (fecha.year == mesRef.year && fecha.month == mesRef.month) {
        result.addAll(lista);
      }
    });

    // Ordenar por fecha
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
    return Scaffold(
      appBar: AppBar(
        title: Text('Agenda de ${widget.reporteroNombre}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _cargarNoticias,
          ),
        ],
      ),
      drawer: widget.esAdmin ? _buildDrawerAdmin() : null, 
      body: _buildBody(),
      floatingActionButton: widget.esAdmin
      ? FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('Crear noticia'),
          onPressed: () async {
            final creado = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => const CrearNoticiaPage(),
              ),
            );
            if (creado == true) {
              _cargarNoticias();
            }
          },
        )
      : null,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text(_error!));
    }

    if (_eventosPorDia.isEmpty) {
      return const Center(
        child: Text('No hay citas registradas en la agenda.'),
      );
    }

    return Column(
      children: [
        const SizedBox(height: 8),
        _buildSelectorVista(),
        const SizedBox(height: 8),
        Expanded(
          child: _buildVistaActual(),
        ),
      ],
    );
  }

  Widget _buildSelectorVista() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SegmentedButton<AgendaView>(
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
        onSelectionChanged: (set) {
          setState(() {
            _vista = set.first;
          });
        },
      ),
    );
  }

  Widget _buildVistaActual() {
    switch (_vista) {
      case AgendaView.year:
        return _buildVistaYear();
      case AgendaView.month:
        return _buildVistaMonth();
      case AgendaView.day:
        return _buildVistaDay();
    }
  }

  // ---------- Vista Año ----------

  Widget _buildVistaYear() {
    final year = _focusedDay.year;
    final theme = Theme.of(context);

    // Calculamos eventos por mes
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
        // Header del año con fondo y flechas
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() {
                    _focusedDay = DateTime(year - 1, _selectedMonthInYear, 1);
                  });
                },
              ),
              Text(
                '$year',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() {
                    _focusedDay = DateTime(year + 1, _selectedMonthInYear, 1);
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        Expanded(
          child: Builder(
            builder: (context) {
              final bottomSafe = MediaQuery.of(context).padding.bottom;
              const fabClearance = 110.0;

              return GridView.builder(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + fabClearance + bottomSafe),
                physics: const AlwaysScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.95,
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
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: esSeleccionado
                            ? theme.colorScheme.primaryContainer
                            : tieneEventos
                                ? theme.colorScheme.primaryContainer.withOpacity(0.8)
                                : theme.colorScheme.surface,
                        border: Border.all(
                          color: esSeleccionado
                              ? theme.colorScheme.primary
                              : (tieneEventos ? theme.colorScheme.primary : theme.dividerColor),
                          width: esSeleccionado ? 2.0 : (tieneEventos ? 1.4 : 0.8),
                        ),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: esSeleccionado ? 6 : 4,
                            offset: const Offset(0, 2),
                            color: Colors.black.withOpacity(esSeleccionado ? 0.15 : 0.08),
                          )
                        ],
                      ),
                      padding: const EdgeInsets.all(8),
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
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              nombreMes,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              tieneEventos ? '$count noticias' : 'Sin noticias',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: tieneEventos
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface.withOpacity(0.70),
                                fontWeight: tieneEventos || esSeleccionado
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              textAlign: TextAlign.center,
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
      ],
    );
  }

  // ---------- Vista Mes ----------

  Widget _buildVistaMonth() {
    final theme = Theme.of(context);
    final eventosMes = _eventosDelMes(_focusedDay);

    int _cmpFecha(Noticia a, Noticia b) {
      // null al final
      final da = a.fechaCita ?? DateTime(9999);
      final db = b.fechaCita ?? DateTime(9999);

      final c = da.compareTo(db);
      if (c != 0) return c;

      // desempate estable
      return a.id.compareTo(b.id);
    }

    final pendientes = eventosMes.where((n) => n.pendiente == true).toList()..sort(_cmpFecha);
    final cerradas   = eventosMes.where((n) => n.pendiente == false).toList()..sort(_cmpFecha);

    // Pendientes primero, luego cerradas
    final eventosMesOrdenados = [...pendientes, ...cerradas];

    return LayoutBuilder(
      builder: (context, constraints) {
        const double calendarFactor = 0.55;

        final double totalH = constraints.maxHeight;
        final double calendarH = totalH * calendarFactor;
        final double listH = totalH - calendarH - 8;

        return Column(
          children: [
            // ---------------- CALENDARIO ----------------
            SizedBox(
              height: calendarH,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: LayoutBuilder(
                      builder: (context, calConstraints) {
                        const double headerAndWeekdaysApprox = 92.0;
                        const int rows = 6;

                        final double computedRowHeight =
                            (calConstraints.maxHeight - headerAndWeekdaysApprox) /
                                rows;

                        final double rowHeight = computedRowHeight
                            .clamp(32.0, 46.0);

                        return TableCalendar<Noticia>(
                          locale: 'es_MX',
                          firstDay: DateTime.utc(2000, 1, 1),
                          lastDay: DateTime.utc(2100, 12, 31),
                          focusedDay: _focusedDay,
                          startingDayOfWeek: StartingDayOfWeek.monday,
                          calendarFormat: CalendarFormat.month,

                          rowHeight: rowHeight,
                          daysOfWeekHeight: 18,

                          selectedDayPredicate: (day) =>
                              _selectedDay != null &&
                              _soloFecha(day) == _soloFecha(_selectedDay!),

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
                            todayDecoration: BoxDecoration(
                              color: theme.colorScheme.primary.withOpacity(0.7),
                              shape: BoxShape.circle,
                            ),
                            todayTextStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            selectedDecoration: BoxDecoration(
                              color: theme.colorScheme.secondary,
                              shape: BoxShape.circle,
                            ),
                            selectedTextStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            weekendTextStyle: TextStyle(
                              color: theme.colorScheme.error,
                            ),
                            outsideDaysVisible: false,
                            markersAlignment: Alignment.bottomRight,
                            markersMaxCount: 1,
                          ),

                          headerStyle: HeaderStyle(
                            formatButtonVisible: false,
                            titleCentered: true,
                            titleTextStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            titleTextFormatter: (date, locale) {
                              final mes = _nombreMes(date.month);
                              return '$mes ${date.year}';
                            },
                            leftChevronIcon: const Icon(Icons.chevron_left),
                            rightChevronIcon: const Icon(Icons.chevron_right),
                            headerPadding:
                                const EdgeInsets.symmetric(vertical: 6),
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
                            markerBuilder: (context, day, events) {
                              if (events.isEmpty) return const SizedBox.shrink();
                              final count = events.length;

                              return Positioned(
                                bottom: 2,
                                right: 2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$count',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ---------------- NOTICIAS DEL MES (altura fija) ----------------
            SizedBox(
              height: listH < 0 ? 0 : listH,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_nombreMes(_focusedDay.month)} ${_focusedDay.year}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${eventosMesOrdenados.length} noticias',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: eventosMes.isEmpty
                            ? const Center(
                                child:
                                    Text('No hay noticias registradas en este mes.'),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                itemCount: eventosMesOrdenados.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final n = eventosMesOrdenados[index];
                                  final fecha = n.fechaCita != null
                                      ? _formatearFechaCorta(n.fechaCita!)
                                      : 'Sin fecha';
                                  final bool cerrada = (n.pendiente == false);

                                  return ListTile(
                                    dense: true,
                                    leading: Icon(
                                      cerrada
                                          ? Icons.check_circle
                                          : Icons.schedule,
                                      color: cerrada
                                          ? theme.colorScheme.secondary 
                                          : theme.colorScheme.primary,
                                    ),
                                    title: Text(
                                      n.noticia,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
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
                                            role: widget.esAdmin
                                                ? 'admin'
                                                : 'reportero',
                                          ),
                                        ),
                                      );
                                      await _cargarNoticias();
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------- Vista Día ----------

  Widget _buildVistaDay() {
    final dia = _selectedDay ?? _soloFecha(DateTime.now());
    final eventos = _eventosDeDia(dia);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: isDark ? theme.colorScheme.surfaceVariant : Colors.grey.shade200,
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          child: Text(
            '${_nombreMes(dia.month)} ${dia.day}, ${dia.year}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: eventos.isEmpty
              ? const Center(
                  child: Text('No hay noticias para este día.'),
                )
              : ListView.builder(
                  padding: EdgeInsets.only(
                    bottom: 16 + (widget.esAdmin ? 110.0 : 0.0) + MediaQuery.of(context).padding.bottom,
                  ),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: eventos.length,
                  itemBuilder: (context, index) {
                    final n = eventos[index];

                    final bool cerrada = (n.pendiente == false);
                    final theme = Theme.of(context);
                    final isDark = theme.brightness == Brightness.dark;

                    final Color? bg = cerrada
                        ? (isDark
                            ? theme.colorScheme.secondary.withOpacity(0.18)
                            : theme.colorScheme.secondary.withOpacity(0.12))
                        : null;

                    final fecha = n.fechaCita != null
                        ? _formatearFechaCorta(n.fechaCita!)
                        : 'Sin fecha';

                    return Card(
                      color: bg,
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    n.noticia,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                if (cerrada) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text(
                                      'Cerrada',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Domicilio: ${n.domicilio ?? 'Sin domicilio'}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Fecha: $fecha',
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.open_in_new, size: 16),
                                label: const Text('Ir a detalles'),
                                onPressed: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          NoticiaDetallePage(
                                            noticia: n,
                                            soloLectura: (n.pendiente == false),
                                            role: widget.esAdmin ? 'admin' : 'reportero',)
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
                ),
        ),
      ],
    );
  }
}
