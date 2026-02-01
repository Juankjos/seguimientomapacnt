// lib/screens/estadisticas_semanas_realizadas.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

import '../models/noticia.dart';
import '../models/reportero_admin.dart';

// ===================== Helpers desktop/web =====================

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

// ================================================================

class EstadisticasSemanasRealizadas extends StatefulWidget {
  final int year;
  final int month;
  final String monthName;
  final List<ReporteroAdmin> reporteros;
  final List<Noticia> noticias;

  final bool embedded;

  const EstadisticasSemanasRealizadas({
    super.key,
    required this.year,
    required this.month,
    required this.monthName,
    required this.reporteros,
    required this.noticias,
    this.embedded = false,
  });

  @override
  State<EstadisticasSemanasRealizadas> createState() => _EstadisticasSemanasRealizadasState();
}

class _EstadisticasSemanasRealizadasState extends State<EstadisticasSemanasRealizadas> {
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
    if (rid == 0) return false;
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

  bool _inRange(DateTime? dt, DateTime start, DateTime endExclusive) {
    if (dt == null) return false;
    return !dt.isBefore(start) && dt.isBefore(endExclusive);
  }

  // ------------------- Stats por semana (SOLO REALIZADAS) -------------------

  List<_ReporterStats> _buildStatsWeek(_WeekRange w) {
    final start = w.start;
    final endEx = w.endExclusive;

    final repById = {for (final r in widget.reporteros) r.id: r};

    final Map<int, _ReporterStats> map = {
      for (final r in widget.reporteros)
        if (!_isAdmin(r))
          r.id: _ReporterStats(
            reporteroId: r.id,
            nombre: r.nombre,
            realizadas: 0,
          ),
    };

    for (final n in widget.noticias) {
      final rid = n.reporteroId ?? 0;

      if (_isAdminId(rid, repById)) continue;

      // SOLO realizadas => pendiente = 0
      final bool realizada = (n.pendiente == false);

      final bool inWeek = _inRange(n.horaLlegada, start, endEx);

      if (!(realizada && inWeek)) continue;

      if (!map.containsKey(rid)) {
        map[rid] = _ReporterStats(
          reporteroId: rid,
          nombre: rid == 0 ? 'Sin asignar' : 'Reportero #$rid',
          realizadas: 0,
        );
      }

      final cur = map[rid]!;
      map[rid] = _ReporterStats(
        reporteroId: cur.reporteroId,
        nombre: cur.nombre,
        realizadas: cur.realizadas + 1,
      );
    }

    final list = map.values.where((s) => s.realizadas > 0).toList()
      ..sort((a, b) => b.realizadas.compareTo(a.realizadas));

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

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: Text('Semanas • Realizadas • ${widget.monthName} ${widget.year}'),
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context, {required bool showTopTitle}) {
    final theme = Theme.of(context);
    final wide = _isWebWide(context);

    final wCur = _weeks[_index];
    final statsCur = _buildStatsWeek(wCur);
    final totalRealizadasCur = statsCur.fold<int>(0, (a, b) => a + b.realizadas);

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
                      'Semanas • Realizadas • ${widget.monthName} ${widget.year}',
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
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(theme, 'Total realizadas: $totalRealizadasCur', isTotal: true),
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
            final stats = _buildStatsWeek(w);
            final hasMany = stats.length > 8;

            final chartKey = (i == _index)
                ? ValueKey('week_real_${i}_${_animSeed}')
                : ValueKey('week_real_${i}_static');

            if (stats.isEmpty) {
              return Center(
                child: Text(
                  'Sin realizadas en esta semana.',
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
                  name: 'Realizadas',
                  dataSource: stats,
                  xValueMapper: (d, _) => d.nombre,
                  yValueMapper: (d, _) => d.realizadas,
                  dataLabelMapper: (d, _) =>
                      d.realizadas == 0 ? null : '${d.realizadas}',
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

    // Mobile
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
              final stats = _buildStatsWeek(w);

              final totalRealizadas = stats.fold<int>(0, (a, b) => a + b.realizadas);
              final hasMany = stats.length > 8;

              final chartKey = (i == _index)
                  ? ValueKey('week_real_m_${i}_${_animSeed}')
                  : ValueKey('week_real_m_${i}_static');

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
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _pill(theme, 'Total realizadas: $totalRealizadas', isTotal: true),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: stats.isEmpty
                            ? Center(
                                child: Text(
                                  'Sin realizadas en esta semana.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                ),
                              )
                            : SfCartesianChart(
                                key: chartKey,
                                tooltipBehavior: _tooltip,
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
                                    name: 'Realizadas',
                                    dataSource: stats,
                                    xValueMapper: (d, _) => d.nombre,
                                    yValueMapper: (d, _) => d.realizadas,
                                    dataLabelMapper: (d, _) =>
                                        d.realizadas == 0 ? null : '${d.realizadas}',
                                    dataLabelSettings: const DataLabelSettings(isVisible: true),
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
    bool isTotal = false,
  }) {
    final bg = isTotal ? theme.colorScheme.primary : theme.colorScheme.primaryContainer;
    final fg = isTotal ? theme.colorScheme.onPrimary : theme.colorScheme.onPrimaryContainer;

    return Container(
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
  final int realizadas;

  const _ReporterStats({
    required this.reporteroId,
    required this.nombre,
    required this.realizadas,
  });
}
