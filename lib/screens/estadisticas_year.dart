// lib/screens/estadisticas_year.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

import '../models/noticia.dart';
import '../models/reportero_admin.dart';
import 'estadisticas_semanas.dart';
import 'estadisticas_dias.dart';

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

// ===============================================================

class EstadisticasYear extends StatefulWidget {
  final List<ReporteroAdmin> reporteros;
  final List<Noticia> noticias;

  const EstadisticasYear({
    super.key,
    required this.reporteros,
    required this.noticias,
  });

  @override
  State<EstadisticasYear> createState() => _EstadisticasYearState();
}

class _EstadisticasYearState extends State<EstadisticasYear> {
  int? _selectedYear;
  int _animSeed = 0;

  late final TooltipBehavior _tooltip;
  late final ZoomPanBehavior _zoom;
  late final List<int> _years;

  @override
  void initState() {
    super.initState();
    _tooltip = TooltipBehavior(enable: true);
    _zoom = ZoomPanBehavior(
      enablePanning: kIsWeb,
      enablePinching: kIsWeb,
      zoomMode: ZoomMode.x,
    );
    _years = _buildYearsList();
  }

  // ------------------- Roles (ocultar admins en la gráfica) -------------------

  bool _isAdmin(ReporteroAdmin? r) {
    final role = (r?.role ?? 'reportero').toLowerCase().trim();
    return role == 'admin';
  }

  bool _isAdminId(int rid, Map<int, ReporteroAdmin> repById) {
    if (rid == 0) return false;
    final r = repById[rid];
    if (r == null) return false;
    return _isAdmin(r);
  }

  // ------------------- Helpers -------------------

  ({DateTime start, DateTime end}) _yearBounds(int year) {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year + 1, 1, 1);
    return (start: start, end: end);
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
    return _aMinuto(llegada).isAfter(_aMinuto(cita));
  }

  bool _isCurrentYear(int year) => year == DateTime.now().year;

  List<int> _buildYearsList() {
    final nowYear = DateTime.now().year;
    final Set<int> years = {};

    for (final n in widget.noticias) {
      final y1 = n.horaLlegada?.year;
      final y2 = n.fechaCita?.year;
      if (y1 != null) years.add(y1);
      if (y2 != null) years.add(y2);
    }

    years.add(nowYear);

    final past = years.where((y) => y < nowYear).toList()..sort((a, b) => b.compareTo(a));
    final future = years.where((y) => y > nowYear).toList()..sort();

    return [nowYear, ...past, ...future];
  }

  int _countNoticiasEnYear(int year) {
    final b = _yearBounds(year);
    int c = 0;

    for (final n in widget.noticias) {
      final hasCompletada = _inRange(n.horaLlegada, b.start, b.end);
      final hasFechaCita = _inRange(n.fechaCita, b.start, b.end);
      if (hasCompletada || hasFechaCita) c++;
    }

    return c;
  }

  List<_ReporterStats> _buildStatsForYear(int year, {required bool includeEnCurso}) {
    final b = _yearBounds(year);

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

      map.putIfAbsent(
        rid,
        () => _ReporterStats(
          reporteroId: rid,
          nombre: rid == 0 ? 'Sin asignar' : 'Reportero #$rid',
          completadas: 0,
          atrasadas: 0,
          agendadas: 0,
          enCurso: 0,
        ),
      );

      final cur = map[rid]!;

      final isCompletada = _inRange(n.horaLlegada, b.start, b.end);

      final isEnCurso = includeEnCurso &&
          (n.pendiente == true) &&
          (n.horaLlegada == null) &&
          _inRange(n.fechaCita, b.start, b.end);

      final isAgendada = (n.pendiente == true) &&
          _inRange(n.fechaCita, b.start, b.end) &&
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

      map[rid] = cur.copyWith(
        completadas: cur.completadas + addCompletada,
        atrasadas: cur.atrasadas + addAtrasada,
        agendadas: cur.agendadas + (isAgendada ? 1 : 0),
        enCurso: cur.enCurso + (isEnCurso ? 1 : 0),
      );
    }

    final list = map.values.toList();
    list.sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  Future<void> _openMesesForYear(int year) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _YearMonthsPage(
          year: year,
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
    final wide = _isWebWide(context);

    final body = Container(
      color: kIsWeb ? theme.colorScheme.surface : null,
      child: _wrapWebWidth(
        wide ? _buildWideLayout() : _buildNarrowLayout(),
      ),
    );

    return body;
  }

  // ======= WIDE: selector (izq) + detalle/gráfica (der) =======
  Widget _buildWideLayout() {
    final pad = _hPad(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 12, pad, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 5, child: _buildYearsPanelWide()),
          const SizedBox(width: 12),
          Expanded(flex: 7, child: _buildDetailsPanelWide()),
        ],
      ),
    );
  }

  Widget _buildYearsPanelWide() {
    final theme = Theme.of(context);

    return _cardShell(
      context,
      elevation: 0.8,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.dividerColor.withOpacity(0.55),
                width: 0.8,
              ),
            ),
            child: Text(
              'Años',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                int crossAxisCount = 2;
                double aspect = 2.25;

                if (w >= 560) {
                  crossAxisCount = 3;
                  aspect = 2.35;
                }
                if (w >= 760) {
                  crossAxisCount = 4;
                  aspect = 2.50;
                }

                final grid = GridView.builder(
                  padding: const EdgeInsets.only(bottom: 6),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: aspect,
                  ),
                  itemCount: _years.length,
                  itemBuilder: (context, index) {
                    final year = _years[index];
                    return _buildYearTile(year);
                  },
                );

                return _maybeScrollbar(child: grid);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsPanelWide() {
    final theme = Theme.of(context);

    if (_selectedYear == null) {
      return _cardShell(
        context,
        elevation: 0.8,
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Selecciona un año para ver la gráfica.',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface.withOpacity(0.75),
            ),
          ),
        ),
      );
    }

    return _buildYearChart(year: _selectedYear!, wide: true);
  }

  // ======= NARROW: AnimatedSwitcher =======
  Widget _buildNarrowLayout() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _selectedYear == null
          ? _buildYearsSelectorNarrow(key: const ValueKey('years'))
          : _buildYearChart(
              year: _selectedYear!,
              wide: false,
              key: ValueKey('chart_${_selectedYear!}_$_animSeed'),
            ),
    );
  }

  Widget _buildYearsSelectorNarrow({required Key key}) {
    final theme = Theme.of(context);

    return Padding(
      key: key,
      padding: EdgeInsets.fromLTRB(_hPad(context), 12, _hPad(context), 12),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.dividerColor.withOpacity(0.55),
                width: 0.8,
              ),
            ),
            child: Text(
              'Años',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                int crossAxisCount = 2;
                double aspect = 2.2;

                if (kIsWeb) {
                  if (w >= 1200) {
                    crossAxisCount = 4;
                    aspect = 2.5;
                  } else if (w >= 980) {
                    crossAxisCount = 3;
                    aspect = 2.4;
                  }
                }

                final grid = GridView.builder(
                  padding: const EdgeInsets.only(bottom: 6),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: aspect,
                  ),
                  itemCount: _years.length,
                  itemBuilder: (context, index) {
                    final year = _years[index];
                    return _buildYearTile(year);
                  },
                );

                return _maybeScrollbar(child: grid);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearTile(int year) {
    final theme = Theme.of(context);

    final isCurrent = _isCurrentYear(year);
    final count = _countNoticiasEnYear(year);
    final tiene = count > 0;

    final selected = _selectedYear == year;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        setState(() {
          _selectedYear = year;
          _animSeed++;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? theme.colorScheme.primaryContainer
              : (tiene
                  ? theme.colorScheme.primaryContainer.withOpacity(0.82)
                  : theme.colorScheme.surface),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : (isCurrent ? theme.colorScheme.primary : theme.dividerColor),
            width: selected ? 2.0 : (isCurrent ? 1.6 : 0.9),
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: selected ? 7 : 4,
              offset: const Offset(0, 2),
              color: Colors.black.withOpacity(selected ? 0.14 : 0.08),
            ),
          ],
        ),
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor:
                  isCurrent ? theme.colorScheme.primary : theme.colorScheme.secondary,
              child: const Icon(Icons.event, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$year${isCurrent ? ' (Actual)' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tiene ? '$count noticias' : 'Sin noticias',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: tiene
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget _buildYearChart({
    required int year,
    bool wide = false,
    Key? key,
  }) {
    final theme = Theme.of(context);

    final isCurrent = _isCurrentYear(year);
    final stats = _buildStatsForYear(year, includeEnCurso: isCurrent);

    final totalCompletadas = stats.fold<int>(0, (a, b) => a + b.completadas);
    final totalAtrasadas = stats.fold<int>(0, (a, b) => a + b.atrasadas);
    final totalAgendadas = stats.fold<int>(0, (a, b) => a + b.agendadas);
    final totalEnCurso = stats.fold<int>(0, (a, b) => a + b.enCurso);
    final totalTareas =
        totalCompletadas + totalAtrasadas + (isCurrent ? totalEnCurso : totalAgendadas);

    final hasMany = stats.length > 8;

    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.arrow_back),
          label: const Text('Años'),
          onPressed: () => setState(() => _selectedYear = null),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_view_month),
          label: const Text('Meses'),
          onPressed: () => _openMesesForYear(year),
        ),
      ],
    );

    final pills = LayoutBuilder(
      builder: (context, c) {
        final bool narrow = c.maxWidth < 380;
        final double? maxPillW = narrow ? (c.maxWidth - 8) / 2 : null;

        final list = <Widget>[
          _pill(theme, 'Total: $totalTareas', maxWidth: maxPillW, isTotal: true),
          _pill(theme, 'Completadas: $totalCompletadas', maxWidth: maxPillW),
          _pill(theme, 'Atrasadas: $totalAtrasadas', maxWidth: maxPillW),
          if (isCurrent)
            _pill(theme, 'En curso: $totalEnCurso', maxWidth: maxPillW)
          else
            _pill(theme, 'Agendadas: $totalAgendadas', maxWidth: maxPillW),
        ];

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: list,
        );
      },
    );

    final chart = stats.isEmpty
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
            key: key ?? ValueKey('year_${year}_$_animSeed'),
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
              if (isCurrent)
                ColumnSeries<_ReporterStats, String>(
                  name: 'En curso',
                  dataSource: stats,
                  xValueMapper: (d, _) => d.nombre,
                  yValueMapper: (d, _) => d.enCurso,
                  dataLabelMapper: (d, _) => d.enCurso == 0 ? null : '${d.enCurso}',
                  dataLabelSettings: const DataLabelSettings(isVisible: true),
                  animationDuration: 650,
                )
              else
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
          );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        actions,
        const SizedBox(height: 10),
        Text(
          'Año $year',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 10),
        pills,
        const SizedBox(height: 10),
        Expanded(child: chart),
      ],
    );

    if (wide) {
      return _cardShell(
        context,
        elevation: 0.8,
        padding: const EdgeInsets.all(12),
        child: content,
      );
    }

    return Padding(
      key: key,
      padding: EdgeInsets.fromLTRB(_hPad(context), 12, _hPad(context), 12),
      child: _cardShell(
        context,
        elevation: 0.8,
        padding: const EdgeInsets.all(12),
        child: content,
      ),
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
}

// ======================= Meses por Año (detalle) =======================

class _YearMonthsPage extends StatefulWidget {
  final int year;
  final List<ReporteroAdmin> reporteros;
  final List<Noticia> noticias;

  const _YearMonthsPage({
    required this.year,
    required this.reporteros,
    required this.noticias,
  });

  @override
  State<_YearMonthsPage> createState() => _YearMonthsPageState();
}

class _YearMonthsPageState extends State<_YearMonthsPage> {
  int? _selectedMonth;
  int _animSeed = 0;

  late final TooltipBehavior _tooltip;
  late final ZoomPanBehavior _zoom;

  @override
  void initState() {
    super.initState();
    _tooltip = TooltipBehavior(enable: true);
    _zoom = ZoomPanBehavior(
      enablePanning: kIsWeb,
      enablePinching: kIsWeb,
      zoomMode: ZoomMode.x,
    );
  }

  // ------------------- Roles -------------------

  bool _isAdmin(ReporteroAdmin? r) {
    final role = (r?.role ?? 'reportero').toLowerCase().trim();
    return role == 'admin';
  }

  bool _isAdminId(int rid, Map<int, ReporteroAdmin> repById) {
    if (rid == 0) return false;
    final r = repById[rid];
    if (r == null) return false;
    return _isAdmin(r);
  }

  // ------------------- Helpers mes -------------------

  ({DateTime start, DateTime end}) _monthBounds(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = (month == 12) ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    return (start: start, end: end);
  }

  bool _inRange(DateTime? dt, DateTime start, DateTime endExclusive) {
    if (dt == null) return false;
    return !dt.isBefore(start) && dt.isBefore(endExclusive);
  }

  bool _isCurrentMonth(int year, int month) {
    final now = DateTime.now();
    return now.year == year && now.month == month;
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

  int _countNoticiasEnMes(int year, int month) {
    final b = _monthBounds(year, month);
    int c = 0;

    for (final n in widget.noticias) {
      final hasCompletada = _inRange(n.horaLlegada, b.start, b.end);
      final hasFechaCita = _inRange(n.fechaCita, b.start, b.end);
      if (hasCompletada || hasFechaCita) c++;
    }

    return c;
  }

  List<_ReporterStats> _buildStatsForMonth(
    int year,
    int month, {
    required bool includeEnCurso,
  }) {
    final b = _monthBounds(year, month);
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

      map.putIfAbsent(
        rid,
        () => _ReporterStats(
          reporteroId: rid,
          nombre: rid == 0 ? 'Sin asignar' : 'Reportero #$rid',
          completadas: 0,
          atrasadas: 0,
          agendadas: 0,
          enCurso: 0,
        ),
      );

      final cur = map[rid]!;

      final isCompletada = _inRange(n.horaLlegada, b.start, b.end);

      final isEnCurso = includeEnCurso &&
          (n.pendiente == true) &&
          (n.horaLlegada == null) &&
          _inRange(n.fechaCita, b.start, b.end);

      final isAgendada = (n.pendiente == true) &&
          _inRange(n.fechaCita, b.start, b.end) &&
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

      map[rid] = cur.copyWith(
        completadas: cur.completadas + addCompletada,
        atrasadas: cur.atrasadas + addAtrasada,
        agendadas: cur.agendadas + (isAgendada ? 1 : 0),
        enCurso: cur.enCurso + (isEnCurso ? 1 : 0),
      );
    }

    final list = map.values.toList()..sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  Future<void> _openSemanas(int month) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EstadisticasSemanas(
          year: widget.year,
          month: month,
          monthName: _nombreMes(month),
          reporteros: widget.reporteros,
          noticias: widget.noticias,
        ),
      ),
    );
  }

  Future<void> _openDias(int month) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EstadisticasDias(
          year: widget.year,
          month: month,
          monthName: _nombreMes(month),
          reporteros: widget.reporteros,
          noticias: widget.noticias,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = _isWebWide(context);

    final body = Container(
      color: kIsWeb ? theme.colorScheme.surface : null,
      child: _wrapWebWidth(
        wide ? _buildWideLayout() : _buildNarrowLayout(),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Meses • ${widget.year}'),
        actions: [
          IconButton(
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildWideLayout() {
    final pad = _hPad(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 12, pad, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 5, child: _buildMonthsPanelWide()),
          const SizedBox(width: 12),
          Expanded(flex: 7, child: _buildDetailsPanelWide()),
        ],
      ),
    );
  }

  Widget _buildMonthsPanelWide() {
    final theme = Theme.of(context);

    return _cardShell(
      context,
      elevation: 0.8,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.dividerColor.withOpacity(0.55),
                width: 0.8,
              ),
            ),
            child: Text(
              '${widget.year}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                int cross = 3;
                double aspect = 1.05;

                if (w >= 560) {
                  cross = 4;
                  aspect = 1.15;
                }
                if (w >= 760) {
                  cross = 5;
                  aspect = 1.20;
                }

                final grid = GridView.builder(
                  padding: const EdgeInsets.only(bottom: 6),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cross,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: aspect,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, i) => _buildMonthTile(i + 1),
                );

                return _maybeScrollbar(child: grid);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsPanelWide() {
    final theme = Theme.of(context);

    if (_selectedMonth == null) {
      return _cardShell(
        context,
        elevation: 0.8,
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Selecciona un mes para ver la gráfica.',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface.withOpacity(0.75),
            ),
          ),
        ),
      );
    }

    return _buildChartMes(month: _selectedMonth!, wide: true);
  }

  Widget _buildNarrowLayout() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _selectedMonth == null
          ? _buildGridMesesNarrow(key: const ValueKey('grid'))
          : _buildChartMes(
              month: _selectedMonth!,
              wide: false,
              key: ValueKey('chart_${_selectedMonth!}_$_animSeed'),
            ),
    );
  }

  Widget _buildGridMesesNarrow({required Key key}) {
    final theme = Theme.of(context);

    return Padding(
      key: key,
      padding: EdgeInsets.fromLTRB(_hPad(context), 12, _hPad(context), 12),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.dividerColor.withOpacity(0.55),
                width: 0.8,
              ),
            ),
            child: Text(
              '${widget.year}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _maybeScrollbar(
              child: GridView.builder(
                padding: const EdgeInsets.only(bottom: 6),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.05,
                ),
                itemCount: 12,
                itemBuilder: (context, i) => _buildMonthTile(i + 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthTile(int month) {
    final theme = Theme.of(context);

    final nombreMes = _nombreMes(month);
    final count = _countNoticiasEnMes(widget.year, month);
    final tiene = count > 0;
    final selected = _selectedMonth == month;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() {
        _selectedMonth = month;
        _animSeed++;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? theme.colorScheme.primaryContainer
              : (tiene
                  ? theme.colorScheme.primaryContainer.withOpacity(0.82)
                  : theme.colorScheme.surface),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : (tiene ? theme.colorScheme.primary : theme.dividerColor),
            width: selected ? 2.0 : (tiene ? 1.2 : 0.8),
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: selected ? 7 : 4,
              offset: const Offset(0, 2),
              color: Colors.black.withOpacity(selected ? 0.14 : 0.08),
            ),
          ],
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primary,
              child: const Icon(Icons.calendar_month, size: 18, color: Colors.white),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                nombreMes,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
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
                tiene ? '$count noticias' : 'Sin noticias',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: tiene
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.70),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartMes({
    required int month,
    bool wide = false,
    Key? key,
  }) {
    final theme = Theme.of(context);

    final isCurrent = _isCurrentMonth(widget.year, month);

    final stats = _buildStatsForMonth(
      widget.year,
      month,
      includeEnCurso: isCurrent,
    );

    final totalCompletadas = stats.fold<int>(0, (a, b) => a + b.completadas);
    final totalAtrasadas = stats.fold<int>(0, (a, b) => a + b.atrasadas);
    final totalAgendadas = stats.fold<int>(0, (a, b) => a + b.agendadas);
    final totalEnCurso = stats.fold<int>(0, (a, b) => a + b.enCurso);
    final totalTareas =
        totalCompletadas + totalAtrasadas + (isCurrent ? totalEnCurso : totalAgendadas);

    final hasMany = stats.length > 8;

    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.arrow_back),
          label: const Text('Meses'),
          onPressed: () => setState(() => _selectedMonth = null),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.view_week),
          label: const Text('Semanas'),
          onPressed: () => _openSemanas(month),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_month),
          label: const Text('Días'),
          onPressed: () => _openDias(month),
        ),
      ],
    );

    final pills = LayoutBuilder(
      builder: (context, c) {
        final bool narrow = c.maxWidth < 380;
        final double? maxPillW = narrow ? (c.maxWidth - 8) / 2 : null;

        final list = <Widget>[
          _pill(theme, 'Total: $totalTareas', maxWidth: maxPillW, isTotal: true),
          _pill(theme, 'Completadas: $totalCompletadas', maxWidth: maxPillW),
          _pill(theme, 'Atrasadas: $totalAtrasadas', maxWidth: maxPillW),
          if (isCurrent)
            _pill(theme, 'En curso: $totalEnCurso', maxWidth: maxPillW)
          else
            _pill(theme, 'Agendadas: $totalAgendadas', maxWidth: maxPillW),
        ];

        return Wrap(spacing: 8, runSpacing: 8, children: list);
      },
    );

    final chart = stats.isEmpty
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
            key: key ?? ValueKey('ym_${widget.year}_${month}_$_animSeed'),
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
              if (isCurrent)
                ColumnSeries<_ReporterStats, String>(
                  name: 'En curso',
                  dataSource: stats,
                  xValueMapper: (d, _) => d.nombre,
                  yValueMapper: (d, _) => d.enCurso,
                  dataLabelMapper: (d, _) => d.enCurso == 0 ? null : '${d.enCurso}',
                  dataLabelSettings: const DataLabelSettings(isVisible: true),
                  animationDuration: 650,
                )
              else
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
          );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        actions,
        const SizedBox(height: 10),
        Text(
          '${_nombreMes(month)} ${widget.year}',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 10),
        pills,
        const SizedBox(height: 10),
        Expanded(child: chart),
      ],
    );

    if (wide) {
      return _cardShell(context, elevation: 0.8, padding: const EdgeInsets.all(12), child: content);
    }

    return Padding(
      key: key,
      padding: EdgeInsets.fromLTRB(_hPad(context), 12, _hPad(context), 12),
      child: _cardShell(context, elevation: 0.8, padding: const EdgeInsets.all(12), child: content),
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

  String _nombreMes(int month) {
    const nombres = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
    ];
    return nombres[month - 1];
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

  int get total => completadas + atrasadas + agendadas + enCurso;

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
