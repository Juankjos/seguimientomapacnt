// lib/screens/estadisticas_dias.dart
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

import '../models/noticia.dart';
import '../models/reportero_admin.dart';

class EstadisticasDias extends StatefulWidget {
  final int year;
  final int month;
  final String monthName;
  final List<ReporteroAdmin> reporteros;
  final List<Noticia> noticias;

  const EstadisticasDias({
    super.key,
    required this.year,
    required this.month,
    required this.monthName,
    required this.reporteros,
    required this.noticias,
  });

  @override
  State<EstadisticasDias> createState() => _EstadisticasDiasState();
}

class _EstadisticasDiasState extends State<EstadisticasDias> {
  late final DateTime _monthStart;
  late final DateTime _monthEndExclusive;

  late DateTime _focusedDay;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();

    _monthStart = DateTime(widget.year, widget.month, 1);
    _monthEndExclusive = (widget.month == 12)
        ? DateTime(widget.year + 1, 1, 1)
        : DateTime(widget.year, widget.month + 1, 1);

    final now = DateTime.now();
    final today = _dayOnly(DateTime(now.year, now.month, now.day));

    if (!today.isBefore(_monthStart) && today.isBefore(_monthEndExclusive)) {
      _focusedDay = today;
      _selectedDay = today;
    } else {
      _focusedDay = _monthStart;
      _selectedDay = _monthStart;
    }
  }

  // ------------------- Helpers fechas -------------------

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  ({DateTime start, DateTime endExclusive}) _dayBounds(DateTime day) {
    final start = _dayOnly(day);
    final end = start.add(const Duration(days: 1));
    return (start: start, endExclusive: end);
  }

  bool _inRange(DateTime? dt, DateTime start, DateTime endExclusive) {
    if (dt == null) return false;
    return !dt.isBefore(start) && dt.isBefore(endExclusive);
  }

  DateTime _aMinuto(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute);

  bool _esAtrasada(Noticia n) {
    final llegada = n.horaLlegada;
    final cita = n.fechaCita;
    if (llegada == null || cita == null) return false;

    final llegadaMin = _aMinuto(llegada);
    final citaMin = _aMinuto(cita);

    return llegadaMin.isAfter(citaMin);
  }

  // ------------------- “Eventos” del día para el calendario -------------------

  List<Noticia> _noticiasRelevantesDelDia(DateTime day) {
    final b = _dayBounds(day);

    final out = <Noticia>[];
    final seen = <int>{};

    for (final n in widget.noticias) {
      final bool esCompletada = _inRange(n.horaLlegada, b.start, b.endExclusive);
      final bool esAgendada =
          (n.pendiente == true) && _inRange(n.fechaCita, b.start, b.endExclusive);

      if (!esCompletada && !esAgendada) continue;

      final id = n.id;
      if (seen.add(id)) out.add(n);
    }

    return out;
  }

  int _countNoticiasEnDia(DateTime day) => _noticiasRelevantesDelDia(day).length;

  Future<void> _openDayChart(DateTime selected) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DiaChartPage(
          day: selected,
          monthName: widget.monthName,
          year: widget.year,
          reporteros: widget.reporteros,
          noticias: widget.noticias,
        ),
      ),
    );
  }

  // ------------------- UI -------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Días • ${widget.monthName} ${widget.year}'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TableCalendar<Noticia>(
                  locale: 'es_MX',
                  firstDay: _monthStart,
                  lastDay: _monthEndExclusive.subtract(const Duration(days: 1)),
                  focusedDay: _focusedDay,
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  calendarFormat: CalendarFormat.month,
                  availableCalendarFormats: const {CalendarFormat.month: 'Mes'},
                  headerStyle: HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    leftChevronVisible: false,
                    rightChevronVisible: false,
                    titleTextStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    titleTextFormatter: (_, __) => '${widget.monthName} ${widget.year}',
                  ),
                  selectedDayPredicate: (day) =>
                      _selectedDay != null && isSameDay(day, _selectedDay),
                  onDaySelected: (selectedDay, focusedDay) async {
                    final sel = _dayOnly(selectedDay);
                    setState(() {
                      _selectedDay = sel;
                      _focusedDay = _dayOnly(focusedDay);
                    });
                    await _openDayChart(sel);
                  },
                  eventLoader: _noticiasRelevantesDelDia,
                  calendarStyle: CalendarStyle(
                    outsideDaysVisible: false,
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
                    markersAlignment: Alignment.bottomRight,
                    markersMaxCount: 1,
                  ),
                  calendarBuilders: CalendarBuilders(
                    markerBuilder: (context, day, events) {
                      final count = _countNoticiasEnDia(day);
                      if (count <= 0) return const SizedBox.shrink();

                      return Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Toca un día para ver la gráfica.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =================== Pantalla de detalle (chart del día) ===================

class _DiaChartPage extends StatefulWidget {
  final DateTime day;
  final String monthName;
  final int year;
  final List<ReporteroAdmin> reporteros;
  final List<Noticia> noticias;

  const _DiaChartPage({
    required this.day,
    required this.monthName,
    required this.year,
    required this.reporteros,
    required this.noticias,
  });

  @override
  State<_DiaChartPage> createState() => _DiaChartPageState();
}

class _DiaChartPageState extends State<_DiaChartPage> {
  late final TooltipBehavior _tooltip;
  int _animSeed = 0;

  @override
  void initState() {
    super.initState();
    _tooltip = TooltipBehavior(enable: true);
    _animSeed++;
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  ({DateTime start, DateTime endExclusive}) _dayBounds(DateTime day) {
    final start = _dayOnly(day);
    final end = start.add(const Duration(days: 1));
    return (start: start, endExclusive: end);
  }

  bool _inRange(DateTime? dt, DateTime start, DateTime endExclusive) {
    if (dt == null) return false;
    return !dt.isBefore(start) && dt.isBefore(endExclusive);
  }

  bool _isToday(DateTime day) {
    final now = DateTime.now();
    final today = _dayOnly(DateTime(now.year, now.month, now.day));
    return _dayOnly(day) == today;
  }

  DateTime _aMinuto(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute);

  bool _esAtrasada(Noticia n) {
    final llegada = n.horaLlegada;
    final cita = n.fechaCita;
    if (llegada == null || cita == null) return false;
    return _aMinuto(llegada).isAfter(_aMinuto(cita));
  }

  List<_ReporterStats> _buildStatsForDay(DateTime day) {
    final b = _dayBounds(day);
    final bool showEnCurso = _isToday(day);

    final Map<int, _ReporterStats> map = {
      for (final r in widget.reporteros)
        r.id: _ReporterStats(
          reporteroId: r.id,
          nombre: r.nombre,
          completadas: 0,
          atrasadas: 0,
          agendadas: 0,
          enCurso: 0,
        ),
    };

    for (final n in widget.noticias) {
      final rid = n.reporteroId ?? 0;

      if (!map.containsKey(rid)) {
        map[rid] = _ReporterStats(
          reporteroId: rid,
          nombre: rid == 0 ? 'Sin asignar' : 'Reportero #$rid',
          completadas: 0,
          atrasadas: 0,
          agendadas: 0,
          enCurso: 0,
        );
      }

      final cur = map[rid]!;

      if (_inRange(n.horaLlegada, b.start, b.endExclusive)) {
        if (_esAtrasada(n)) {
          map[rid] = cur.copyWith(atrasadas: cur.atrasadas + 1);
        } else {
          map[rid] = cur.copyWith(completadas: cur.completadas + 1);
        }
      }

      final isEnCurso =
          showEnCurso &&
          (n.pendiente == true) &&
          (n.horaLlegada == null) &&
          _inRange(n.fechaCita, b.start, b.endExclusive);

      final isAgendada =
          (n.pendiente == true) &&
          _inRange(n.fechaCita, b.start, b.endExclusive) &&
          !(showEnCurso && isEnCurso);

      if (isAgendada) {
        final after = map[rid]!;
        map[rid] = after.copyWith(agendadas: after.agendadas + 1);
      }

      if (isEnCurso) {
        final after = map[rid]!;
        map[rid] = after.copyWith(enCurso: after.enCurso + 1);
      }
    }

    final list = map.values.toList();
    list.sort((a, b) {
      final sa = _isToday(day) ? a.scoreToday : a.scoreBase;
      final sb = _isToday(day) ? b.scoreToday : b.scoreBase;
      return sb.compareTo(sa);
    });
    return list;
  }

  String _tituloDia(DateTime d) => '${d.day} de ${widget.monthName} del ${widget.year}';

  Widget _pill(ThemeData theme, String text, {double? maxWidth, bool isTotal = false}) {
    final core = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isTotal ? Colors.black : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: isTotal ? Colors.white : theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );

    if (maxWidth == null) return core;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: core,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bool showEnCurso = _isToday(widget.day);
    final stats = _buildStatsForDay(widget.day);

    final totalCompletadas = stats.fold<int>(0, (a, b) => a + b.completadas);
    final totalAtrasadas = stats.fold<int>(0, (a, b) => a + b.atrasadas);
    final totalAgendadas = stats.fold<int>(0, (a, b) => a + b.agendadas);
    final totalEnCurso = stats.fold<int>(0, (a, b) => a + b.enCurso);
    final totalTareas = totalCompletadas + totalAtrasadas + (showEnCurso ? totalEnCurso : totalAgendadas);

    final hasMany = stats.length > 8;

    return Scaffold(
      appBar: AppBar(
        title: Text(_tituloDia(widget.day)),
        actions: [
          IconButton(
            tooltip: 'Re-animar',
            onPressed: () => setState(() => _animSeed++),
            icon: const Icon(Icons.replay),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(
              child: Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, c) {
                          final bool narrow = c.maxWidth < 380;
                          final double? maxPillW = narrow ? (c.maxWidth - 8) / 2 : null;

                          final pills = <Widget>[
                            _pill(theme, 'Total: $totalTareas', maxWidth: maxPillW, isTotal: true),
                            if (!showEnCurso)
                              _pill(theme, 'Agendadas: $totalAgendadas', maxWidth: maxPillW),
                            _pill(theme, 'Completadas: $totalCompletadas', maxWidth: maxPillW),
                            _pill(theme, 'Atrasadas: $totalAtrasadas', maxWidth: maxPillW),
                            if (showEnCurso)
                              _pill(theme, 'En curso: $totalEnCurso', maxWidth: maxPillW),
                          ];

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: pills,
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 10),

                      Expanded(
                        child: SfCartesianChart(
                          key: ValueKey('day_chart_${widget.day.toIso8601String()}_$_animSeed'),
                          tooltipBehavior: _tooltip,
                          legend: const Legend(isVisible: true, position: LegendPosition.bottom),
                          plotAreaBorderWidth: 0,
                          primaryXAxis: CategoryAxis(
                            labelRotation: hasMany ? 45 : 0,
                            labelIntersectAction: AxisLabelIntersectAction.rotate45,
                            majorGridLines: const MajorGridLines(width: 0),
                          ),
                          primaryYAxis: NumericAxis(
                            minimum: 0,
                            interval: 1,
                            numberFormat: NumberFormat('#0'),
                            majorGridLines: MajorGridLines(
                              width: 1,
                              color: theme.dividerColor.withOpacity(0.35),
                            ),
                          ),
                          series: [
                            ColumnSeries<_ReporterStats, String>(
                              name: 'Completadas',
                              dataSource: stats,
                              xValueMapper: (d, _) => d.nombre,
                              yValueMapper: (d, _) => d.completadas,
                              dataLabelMapper: (d, _) =>
                                  d.completadas == 0 ? null : '${d.completadas}',
                              dataLabelSettings: const DataLabelSettings(isVisible: true),
                              animationDuration: 650,
                            ),
                            ColumnSeries<_ReporterStats, String>(
                              name: 'Atrasadas',
                              dataSource: stats,
                              xValueMapper: (d, _) => d.nombre,
                              yValueMapper: (d, _) => d.atrasadas,
                              dataLabelMapper: (d, _) =>
                                  d.atrasadas == 0 ? null : '${d.atrasadas}',
                              dataLabelSettings: const DataLabelSettings(isVisible: true),
                              animationDuration: 650,
                              color: Colors.red.shade900,
                            ),
                            if (showEnCurso)
                              ColumnSeries<_ReporterStats, String>(
                                name: 'En curso',
                                dataSource: stats,
                                xValueMapper: (d, _) => d.nombre,
                                yValueMapper: (d, _) => d.enCurso,
                                dataLabelMapper: (d, _) =>
                                    d.enCurso == 0 ? null : '${d.enCurso}',
                                dataLabelSettings: const DataLabelSettings(isVisible: true),
                                animationDuration: 650,
                              ),
                            if (!showEnCurso)
                              ColumnSeries<_ReporterStats, String>(
                                name: 'Agendadas',
                                dataSource: stats,
                                xValueMapper: (d, _) => d.nombre,
                                yValueMapper: (d, _) => d.agendadas,
                                dataLabelMapper: (d, _) =>
                                    d.agendadas == 0 ? null : '${d.agendadas}',
                                dataLabelSettings: const DataLabelSettings(isVisible: true),
                                animationDuration: 650,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------- Stats interno (privado) -------------------

class _ReporterStats {
  final int reporteroId;
  final String nombre;

  final int completadas;
  final int atrasadas;
  final int agendadas;

  final int enCurso;

  const _ReporterStats({
    required this.reporteroId,
    required this.nombre,
    required this.completadas,
    required this.atrasadas,
    required this.agendadas,
    required this.enCurso,
  });

  int get scoreBase => completadas + atrasadas + agendadas;

  int get scoreToday => completadas + atrasadas + agendadas + enCurso;

  _ReporterStats copyWith({int? completadas, int? atrasadas, int? agendadas, int? enCurso}) {
    return _ReporterStats(
      reporteroId: reporteroId,
      nombre: nombre,
      completadas: completadas ?? this.completadas,
      atrasadas: atrasadas ?? this.atrasadas,
      agendadas: agendadas ?? this.agendadas,
      enCurso: enCurso ?? this.enCurso,
    );
  }
}
