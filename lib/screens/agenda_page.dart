import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/noticia.dart';
import '../services/api_service.dart';
import 'noticia_detalle_page.dart';

enum AgendaView { year, month, day }

class AgendaPage extends StatefulWidget {
  final int reporteroId;
  final String reporteroNombre;

  const AgendaPage({
    super.key,
    required this.reporteroId,
    required this.reporteroNombre,
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

  @override
  void initState() {
    super.initState();
    _cargarNoticias();
  }

  DateTime _soloFecha(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);

  Future<void> _cargarNoticias() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final noticias =
          await ApiService.getNoticias(widget.reporteroId);

      _eventosPorDia.clear();

      for (final n in noticias) {
        if (n.fechaCita == null) continue; // solo con fecha_cita
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

  // ---------- UI ----------

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
      body: _buildBody(),
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

  // ---------- Vista Año: header con año + cuadritos por mes ----------

  Widget _buildVistaYear() {
    final year = _focusedDay.year;

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

    final theme = Theme.of(context);

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
                    _focusedDay = DateTime(year - 1, _focusedDay.month, 1);
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
                    _focusedDay = DateTime(year + 1, _focusedDay.month, 1);
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.1,
            ),
            itemCount: 12,
            itemBuilder: (context, index) {
              final month = index + 1;
              final count = eventosPorMes[month] ?? 0;
              final nombreMes = _nombreMes(month);

              final bool tieneEventos = count > 0;

              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  setState(() {
                    _focusedDay = DateTime(year, month, 1);
                    _vista = AgendaView.month;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: tieneEventos
                        ? theme.colorScheme.primaryContainer.withOpacity(0.8)
                        : theme.colorScheme.surface,
                    border: Border.all(
                      color: tieneEventos
                          ? theme.colorScheme.primary
                          : theme.dividerColor,
                      width: tieneEventos ? 1.4 : 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                        color: Colors.black.withOpacity(0.08),
                      )
                    ],
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Inicial grande del mes
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: tieneEventos
                            ? theme.colorScheme.primary
                            : theme.colorScheme.secondaryContainer,
                        child: Text(
                          nombreMes.characters.first,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        nombreMes,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tieneEventos ? '$count noticias' : 'Sin noticias',
                        style: TextStyle(
                          fontSize: 11,
                          color: tieneEventos
                              ? theme.colorScheme.primary
                              : Colors.grey,
                          fontWeight:
                              tieneEventos ? FontWeight.w600 : FontWeight.normal,
                        ),
                        textAlign: TextAlign.center,
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

  // ---------- Vista Mes: calendario con marcadores ----------

  Widget _buildVistaMonth() {
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TableCalendar<Noticia>(
                  locale: 'es_MX',
                  firstDay: DateTime.utc(2000, 1, 1),
                  lastDay: DateTime.utc(2100, 12, 31),
                  focusedDay: _focusedDay,
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  calendarFormat: CalendarFormat.month,
                  selectedDayPredicate: (day) =>
                      _selectedDay != null &&
                      _soloFecha(day) == _soloFecha(_selectedDay!),
                  eventLoader: _eventosDeDia,
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = _soloFecha(selectedDay);
                      _focusedDay = focusedDay;
                      _vista = AgendaView.day;
                    });
                  },
                  onPageChanged: (focusedDay) {
                    _focusedDay = focusedDay;
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
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    titleTextFormatter: (date, locale) {
                      final mes = _nombreMes(date.month);
                      return '$mes ${date.year}';
                    },
                    leftChevronIcon: const Icon(Icons.chevron_left),
                    rightChevronIcon: const Icon(Icons.chevron_right),
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
                              horizontal: 4, vertical: 1),
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
                ),
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          color: Colors.grey.shade200,
          padding: const EdgeInsets.all(8),
          child: Text(
            '${_nombreMes(_focusedDay.month)} ${_focusedDay.year}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // ---------- Vista Día: lista de noticias del día ----------

  Widget _buildVistaDay() {
    final dia = _selectedDay ?? _soloFecha(DateTime.now());
    final eventos = _eventosDeDia(dia);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: Colors.grey.shade200,
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          child: Text(
            '${_nombreMes(dia.month)} ${dia.day}, ${dia.year}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
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
                  itemCount: eventos.length,
                  itemBuilder: (context, index) {
                    final n = eventos[index];
                    final fecha = n.fechaCita != null
                        ? _formatearFechaCorta(n.fechaCita!)
                        : 'Sin fecha';

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              n.noticia,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Domicilio: ${n.domicilio ?? 'Sin domicilio'}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Fecha: $fecha',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
                                icon: const Icon(
                                  Icons.open_in_new,
                                  size: 16,
                                ),
                                label: const Text('Ir a detalles'),
                                onPressed: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          NoticiaDetallePage(noticia: n),
                                    ),
                                  );
                                  // Al volver, recargamos la agenda
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
