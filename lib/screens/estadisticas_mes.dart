// lib/screens/estadisticas_mes.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

import '../models/noticia.dart';
import '../models/reportero_admin.dart';
import 'estadisticas_semanas.dart';
import 'estadisticas_dias.dart';

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

class EstadisticasMes extends StatefulWidget {
  final List<ReporteroAdmin> reporteros;
  final List<Noticia> noticias;

  const EstadisticasMes({
    super.key,
    required this.reporteros,
    required this.noticias,
  });

  @override
  State<EstadisticasMes> createState() => _EstadisticasMesState();
}

class _EstadisticasMesState extends State<EstadisticasMes> {
  final int _year = DateTime.now().year;

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

  // ------------------- Roles (ocultar admins en la gráfica) -------------------

  bool _isAdmin(ReporteroAdmin? r) {
    final role = (r?.role ?? 'reportero').toLowerCase().trim();
    return role == 'admin';
  }

  bool _isAdminId(int rid, Map<int, ReporteroAdmin> repById) {
    if (rid == 0) return false; // "Sin asignar" sí se muestra
    return _isAdmin(repById[rid]);
  }

  // ------------------- Helpers rango de mes -------------------

  ({DateTime start, DateTime end}) _monthBounds(int year, int month) {
    final start = DateTime(year, month, 1);
    final end =
        (month == 12) ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    return (start: start, end: end);
  }

  bool _inRange(DateTime? dt, DateTime start, DateTime end) {
    if (dt == null) return false;
    return !dt.isBefore(start) && dt.isBefore(end);
  }

  bool _isCurrentMonth(int month) {
    final now = DateTime.now();
    return now.year == _year && now.month == month;
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

  // ------------------- Stats internos -------------------

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

      map[rid] = _ReporterStats(
        reporteroId: cur.reporteroId,
        nombre: cur.nombre,
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

  Widget _buildWideLayout() {
    final pad = _hPad(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 12, pad, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: _buildMonthsPanelWide(),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 7,
            child: _buildDetailsPanelWide(),
          ),
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
              '$_year',
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

                int crossAxisCount = 3;
                double aspect = 0.95;

                if (w >= 560) {
                  crossAxisCount = 4;
                  aspect = 1.10;
                }
                if (w >= 720) {
                  crossAxisCount = 5;
                  aspect = 1.18;
                }

                final grid = GridView.builder(
                  padding: const EdgeInsets.only(bottom: 6),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: aspect,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, index) {
                    final month = index + 1;
                    return _buildMonthTile(month);
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
              '$_year',
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
                  padding: const EdgeInsets.only(bottom: 6),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: aspect,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, index) {
                    final month = index + 1;
                    return _buildMonthTile(month);
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

  Widget _buildMonthTile(int month) {
    final theme = Theme.of(context);

    final nombreMes = _nombreMes(month);
    final efem = _efemerideMes(month, theme);
    final count = _countNoticiasEnMes(_year, month);
    final tiene = count > 0;

    final bool selected = _selectedMonth == month;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        setState(() {
          _selectedMonth = month;
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
                  ? theme.colorScheme.primaryContainer.withOpacity(0.80)
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
              color: Colors.black.withOpacity(selected ? 0.14 : 0.07),
            ),
          ],
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Tooltip(
              message: efem.tooltip,
              child: CircleAvatar(
                radius: 16,
                backgroundColor: efem.color,
                child: Icon(efem.icon, size: 18, color: Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                nombreMes,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
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

    final isCurrent = _isCurrentMonth(month);

    final stats = _buildStatsForMonth(
      _year,
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

    // Acciones
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.arrow_back),
          label: const Text('Año'),
          onPressed: () {
            setState(() {
              _selectedMonth = null;
            });
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.view_week),
          label: const Text('Semanas'),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EstadisticasSemanas(
                  year: _year,
                  month: month,
                  monthName: _nombreMes(month),
                  reporteros: widget.reporteros,
                  noticias: widget.noticias,
                ),
              ),
            );
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_month),
          label: const Text('Días'),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EstadisticasDias(
                  year: _year,
                  month: month,
                  monthName: _nombreMes(month),
                  reporteros: widget.reporteros,
                  noticias: widget.noticias,
                ),
              ),
            );
          },
        ),
      ],
    );

    final pills = LayoutBuilder(
      builder: (context, c) {
        final bool narrow = c.maxWidth < 380;
        final double? maxPillW = narrow ? (c.maxWidth - 8) / 2 : null;

        final list = <Widget>[
          _pill('Total: $totalTareas', maxWidth: maxPillW, isTotal: true),
          _pill('Completadas: $totalCompletadas', maxWidth: maxPillW),
          _pill('Atrasadas: $totalAtrasadas', maxWidth: maxPillW),
          if (isCurrent)
            _pill('En curso: $totalEnCurso', maxWidth: maxPillW)
          else
            _pill('Agendadas: $totalAgendadas', maxWidth: maxPillW),
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
            key: key ?? ValueKey('month_${month}_$_animSeed'),
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

    if (wide) {
      return _cardShell(
        context,
        elevation: 0.8,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            actions,
            const SizedBox(height: 10),
            Text(
              '${_nombreMes(month)} $_year',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            pills,
            const SizedBox(height: 10),
            Expanded(child: chart),
          ],
        ),
      );
    }

    return Padding(
      key: key,
      padding: EdgeInsets.fromLTRB(_hPad(context), 12, _hPad(context), 12),
      child: Column(
        children: [
          actions,
          const SizedBox(height: 10),
          Expanded(
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
                          '${_nombreMes(month)} $_year',
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
                  pills,
                  const SizedBox(height: 10),
                  Expanded(child: chart),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, {double? maxWidth, bool isTotal = false}) {
    final theme = Theme.of(context);

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

// ------------------- MESES -------------------

class _MesEfemeride {
  final IconData icon;
  final Color color;
  final String tooltip;
  const _MesEfemeride({
    required this.icon,
    required this.color,
    required this.tooltip,
  });
}

_MesEfemeride _efemerideMes(int month, ThemeData theme) {
  switch (month) {
    case 1:
      return const _MesEfemeride(
        icon: Icons.celebration,
        color: Color(0xFFF94144),
        tooltip: 'Año Nuevo',
      );
    case 2:
      return const _MesEfemeride(
        icon: Icons.favorite,
        color: Color(0xFFF3722C),
        tooltip: 'Día del Amor y la Amistad',
      );
    case 3:
      return const _MesEfemeride(
        icon: Icons.emoji_nature,
        color: Color(0xFFF8961E),
        tooltip: 'Primavera',
      );
    case 4:
      return const _MesEfemeride(
        icon: Icons.face_outlined,
        color: Color(0xFFF9844A),
        tooltip: 'Día del Niño',
      );
    case 5:
      return const _MesEfemeride(
        icon: Icons.face_2_rounded,
        color: Color(0xFFF9C74F),
        tooltip: 'Día de las Madres',
      );
    case 6:
      return const _MesEfemeride(
        icon: Icons.wb_sunny,
        color: Color(0xFF90BE6D),
        tooltip: 'Verano',
      );
    case 7:
      return const _MesEfemeride(
        icon: Icons.beach_access,
        color: Color(0xFF43AA8B),
        tooltip: 'Vacaciones de verano',
      );
    case 8:
      return const _MesEfemeride(
        icon: Icons.school,
        color: Color(0xFF4D908E),
        tooltip: 'Regreso a clases',
      );
    case 9:
      return const _MesEfemeride(
        icon: Icons.flag,
        color: Color(0xFF577590),
        tooltip: 'Independencia de México',
      );
    case 10:
      return const _MesEfemeride(
        icon: Icons.nights_stay,
        color: Color(0xFF277DA1),
        tooltip: 'Día de Muertos',
      );
    case 11:
      return const _MesEfemeride(
        icon: Icons.local_florist,
        color: Color(0xFF4D908E),
        tooltip: 'Día de Muertos / Revolución',
      );
    case 12:
      return const _MesEfemeride(
        icon: Icons.ice_skating_outlined,
        color: Color(0xFFF94144),
        tooltip: 'Navidad',
      );
    default:
      return _MesEfemeride(
        icon: Icons.event,
        color: theme.colorScheme.primary,
        tooltip: 'Mes',
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

  int get total => completadas + atrasadas + agendadas + enCurso;
}
