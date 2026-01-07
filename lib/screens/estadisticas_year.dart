// lib/screens/estadisticas_year.dart
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../models/noticia.dart';
import '../models/reportero_admin.dart';

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
  late final List<int> _years;

  @override
  void initState() {
    super.initState();
    _tooltip = TooltipBehavior(enable: true);
    _years = _buildYearsList();
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

    // Siempre mostrar el año actual primero (aunque no haya registros)
    years.add(nowYear);

    final past = years.where((y) => y < nowYear).toList()..sort((a, b) => b.compareTo(a));
    final future = years.where((y) => y > nowYear).toList()..sort();

    return [nowYear, ...past, ...future];
  }

  int _countNoticiasEnYear(int year) {
    final b = _yearBounds(year);
    int c = 0;

    // Unión sin duplicar por noticia:
    // cuenta si tiene horaLlegada en el año OR fechaCita en el año
    for (final n in widget.noticias) {
      final hasCompletada = _inRange(n.horaLlegada, b.start, b.end);
      final hasFechaCita = _inRange(n.fechaCita, b.start, b.end);
      if (hasCompletada || hasFechaCita) c++;
    }

    return c;
  }

  List<_ReporterStats> _buildStatsForYear(int year, {required bool includeEnCurso}) {
    final b = _yearBounds(year);

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

      map.putIfAbsent(
        rid,
        () => _ReporterStats(
          reporteroId: rid,
          nombre: rid == 0 ? 'Sin asignar' : 'Reportero #$rid',
          completadas: 0,
          agendadas: 0,
          enCurso: 0,
        ),
      );

      final cur = map[rid]!;

      final isCompletada = _inRange(n.horaLlegada, b.start, b.end);
      final isAgendada = (n.pendiente == true) && _inRange(n.fechaCita, b.start, b.end);
      final isEnCurso = includeEnCurso && _inRange(n.fechaCita, b.start, b.end);

      map[rid] = cur.copyWith(
        completadas: cur.completadas + (isCompletada ? 1 : 0),
        agendadas: cur.agendadas + (isAgendada ? 1 : 0),
        enCurso: cur.enCurso + (isEnCurso ? 1 : 0),
      );
    }

    final list = map.values.toList();
    list.sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  // ------------------- UI -------------------

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _selectedYear == null
          ? _buildYearsSelector(key: const ValueKey('years'))
          : _buildYearChart(year: _selectedYear!, key: ValueKey('chart_${_selectedYear!}_$_animSeed')),
    );
  }

  Widget _buildYearsSelector({required Key key}) {
    final theme = Theme.of(context);

    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Años',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 10),

          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.only(bottom: 6),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.2,
              ),
              itemCount: _years.length,
              itemBuilder: (context, index) {
                final year = _years[index];
                final isCurrent = _isCurrentYear(year);
                final count = _countNoticiasEnYear(year);
                final tiene = count > 0;

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
                      color: tiene
                          ? theme.colorScheme.primaryContainer.withOpacity(0.85)
                          : theme.colorScheme.surface,
                      border: Border.all(
                        color: isCurrent ? theme.colorScheme.primary : theme.dividerColor,
                        width: isCurrent ? 1.6 : 0.9,
                      ),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                          color: Colors.black.withOpacity(0.08),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: isCurrent ? theme.colorScheme.primary : theme.colorScheme.secondary,
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
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                tiene ? '$count noticias' : 'Sin noticias',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: tiene ? FontWeight.w700 : FontWeight.w500,
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
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearChart({required int year, required Key key}) {
    final theme = Theme.of(context);

    final isCurrent = _isCurrentYear(year);
    final stats = _buildStatsForYear(year, includeEnCurso: isCurrent);

    final totalCompletadas = stats.fold<int>(0, (a, b) => a + b.completadas);
    final totalAgendadas = stats.fold<int>(0, (a, b) => a + b.agendadas);
    final totalEnCurso = stats.fold<int>(0, (a, b) => a + b.enCurso);

    final hasMany = stats.length > 8;

    return Padding(
      key: key,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text(''),
                onPressed: () => setState(() => _selectedYear = null),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Año $year',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Resumen',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _pill(theme, 'Agendadas: $totalAgendadas'),
                  const SizedBox(width: 8),
                  _pill(theme, 'Completadas: $totalCompletadas'),
                  if (isCurrent) ...[
                    const SizedBox(width: 8),
                    _pill(theme, 'En curso: $totalEnCurso'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          Expanded(
            child: SfCartesianChart(
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
                    dataLabelSettings: const DataLabelSettings(isVisible: true),
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
}

class _ReporterStats {
  final int reporteroId;
  final String nombre;

  final int completadas;
  final int agendadas;
  final int enCurso;

  const _ReporterStats({
    required this.reporteroId,
    required this.nombre,
    required this.completadas,
    required this.agendadas,
    required this.enCurso,
  });

  int get total => completadas + agendadas + enCurso;

  _ReporterStats copyWith({int? completadas, int? agendadas, int? enCurso}) {
    return _ReporterStats(
      reporteroId: reporteroId,
      nombre: nombre,
      completadas: completadas ?? this.completadas,
      agendadas: agendadas ?? this.agendadas,
      enCurso: enCurso ?? this.enCurso,
    );
  }
}
