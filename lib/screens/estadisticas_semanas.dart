// lib/screens/estadisticas_semanas.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
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
  late final ZoomPanBehavior _zoom;

  late final List<_WeekRange> _weeks;

  int _index = 0;
  int _animSeed = 0;

  bool get _canPrev => _index > 0;
  bool get _canNext => _index < _weeks.length - 1;

  @override
  void initState() {
    super.initState();
    _tooltip = TooltipBehavior(enable: true);

    _zoom = ZoomPanBehavior(
      enablePanning: kIsWeb,
      enablePinching: kIsWeb,
      zoomMode: ZoomMode.x,
    );

    _weeks = _buildWeeksForMonth(widget.year, widget.month);

    _index = _indexForDate(DateTime.now());
    _page = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  // ------------------- Roles (ocultar admins) -------------------

  bool _isAdmin(ReporteroAdmin? r) {
    final role = (r?.role ?? 'reportero').toLowerCase().trim();
    return role == 'admin';
  }

  bool _isAdminId(int rid, Map<int, ReporteroAdmin> repById) {
    if (rid == 0) return false; // "Sin asignar" sí se muestra
    return _isAdmin(repById[rid]);
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

  // ------------------- ATRASADAS -------------------

  DateTime _aMinuto(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute);

  bool _esAtrasada(Noticia n) {
    final llegada = n.horaLlegada;
    final cita = n.fechaCita;
    if (llegada == null || cita == null) return false;
    return _aMinuto(llegada).isAfter(_aMinuto(cita));
  }

  // ------------------- Stats por semana -------------------

  List<_ReporterStats> _buildStatsWeek(
    _WeekRange w, {
    required bool includeEnCurso,
  }) {
    final start = w.start;
    final endEx = w.endExclusive;

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

      final isCompletada = _inRange(n.horaLlegada, start, endEx);

      final isEnCurso = includeEnCurso &&
          (n.pendiente == true) &&
          (n.horaLlegada == null) &&
          _inRange(n.fechaCita, start, endEx);

      final isAgendada = (n.pendiente == true) &&
          _inRange(n.fechaCita, start, endEx) &&
          !(includeEnCurso && isEnCurso);

      int addCompletada = 0;
      int addAtrasada = 0;

      if (isCompletada) {
        if (_esAtrasada(n)) {
          addAtrasada = 1;
        } else {
          addCompletada = 1;
        }
      }

      map[rid] = _ReporterStats(
        reporteroId: cur.reporteroId,
        nombre: cur.nombre,
        completadas: cur.completadas + addCompletada,
        atrasadas: cur.atrasadas + addAtrasada,
        agendadas: cur.agendadas + (isAgendada ? 1 : 0),
        enCurso: cur.enCurso + (isEnCurso ? 1 : 0),
      );
    }

    final list = map.values.where((s) => s.total > 0).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

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
    final theme = Theme.of(context);

    final body = Container(
      color: kIsWeb ? theme.colorScheme.surface : null,
      child: _wrapWebWidth(_buildBody(context, showTopTitle: widget.embedded)),
    );

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Semanas • ${widget.monthName} ${widget.year}'),
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context, {required bool showTopTitle}) {
    final theme = Theme.of(context);
    final wide = _isWebWide(context);

    final wCur = _weeks[_index];
    final isCurrentCur = _isCurrentWeek(wCur);
    final statsCur = _buildStatsWeek(wCur, includeEnCurso: isCurrentCur);

    final totalCompletadasCur =
        statsCur.fold<int>(0, (a, b) => a + b.completadas);
    final totalAtrasadasCur = statsCur.fold<int>(0, (a, b) => a + b.atrasadas);
    final totalAgendadasCur = statsCur.fold<int>(0, (a, b) => a + b.agendadas);
    final totalEnCursoCur = statsCur.fold<int>(0, (a, b) => a + b.enCurso);

    final totalTareasCur = totalCompletadasCur +
        totalAtrasadasCur +
        (isCurrentCur ? totalEnCursoCur : totalAgendadasCur);

    final topHeader = showTopTitle
        ? Padding(
            padding: EdgeInsets.fromLTRB(_hPad(context), 10, _hPad(context), 8),
            child: _cardShell(
              context,
              elevation: 0.6,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.view_week, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Semanas • ${widget.monthName} ${widget.year}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          )
        : const SizedBox.shrink();

    final nav = Padding(
      padding: EdgeInsets.fromLTRB(_hPad(context), 0, _hPad(context), 10),
      child: _cardShell(
        context,
        elevation: 0.6,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Semana anterior',
              onPressed: _canPrev ? _goPrev : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dots(theme),
                  const SizedBox(height: 6),
                  Text(
                    '${_index + 1} / ${_weeks.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface.withOpacity(0.72),
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
    );

    if (wide) {
      final summary = _cardShell(
        context,
        elevation: 0.8,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _weekTitle(wCur),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isCurrentCur) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: theme.dividerColor.withOpacity(0.55),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      'Actual',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(theme, 'Total: $totalTareasCur', isTotal: true),
                _pill(theme, 'Completadas: $totalCompletadasCur'),
                _pill(theme, 'Atrasadas: $totalAtrasadasCur'),
                isCurrentCur
                    ? _pill(theme, 'En curso: $totalEnCursoCur')
                    : _pill(theme, 'Agendadas: $totalAgendadasCur'),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      );

      final chartPanel = _cardShell(
        context,
        elevation: 0.8,
        padding: const EdgeInsets.all(12),
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

            final stats = _buildStatsWeek(w, includeEnCurso: isCurrent);
            final hasMany = stats.length > 8;

            final chartKey = (i == _index)
                ? ValueKey('week_chart_${i}_${_animSeed}')
                : ValueKey('week_chart_${i}_static');

            if (stats.isEmpty) {
              return Center(
                child: Text(
                  'Sin datos en esta semana.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              );
            }

            return SfCartesianChart(
              key: chartKey,
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
                if (isCurrent)
                  ColumnSeries<_ReporterStats, String>(
                    name: 'En curso',
                    dataSource: stats,
                    xValueMapper: (d, _) => d.nombre,
                    yValueMapper: (d, _) => d.enCurso,
                    dataLabelMapper: (d, _) =>
                        d.enCurso == 0 ? null : '${d.enCurso}',
                    dataLabelSettings: const DataLabelSettings(isVisible: true),
                    animationDuration: 650,
                  )
                else
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
            );
          },
        ),
      );

      return Column(
        children: [
          if (showTopTitle) topHeader,
          nav,
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(_hPad(context), 0, _hPad(context), 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 420, child: summary),
                  const SizedBox(width: 12),
                  Expanded(child: _maybeScrollbar(child: chartPanel)),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (showTopTitle) topHeader,
        nav,
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
              final totalAtrasadas =
                  stats.fold<int>(0, (a, b) => a + b.atrasadas);
              final totalAgendadas =
                  stats.fold<int>(0, (a, b) => a + b.agendadas);
              final totalEnCurso =
                  stats.fold<int>(0, (a, b) => a + b.enCurso);

              final totalTareas = totalCompletadas +
                  totalAtrasadas +
                  (isCurrent ? totalEnCurso : totalAgendadas);

              final hasMany = stats.length > 8;

              final chartKey = (i == _index)
                  ? ValueKey('week_${i}_${_animSeed}')
                  : ValueKey('week_${i}_static');

              return Padding(
                padding: EdgeInsets.fromLTRB(_hPad(context), 0, _hPad(context), 12),
                child: _cardShell(
                  context,
                  elevation: 0.8,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _weekTitle(w),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, c) {
                          final bool narrow = c.maxWidth < 380;
                          final double? maxPillW =
                              narrow ? (c.maxWidth - 8) / 2 : null;

                          final pills = <Widget>[
                            _pill(
                              theme,
                              'Total: $totalTareas',
                              maxWidth: maxPillW,
                              isTotal: true,
                            ),
                            _pill(
                              theme,
                              'Completadas: $totalCompletadas',
                              maxWidth: maxPillW,
                            ),
                            _pill(
                              theme,
                              'Atrasadas: $totalAtrasadas',
                              maxWidth: maxPillW,
                            ),
                            if (isCurrent)
                              _pill(
                                theme,
                                'En curso: $totalEnCurso',
                                maxWidth: maxPillW,
                              )
                            else
                              _pill(
                                theme,
                                'Agendadas: $totalAgendadas',
                                maxWidth: maxPillW,
                              ),
                          ];

                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: pills,
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: stats.isEmpty
                            ? Center(
                                child: Text(
                                  'Sin datos en esta semana.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.7),
                                  ),
                                ),
                              )
                            : SfCartesianChart(
                                key: chartKey,
                                tooltipBehavior: _tooltip,
                                legend: const Legend(
                                  isVisible: true,
                                  position: LegendPosition.bottom,
                                  overflowMode: LegendItemOverflowMode.wrap,
                                ),
                                plotAreaBorderWidth: 0,
                                primaryXAxis: CategoryAxis(
                                  labelRotation: hasMany ? 45 : 0,
                                  labelIntersectAction:
                                      AxisLabelIntersectAction.rotate45,
                                  majorGridLines:
                                      const MajorGridLines(width: 0),
                                ),
                                primaryYAxis: NumericAxis(
                                  minimum: 0,
                                  interval: 1,
                                  numberFormat: NumberFormat('#0'),
                                  majorGridLines: MajorGridLines(
                                    width: 1,
                                    color:
                                        theme.dividerColor.withOpacity(0.30),
                                  ),
                                ),
                                series: [
                                  ColumnSeries<_ReporterStats, String>(
                                    name: 'Completadas',
                                    dataSource: stats,
                                    xValueMapper: (d, _) => d.nombre,
                                    yValueMapper: (d, _) => d.completadas,
                                    dataLabelMapper: (d, _) =>
                                        d.completadas == 0
                                            ? null
                                            : '${d.completadas}',
                                    dataLabelSettings:
                                        const DataLabelSettings(isVisible: true),
                                    animationDuration: 650,
                                  ),
                                  ColumnSeries<_ReporterStats, String>(
                                    name: 'Atrasadas',
                                    dataSource: stats,
                                    xValueMapper: (d, _) => d.nombre,
                                    yValueMapper: (d, _) => d.atrasadas,
                                    dataLabelMapper: (d, _) =>
                                        d.atrasadas == 0
                                            ? null
                                            : '${d.atrasadas}',
                                    dataLabelSettings:
                                        const DataLabelSettings(isVisible: true),
                                    animationDuration: 650,
                                    color: Colors.red.shade900,
                                  ),
                                  if (isCurrent)
                                    ColumnSeries<_ReporterStats, String>(
                                      name: 'En curso',
                                      dataSource: stats,
                                      xValueMapper: (d, _) => d.nombre,
                                      yValueMapper: (d, _) => d.enCurso,
                                      dataLabelMapper: (d, _) =>
                                          d.enCurso == 0 ? null : '${d.enCurso}',
                                      dataLabelSettings:
                                          const DataLabelSettings(isVisible: true),
                                      animationDuration: 650,
                                    )
                                  else
                                    ColumnSeries<_ReporterStats, String>(
                                      name: 'Agendadas',
                                      dataSource: stats,
                                      xValueMapper: (d, _) => d.nombre,
                                      yValueMapper: (d, _) => d.agendadas,
                                      dataLabelMapper: (d, _) =>
                                          d.agendadas == 0 ? null : '${d.agendadas}',
                                      dataLabelSettings:
                                          const DataLabelSettings(isVisible: true),
                                      animationDuration: 650,
                                    ),
                                ],
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

  int get total => completadas + atrasadas + agendadas + enCurso;
}
