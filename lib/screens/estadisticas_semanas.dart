import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../models/noticia.dart';
import '../models/reportero_admin.dart';

class EstadisticasSemanas extends StatefulWidget {
  final int year;
  final int month;
  final String monthName;
  final List<ReporteroAdmin> reporteros;
  final List<Noticia> noticias;

  final bool embedded;

  const EstadisticasSemanas({
    super.key,
    required this.year,
    required this.month,
    required this.monthName,
    required this.reporteros,
    required this.noticias,
    this.embedded = false,
  });

  @override
  State<EstadisticasSemanas> createState() => _EstadisticasSemanasState();
}

class _EstadisticasSemanasState extends State<EstadisticasSemanas> {
  late final TooltipBehavior _tooltip;
  late final PageController _page;

  late final List<_WeekRange> _weeks;

  int _index = 0;
  int _animSeed = 0;

  bool get _canPrev => _index > 0;
  bool get _canNext => _index < _weeks.length - 1;

  @override
  void initState() {
    super.initState();
    _tooltip = TooltipBehavior(enable: true);

    _weeks = _buildWeeksForMonth(widget.year, widget.month);

    _index = _indexForDate(DateTime.now());
    _page = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _goPrev() async {
    if (!_canPrev) return;
    await _page.previousPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  Future<void> _goNext() async {
    if (!_canNext) return;
    await _page.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  // ------------------- Semanas dinámicas (Lun–Dom, recortadas al mes) -------------------

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _startOfWeekMonday(DateTime d) {
    final day = _dayOnly(d);
    final diff = day.weekday - DateTime.monday;
    return day.subtract(Duration(days: diff));
  }

  DateTime _monthStart(int year, int month) => DateTime(year, month, 1);

  DateTime _monthEndExclusive(int year, int month) {
    if (month == 12) return DateTime(year + 1, 1, 1);
    return DateTime(year, month + 1, 1);
  }

  List<_WeekRange> _buildWeeksForMonth(int year, int month) {
    final mStart = _monthStart(year, month);
    final mEndEx = _monthEndExclusive(year, month);

    var cursorWeekStart = _startOfWeekMonday(mStart);
    final List<_WeekRange> out = [];

    while (cursorWeekStart.isBefore(mEndEx)) {
      final cursorWeekEndEx = cursorWeekStart.add(const Duration(days: 7));

      final start = cursorWeekStart.isBefore(mStart) ? mStart : cursorWeekStart;
      final endEx = cursorWeekEndEx.isAfter(mEndEx) ? mEndEx : cursorWeekEndEx;

      out.add(_WeekRange(start: start, endExclusive: endEx));
      cursorWeekStart = cursorWeekStart.add(const Duration(days: 7));
    }

    return out;
  }

  int _indexForDate(DateTime d) {
    if (d.year != widget.year || d.month != widget.month) return 0;

    final day = _dayOnly(d);
    for (int i = 0; i < _weeks.length; i++) {
      final w = _weeks[i];
      if (!day.isBefore(w.start) && day.isBefore(w.endExclusive)) return i;
    }
    return 0;
  }

  bool _isCurrentWeek(_WeekRange w) {
    final today = _dayOnly(DateTime.now());
    if (today.year != widget.year || today.month != widget.month) return false;
    return !today.isBefore(w.start) && today.isBefore(w.endExclusive);
  }

  bool _inRange(DateTime? dt, DateTime start, DateTime endExclusive) {
    if (dt == null) return false;
    return !dt.isBefore(start) && dt.isBefore(endExclusive);
  }

  // ------------------- Stats por semana (nueva lógica) -------------------

  List<_ReporterStats> _buildStatsWeek(
    _WeekRange w, {
    required bool includeEnCurso,
  }) {
    final start = w.start;
    final endEx = w.endExclusive;

    final Map<int, _ReporterStats> map = {
      for (final r in widget.reporteros)
        r.id: _ReporterStats(
          reporteroId: r.id,
          nombre: r.nombre,
          completadas: 0,
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
          agendadas: 0,
          enCurso: 0,
        );
      }

      final cur = map[rid]!;

      // ✅ Completadas: por horaLlegada en rango
      final isCompletada = _inRange(n.horaLlegada, start, endEx);

      // ✅ Agendadas: pendiente==true y fechaCita en rango
      final isAgendada = (n.pendiente == true) && _inRange(n.fechaCita, start, endEx);

      // ✅ En curso (solo semana actual): por fechaCita en rango (independiente de estado)
      final isEnCurso = includeEnCurso && _inRange(n.fechaCita, start, endEx);

      map[rid] = _ReporterStats(
        reporteroId: cur.reporteroId,
        nombre: cur.nombre,
        completadas: cur.completadas + (isCompletada ? 1 : 0),
        agendadas: cur.agendadas + (isAgendada ? 1 : 0),
        enCurso: cur.enCurso + (isEnCurso ? 1 : 0),
      );
    }

    final list = map.values.toList();
    list.sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  String _weekTitle(_WeekRange w) {
    final startDay = w.start.day;
    final endDay = w.endInclusive.day;
    return 'Semana del $startDay al $endDay ${widget.monthName} ${widget.year}';
  }

  // ------------------- UI -------------------

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildBody(context, showTopTitle: true);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Semanas • ${widget.monthName} ${widget.year}'),
      ),
      body: _buildBody(context, showTopTitle: false),
    );
  }

  Widget _buildBody(BuildContext context, {required bool showTopTitle}) {
    final theme = Theme.of(context);

    return Column(
      children: [
        const SizedBox(height: 8),

        if (showTopTitle) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.view_week),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Semanas • ${widget.monthName} ${widget.year}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Semana anterior',
                onPressed: _canPrev ? _goPrev : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Column(
                  children: [
                    _dots(theme),
                    const SizedBox(height: 6),
                    Text(
                      '${_index + 1} / ${_weeks.length}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface.withOpacity(0.75),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Semana siguiente',
                onPressed: _canNext ? _goNext : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        Expanded(
          child: PageView.builder(
            controller: _page,
            itemCount: _weeks.length,
            onPageChanged: (i) {
              setState(() {
                _index = i;
                _animSeed++;
              });
            },
            itemBuilder: (context, i) {
              final w = _weeks[i];
              final isCurrent = _isCurrentWeek(w);

              final stats = _buildStatsWeek(
                w,
                includeEnCurso: isCurrent,
              );

              final totalCompletadas =
                  stats.fold<int>(0, (a, b) => a + b.completadas);
              final totalAgendadas = stats.fold<int>(0, (a, b) => a + b.agendadas);
              final totalEnCurso = stats.fold<int>(0, (a, b) => a + b.enCurso);

              final hasMany = stats.length > 8;

              final chartKey = (i == _index)
                  ? ValueKey('week_${i}_${_animSeed}')
                  : ValueKey('week_${i}_static');

              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _weekTitle(w),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        Row(
                          children: [
                            _pill(theme, 'Agendadas: $totalAgendadas'),
                            const SizedBox(width: 8),
                            _pill(theme, 'Completadas: $totalCompletadas'),
                            if (isCurrent) ...[
                              const SizedBox(width: 8),
                              _pill(theme, 'En curso: $totalEnCurso'),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),

                        Expanded(
                          child: SfCartesianChart(
                            key: chartKey,
                            tooltipBehavior: _tooltip,
                            legend: const Legend(
                              isVisible: true,
                              position: LegendPosition.bottom,
                            ),
                            plotAreaBorderWidth: 0,
                            primaryXAxis: CategoryAxis(
                              labelRotation: hasMany ? 45 : 0,
                              labelIntersectAction: AxisLabelIntersectAction.rotate45,
                              majorGridLines: const MajorGridLines(width: 0),
                            ),
                            primaryYAxis: NumericAxis(
                              minimum: 0,
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
                                dataLabelSettings: const DataLabelSettings(isVisible: true),
                                animationDuration: 650,
                              ),
                              if (isCurrent)
                                ColumnSeries<_ReporterStats, String>(
                                  name: 'En curso',
                                  dataSource: stats,
                                  xValueMapper: (d, _) => d.nombre,
                                  yValueMapper: (d, _) => d.enCurso,
                                  dataLabelSettings:
                                      const DataLabelSettings(isVisible: true),
                                  animationDuration: 650,
                                ),
                              ColumnSeries<_ReporterStats, String>(
                                name: 'Agendadas',
                                dataSource: stats,
                                xValueMapper: (d, _) => d.nombre,
                                yValueMapper: (d, _) => d.agendadas,
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
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _pill(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _dots(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_weeks.length, (i) {
        final active = i == _index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 18 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withOpacity(0.25),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

class _WeekRange {
  final DateTime start;
  final DateTime endExclusive;

  const _WeekRange({required this.start, required this.endExclusive});

  DateTime get endInclusive => endExclusive.subtract(const Duration(days: 1));
}

class _ReporterStats {
  final int reporteroId;
  final String nombre;

  final int completadas;
  final int agendadas;
  final int enCurso; // solo se “usa” (y se muestra) en la semana actual

  const _ReporterStats({
    required this.reporteroId,
    required this.nombre,
    required this.completadas,
    required this.agendadas,
    required this.enCurso,
  });

  int get total => completadas + agendadas + enCurso;
}
