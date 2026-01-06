import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../models/noticia.dart';
import '../models/reportero_admin.dart';
import 'estadisticas_semanas.dart';

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

  @override
  void initState() {
    super.initState();
    _tooltip = TooltipBehavior(enable: true);
  }

  // ------------------- Helpers rango de mes -------------------

  ({DateTime start, DateTime end}) _monthBounds(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = (month == 12) ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    return (start: start, end: end);
  }

  DateTime? _timestampFor(Noticia n) {
    if (n.pendiente == false) {
      return n.horaLlegada ?? n.ultimaMod ?? n.fechaCita;
    }
    return n.ultimaMod ?? n.fechaCita;
  }

  bool _inRange(DateTime? dt, DateTime start, DateTime end) {
    if (dt == null) return false;
    return !dt.isBefore(start) && dt.isBefore(end); // [start, end)
  }

  // ------------------- Stats internos -------------------

  List<_ReporterStats> _buildStatsForMonth(int year, int month) {
    final bounds = _monthBounds(year, month);

    final Map<int, _ReporterStats> map = {
      for (final r in widget.reporteros)
        r.id: _ReporterStats(
          reporteroId: r.id,
          nombre: r.nombre,
          enCurso: 0,
          completadas: 0,
        ),
    };

    for (final n in widget.noticias) {
      final ts = _timestampFor(n);
      if (!_inRange(ts, bounds.start, bounds.end)) continue;

      final rid = n.reporteroId ?? 0;

      if (!map.containsKey(rid)) {
        map[rid] = _ReporterStats(
          reporteroId: rid,
          nombre: rid == 0 ? 'Sin asignar' : 'Reportero #$rid',
          enCurso: 0,
          completadas: 0,
        );
      }

      final cur = map[rid]!;
      if (n.pendiente == true) {
        map[rid] = cur.copyWith(enCurso: cur.enCurso + 1);
      } else {
        map[rid] = cur.copyWith(completadas: cur.completadas + 1);
      }
    }

    final list = map.values.toList();

    list.sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  int _countNoticiasEnMes(int year, int month) {
    final b = _monthBounds(year, month);
    int c = 0;
    for (final n in widget.noticias) {
      if (_inRange(_timestampFor(n), b.start, b.end)) c++;
    }
    return c;
  }

  // ------------------- UI -------------------

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _selectedMonth == null
          ? _buildGridMeses(key: const ValueKey('grid'))
          : _buildChartMes(
              month: _selectedMonth!,
              key: ValueKey('chart_${_selectedMonth!}_$_animSeed'),
            ),
    );
  }

  Widget _buildGridMeses({required Key key}) {
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
              '$_year',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 10),

          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.only(bottom: 6),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.95,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                final month = index + 1;
                final nombreMes = _nombreMes(month);
                final efem = _efemerideMes(month, theme);
                final count = _countNoticiasEnMes(_year, month);
                final tiene = count > 0;

                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    setState(() {
                      _selectedMonth = month;
                      _animSeed++; // fuerza reanimación al entrar al chart
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
                        color: tiene ? theme.colorScheme.primary : theme.dividerColor,
                        width: tiene ? 1.4 : 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                          color: Colors.black.withOpacity(0.08),
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
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            tiene ? '$count noticias' : 'Sin noticias',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: tiene ? FontWeight.w700 : FontWeight.w500,
                              color: tiene
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface.withOpacity(0.7),
                            ),
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
      ),
    );
  }

  Widget _buildChartMes({required int month, required Key key}) {
    final theme = Theme.of(context);

    final stats = _buildStatsForMonth(_year, month);
    final totalEnCurso = stats.fold<int>(0, (a, b) => a + b.enCurso);
    final totalCompletadas = stats.fold<int>(0, (a, b) => a + b.completadas);

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
                label: const Text('Volver'),
                onPressed: () {
                  setState(() {
                    _selectedMonth = null;
                  });
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_nombreMes(month)} $_year',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                icon: const Icon(Icons.view_carousel),
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
                      'Resumen del mes',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _pill('En curso: $totalEnCurso'),
                  const SizedBox(width: 8),
                  _pill('Completadas: $totalCompletadas'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Chart
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
                  name: 'En curso',
                  dataSource: stats,
                  xValueMapper: (d, _) => d.nombre,
                  yValueMapper: (d, _) => d.enCurso,
                  dataLabelSettings: const DataLabelSettings(isVisible: true),
                  animationDuration: 650,
                ),
                ColumnSeries<_ReporterStats, String>(
                  name: 'Completadas',
                  dataSource: stats,
                  xValueMapper: (d, _) => d.nombre,
                  yValueMapper: (d, _) => d.completadas,
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

  Widget _pill(String text) {
    final theme = Theme.of(context);
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
  const _MesEfemeride({required this.icon, required this.color, required this.tooltip});
}

_MesEfemeride _efemerideMes(int month, ThemeData theme) {
  switch (month) {
    case 1:
      return const _MesEfemeride(icon: Icons.celebration, color: Color(0xFFF94144), tooltip: 'Año Nuevo');
    case 2:
      return const _MesEfemeride(icon: Icons.favorite, color: Color(0xFFF3722C), tooltip: 'Día del Amor y la Amistad');
    case 3:
      return const _MesEfemeride(icon: Icons.emoji_nature, color: Color(0xFFF8961E), tooltip: 'Primavera');
    case 4:
      return const _MesEfemeride(icon: Icons.face_outlined, color: Color(0xFFF9844A), tooltip: 'Día del Niño');
    case 5:
      return const _MesEfemeride(icon: Icons.face_2_rounded, color: Color(0xFFF9C74F), tooltip: 'Día de las Madres');
    case 6:
      return const _MesEfemeride(icon: Icons.wb_sunny, color: Color(0xFF90BE6D), tooltip: 'Verano');
    case 7:
      return const _MesEfemeride(icon: Icons.beach_access, color: Color(0xFF43AA8B), tooltip: 'Vacaciones de verano');
    case 8:
      return const _MesEfemeride(icon: Icons.school, color: Color(0xFF4D908E), tooltip: 'Regreso a clases');
    case 9:
      return const _MesEfemeride(icon: Icons.flag, color: Color(0xFF577590), tooltip: 'Independencia de México');
    case 10:
      return const _MesEfemeride(icon: Icons.nights_stay, color: Color(0xFF277DA1), tooltip: 'Día de Muertos');
    case 11:
      return const _MesEfemeride(icon: Icons.local_florist, color: Color(0xFF4D908E), tooltip: 'Día de Muertos / Revolución');
    case 12:
      return const _MesEfemeride(icon: Icons.ice_skating_outlined, color: Color(0xFFF94144), tooltip: 'Navidad');
    default:
      return _MesEfemeride(icon: Icons.event, color: theme.colorScheme.primary, tooltip: 'Mes');
  }
}

// ------------------- Stats interno (privado) -------------------

class _ReporterStats {
  final int reporteroId;
  final String nombre;
  final int enCurso;
  final int completadas;

  const _ReporterStats({
    required this.reporteroId,
    required this.nombre,
    required this.enCurso,
    required this.completadas,
  });

  int get total => enCurso + completadas;

  _ReporterStats copyWith({int? enCurso, int? completadas}) {
    return _ReporterStats(
      reporteroId: reporteroId,
      nombre: nombre,
      enCurso: enCurso ?? this.enCurso,
      completadas: completadas ?? this.completadas,
    );
  }
}
