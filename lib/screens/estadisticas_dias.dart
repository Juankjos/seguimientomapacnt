// lib/screens/estadisticas_dias.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

import '../models/noticia.dart';
import '../models/reportero_admin.dart';

// ===================== Helpers desktop/web (reutilizables en este archivo) =====================

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

ShapeBorder _softShape(ThemeData theme) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: theme.dividerColor.withOpacity(0.70),
        width: 0.9,
      ),
    );

Widget _cardShell(
  BuildContext context, {
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.all(12),
  double? elevation,
  Color? color,
}) {
  final theme = Theme.of(context);
  return Card(
    elevation: elevation ?? (kIsWeb ? 0.7 : 1),
    color: color ?? theme.colorScheme.surface,
    shape: _softShape(theme),
    child: Padding(padding: padding, child: child),
  );
}

Widget _maybeScrollbar({required Widget child}) {
  if (!kIsWeb) return child;
  return Scrollbar(thumbVisibility: true, interactive: true, child: child);
}

// ================================================================================================

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

  // Solo para un “hint” en escritorio (sin cambiar lógica)
  ({int completadas, int agendadas}) _resumenBasicoDia(DateTime day) {
    final b = _dayBounds(day);
    int completadas = 0;
    int agendadas = 0;

    for (final n in widget.noticias) {
      final bool esCompletada = _inRange(n.horaLlegada, b.start, b.endExclusive);
      final bool esAgendada =
          (n.pendiente == true) && _inRange(n.fechaCita, b.start, b.endExclusive);

      if (esCompletada) completadas++;
      if (esAgendada) agendadas++;
    }

    return (completadas: completadas, agendadas: agendadas);
  }

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

  // ------------------- UI: calendario con divisiones sutiles -------------------

  Widget _dayCellShell({
    required ThemeData theme,
    required DateTime day,
    required Widget child,
  }) {
    // “Divisiones casi imperceptibles”
    return Container(
      margin: EdgeInsets.all(_isWebWide(context) ? 2.0 : 1.6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.16),
          width: 0.7,
        ),
      ),
      child: child,
    );
  }

  Widget _defaultDayBuilder(BuildContext context, DateTime day, DateTime focusedDay) {
    final theme = Theme.of(context);
    final isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

    final textStyle = TextStyle(
      fontWeight: FontWeight.w700,
      color: isWeekend
          ? theme.colorScheme.error.withOpacity(0.90)
          : theme.colorScheme.onSurface.withOpacity(0.88),
    );

    return _dayCellShell(
      theme: theme,
      day: day,
      child: Center(child: Text('${day.day}', style: textStyle)),
    );
  }

  Widget _todayBuilder(BuildContext context, DateTime day, DateTime focusedDay) {
    final theme = Theme.of(context);

    return _dayCellShell(
      theme: theme,
      day: day,
      child: Center(
        child: Container(
          width: _isWebWide(context) ? 34 : 30,
          height: _isWebWide(context) ? 34 : 30,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.78),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Text(
            '',
          ),
        ),
      ),
    );
  }

  Widget _selectedBuilder(BuildContext context, DateTime day, DateTime focusedDay) {
    final theme = Theme.of(context);

    return _dayCellShell(
      theme: theme,
      day: day,
      child: Center(
        child: Container(
          width: _isWebWide(context) ? 34 : 30,
          height: _isWebWide(context) ? 34 : 30,
          decoration: BoxDecoration(
            color: theme.colorScheme.secondary,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '${day.day}',
            style: TextStyle(
              color: theme.colorScheme.onSecondary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _todayTextInsideFix(BuildContext context, DateTime day) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        '${day.day}',
        style: TextStyle(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  // ------------------- UI -------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = _isWebWide(context);

    final selected = _selectedDay ?? _focusedDay;
    final resumen = _resumenBasicoDia(selected);

    final calendarCard = _cardShell(
      context,
      elevation: 0.8,
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, c) {
          // Ajuste suave de altura de filas para escritorio
          // header+weekdays aprox:
          final headerAndWeekdays = wide ? 96.0 : 88.0;
          const rows = 6;
          final computedRow = (c.maxHeight - headerAndWeekdays) / rows;
          final rowHeight = computedRow.clamp(34.0, wide ? 56.0 : 48.0);

          return TableCalendar<Noticia>(
            locale: 'es_MX',
            firstDay: _monthStart,
            lastDay: _monthEndExclusive.subtract(const Duration(days: 1)),
            focusedDay: _focusedDay,
            startingDayOfWeek: StartingDayOfWeek.monday,
            calendarFormat: CalendarFormat.month,
            availableCalendarFormats: const {CalendarFormat.month: 'Mes'},
            rowHeight: rowHeight,
            daysOfWeekHeight: wide ? 20 : 18,
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              leftChevronVisible: false,
              rightChevronVisible: false,
              headerPadding: const EdgeInsets.symmetric(vertical: 6),
              titleTextStyle: TextStyle(
                fontSize: wide ? 17 : 16,
                fontWeight: FontWeight.w900,
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
              // dejamos estas, pero en builders controlamos el look (círculos dentro del borde)
              todayDecoration: const BoxDecoration(shape: BoxShape.circle),
              selectedDecoration: const BoxDecoration(shape: BoxShape.circle),
              todayTextStyle: const TextStyle(color: Colors.transparent),
              selectedTextStyle: const TextStyle(color: Colors.transparent),
              weekendTextStyle: TextStyle(color: theme.colorScheme.error),
              markersAlignment: Alignment.bottomRight,
              markersMaxCount: 1,
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: _defaultDayBuilder,
              selectedBuilder: _selectedBuilder,
              todayBuilder: (context, day, focusedDay) {
                // todayBuilder personalizado con borde + círculo, pero conservando número del día
                final base = _todayBuilder(context, day, focusedDay);
                return Stack(
                  children: [
                    base,
                    Positioned.fill(child: _todayTextInsideFix(context, day)),
                  ],
                );
              },
              markerBuilder: (context, day, events) {
                final count = _countNoticiasEnDia(day);
                if (count <= 0) return const SizedBox.shrink();

                return Positioned(
                  bottom: 3,
                  right: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );

    final hintCard = _cardShell(
      context,
      elevation: 0.6,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Toca un día para ver la gráfica.',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.dividerColor.withOpacity(0.55),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Seleccionado: ${selected.day}/${selected.month}/${selected.year}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface.withOpacity(0.86),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Completadas
                Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '${resumen.completadas}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface.withOpacity(0.80),
                  ),
                ),

                const SizedBox(width: 10),

                // Agendadas
                Icon(
                  Icons.event_available_rounded,
                  size: 18,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 4),
                Text(
                  '${resumen.agendadas}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface.withOpacity(0.80),
                  ),
                ),
              ],

            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );

    final content = Padding(
      padding: EdgeInsets.fromLTRB(_hPad(context), 12, _hPad(context), 12),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 7, child: calendarCard),
                const SizedBox(width: 12),
                SizedBox(width: 380, child: hintCard),
              ],
            )
          : Column(
              children: [
                SizedBox(height: 420, child: calendarCard),
                const SizedBox(height: 12),
                hintCard,
              ],
            ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Días • ${widget.monthName} ${widget.year}'),
      ),
      body: Container(
        color: kIsWeb ? theme.colorScheme.surface : null,
        child: _wrapWebWidth(content),
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
  late final ZoomPanBehavior _zoom;
  int _animSeed = 0;

  @override
  void initState() {
    super.initState();
    _tooltip = TooltipBehavior(enable: true);
    _zoom = ZoomPanBehavior(
      enablePanning: kIsWeb,
      enablePinching: kIsWeb,
      zoomMode: ZoomMode.x,
    );
    _animSeed++;
  }

  // ------------------- Roles (ocultar admins en la gráfica) -------------------

  bool _isAdmin(ReporteroAdmin? r) {
    final role = (r?.role ?? 'reportero').toLowerCase().trim();
    return role == 'admin';
  }

  bool _isAdminId(int rid, Map<int, ReporteroAdmin> repById) {
    if (rid == 0) return false;
    return _isAdmin(repById[rid]);
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

    final repById = {for (final r in widget.reporteros) r.id: r};

    final Map<int, _ReporterStats> map = {
      for (final r in widget.reporteros)
        if (!_isAdmin(r))
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

      if (_isAdminId(rid, repById)) continue;

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

      final isEnCurso = showEnCurso &&
          (n.pendiente == true) &&
          (n.horaLlegada == null) &&
          _inRange(n.fechaCita, b.start, b.endExclusive);

      final isAgendada = (n.pendiente == true) &&
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

  Widget _pill(
    ThemeData theme,
    String text, {
    double? maxWidth,
    bool isTotal = false,
  }) {
    final bg = isTotal ? theme.colorScheme.primary : theme.colorScheme.primaryContainer;
    final fg = isTotal ? theme.colorScheme.onPrimary : theme.colorScheme.onPrimaryContainer;

    final core = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.55),
          width: 0.8,
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w800, color: fg),
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
    final wide = _isWebWide(context);

    final bool showEnCurso = _isToday(widget.day);
    final stats = _buildStatsForDay(widget.day);

    final totalCompletadas = stats.fold<int>(0, (a, b) => a + b.completadas);
    final totalAtrasadas = stats.fold<int>(0, (a, b) => a + b.atrasadas);
    final totalAgendadas = stats.fold<int>(0, (a, b) => a + b.agendadas);
    final totalEnCurso = stats.fold<int>(0, (a, b) => a + b.enCurso);

    final totalTareas =
        totalCompletadas + totalAtrasadas + (showEnCurso ? totalEnCurso : totalAgendadas);

    final hasMany = stats.length > 8;

    final resumen = _cardShell(
      context,
      elevation: 0.8,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Resumen',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 380;
              final double? maxPillW = narrow ? (c.maxWidth - 8) / 2 : null;

              final pills = <Widget>[
                _pill(theme, 'Total: $totalTareas', maxWidth: maxPillW, isTotal: true),
                if (!showEnCurso)
                  _pill(theme, 'Agendadas: $totalAgendadas', maxWidth: maxPillW),
                _pill(theme, 'Completadas: $totalCompletadas', maxWidth: maxPillW),
                _pill(theme, 'Atrasadas: $totalAtrasadas', maxWidth: maxPillW),
                if (showEnCurso) _pill(theme, 'En curso: $totalEnCurso', maxWidth: maxPillW),
              ];

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: pills,
              );
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );

    final chart = _cardShell(
      context,
      elevation: 0.8,
      padding: const EdgeInsets.all(12),
      child: stats.isEmpty
          ? Center(
              child: Text(
                'No hay datos para mostrar.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            )
          : SfCartesianChart(
              key: ValueKey('day_chart_${widget.day.toIso8601String()}_$_animSeed'),
              tooltipBehavior: _tooltip,
              zoomPanBehavior: _zoom,
              legend: const Legend(
                isVisible: true,
                position: LegendPosition.bottom,
                overflowMode: LegendItemOverflowMode.wrap,
              ),
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
                  color: theme.dividerColor.withOpacity(0.30),
                ),
              ),
              series: [
                ColumnSeries<_ReporterStats, String>(
                  name: 'Completadas',
                  dataSource: stats,
                  xValueMapper: (d, _) => d.nombre,
                  yValueMapper: (d, _) => d.completadas,
                  dataLabelMapper: (d, _) => d.completadas == 0 ? null : '${d.completadas}',
                  dataLabelSettings: const DataLabelSettings(isVisible: true),
                  animationDuration: 650,
                ),
                ColumnSeries<_ReporterStats, String>(
                  name: 'Atrasadas',
                  dataSource: stats,
                  xValueMapper: (d, _) => d.nombre,
                  yValueMapper: (d, _) => d.atrasadas,
                  dataLabelMapper: (d, _) => d.atrasadas == 0 ? null : '${d.atrasadas}',
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
                    dataLabelMapper: (d, _) => d.enCurso == 0 ? null : '${d.enCurso}',
                    dataLabelSettings: const DataLabelSettings(isVisible: true),
                    animationDuration: 650,
                  ),
                if (!showEnCurso)
                  ColumnSeries<_ReporterStats, String>(
                    name: 'Agendadas',
                    dataSource: stats,
                    xValueMapper: (d, _) => d.nombre,
                    yValueMapper: (d, _) => d.agendadas,
                    dataLabelMapper: (d, _) => d.agendadas == 0 ? null : '${d.agendadas}',
                    dataLabelSettings: const DataLabelSettings(isVisible: true),
                    animationDuration: 650,
                  ),
              ],
            ),
    );

    final body = Padding(
      padding: EdgeInsets.fromLTRB(_hPad(context), 12, _hPad(context), 12),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 420, child: resumen),
                const SizedBox(width: 12),
                Expanded(child: _maybeScrollbar(child: chart)),
              ],
            )
          : Column(
              children: [
                resumen,
                const SizedBox(height: 12),
                Expanded(child: _maybeScrollbar(child: chart)),
              ],
            ),
    );

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
      body: Container(
        color: kIsWeb ? theme.colorScheme.surface : null,
        child: _wrapWebWidth(body),
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

  _ReporterStats copyWith({
    int? completadas,
    int? atrasadas,
    int? agendadas,
    int? enCurso,
  }) {
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
