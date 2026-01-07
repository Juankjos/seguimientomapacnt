// lib/screens/estadisticas_screen.dart
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../models/noticia.dart';
import '../models/reportero_admin.dart';
import '../services/api_service.dart';
import 'estadisticas_mes.dart';
import 'estadisticas_semanas.dart';
import 'estadisticas_dias.dart';

enum StatsRange { day, week, month, year }

class ReporterStats {
  final int reporteroId;
  final String nombre;

  final int completadas; 
  final int enCurso;   
  final int agendadas;   

  const ReporterStats({
    required this.reporteroId,
    required this.nombre,
    required this.completadas,
    required this.enCurso,
    required this.agendadas,
  });

  int get total => completadas + enCurso + agendadas;
}

class EstadisticasScreen extends StatefulWidget {
  const EstadisticasScreen({super.key});

  @override
  State<EstadisticasScreen> createState() => _EstadisticasScreenState();
}

class _EstadisticasScreenState extends State<EstadisticasScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  bool _loading = true;
  String? _error;

  List<ReporteroAdmin> _reporteros = [];
  List<Noticia> _noticias = [];

  int _animSeed = 0;
  late final TooltipBehavior _tooltip;

  @override
  void initState() {
    super.initState();
    _tooltip = TooltipBehavior(enable: true);
    _tab = TabController(length: 4, vsync: this);

    _tab.addListener(() {
      if (!_tab.indexIsChanging) {
        setState(() => _animSeed++);
      }
    });

    _cargar();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  StatsRange get _range => StatsRange.values[_tab.index];

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final reps = await ApiService.getReporterosAdmin(q: '');
      final news = await ApiService.getNoticiasAdmin();

      setState(() {
        _reporteros = reps;
        _noticias = news;
        _loading = false;
      });

      setState(() => _animSeed++);
    } catch (e) {
      setState(() {
        _error = 'Error cargando estadísticas: $e';
        _loading = false;
      });
    }
  }

  // ------------------- Helpers de fechas -------------------

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _startOfWeek(DateTime d) {
    final day = _startOfDay(d);
    final diff = day.weekday - DateTime.monday; // lunes = 1
    return day.subtract(Duration(days: diff));
  }

  DateTime _startOfYear(DateTime d) => DateTime(d.year, 1, 1);

  ({DateTime start, DateTime end}) _rangeBounds(StatsRange r) {
    final now = DateTime.now();

    switch (r) {
      case StatsRange.day:
        final start = _startOfDay(now);
        final end = start.add(const Duration(days: 1));
        return (start: start, end: end);

      case StatsRange.week:
        final start = _startOfWeek(now);
        final end = start.add(const Duration(days: 7));
        return (start: start, end: end);

      case StatsRange.month:
        final start = DateTime(now.year, now.month, 1);
        final end = (start.month == 12)
            ? DateTime(start.year + 1, 1, 1)
            : DateTime(start.year, start.month + 1, 1);
        return (start: start, end: end);

      case StatsRange.year:
        final start = _startOfYear(now);
        final end = DateTime(start.year + 1, 1, 1);
        return (start: start, end: end);
    }
  }

  bool _inRange(DateTime? dt, DateTime start, DateTime endExclusive) {
    if (dt == null) return false;
    return !dt.isBefore(start) && dt.isBefore(endExclusive);
  }

  // ------------------- Día (HOY) con lógica nueva -------------------

  List<ReporterStats> _buildStatsToday() {
    final b = _rangeBounds(StatsRange.day);

    final Map<int, ReporterStats> map = {
      for (final r in _reporteros)
        r.id: ReporterStats(
          reporteroId: r.id,
          nombre: r.nombre,
          completadas: 0,
          agendadas: 0,
          enCurso: 0,
        ),
    };

    for (final n in _noticias) {
      final rid = n.reporteroId ?? 0;

      if (!map.containsKey(rid)) {
        map[rid] = ReporterStats(
          reporteroId: rid,
          nombre: rid == 0 ? 'Sin asignar' : 'Reportero #$rid',
          completadas: 0,
          agendadas: 0,
          enCurso: 0,
        );
      }

      final cur = map[rid]!;

      final isCompletadaHoy = _inRange(n.horaLlegada, b.start, b.end);
      final isAgendadaHoy =
          (n.pendiente == true) && _inRange(n.fechaCita, b.start, b.end);
      final isEnCursoHoy = _inRange(n.fechaCita, b.start, b.end);

      map[rid] = ReporterStats(
        reporteroId: cur.reporteroId,
        nombre: cur.nombre,
        completadas: cur.completadas + (isCompletadaHoy ? 1 : 0),
        agendadas: cur.agendadas + (isAgendadaHoy ? 1 : 0),
        enCurso: cur.enCurso + (isEnCursoHoy ? 1 : 0),
      );
    }

    final list = map.values.toList();
    list.sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  // ------------------- Año (por ahora se queda como antes) -------------------

  DateTime? _timestampForLegacy(Noticia n) {
    if (n.pendiente == false) {
      return n.horaLlegada ?? n.ultimaMod ?? n.fechaCita;
    }
    return n.ultimaMod ?? n.fechaCita;
  }

  List<ReporterStats> _buildStatsLegacy(StatsRange range) {
    final bounds = _rangeBounds(range);

    final Map<int, ReporterStats> map = {
      for (final r in _reporteros)
        r.id: ReporterStats(
          reporteroId: r.id,
          nombre: r.nombre,
          enCurso: 0,
          completadas: 0,
          agendadas: 0, 
        ),
    };

    for (final n in _noticias) {
      final ts = _timestampForLegacy(n);
      if (!_inRange(ts, bounds.start, bounds.end)) continue;

      final rid = n.reporteroId ?? 0;

      if (!map.containsKey(rid)) {
        map[rid] = ReporterStats(
          reporteroId: rid,
          nombre: rid == 0 ? 'Sin asignar' : 'Reportero #$rid',
          enCurso: 0,
          completadas: 0,
          agendadas: 0,
        );
      }

      final cur = map[rid]!;
      if (n.pendiente == true) {
        map[rid] = ReporterStats(
          reporteroId: cur.reporteroId,
          nombre: cur.nombre,
          enCurso: cur.enCurso + 1,
          completadas: cur.completadas,
          agendadas: 0,
        );
      } else {
        map[rid] = ReporterStats(
          reporteroId: cur.reporteroId,
          nombre: cur.nombre,
          enCurso: cur.enCurso,
          completadas: cur.completadas + 1,
          agendadas: 0,
        );
      }
    }

    final list = map.values.toList();
    list.sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  // ------------------- UI helpers -------------------

  String _tituloRange(StatsRange r) {
    switch (r) {
      case StatsRange.day:
        return 'Hoy';
      case StatsRange.week:
        return 'Semanas del mes';
      case StatsRange.month:
        return 'Este mes';
      case StatsRange.year:
        return 'Este año';
    }
  }

  String _nombreMes(int month) {
    const nombres = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
    ];
    return nombres[month - 1];
  }

  Future<void> _openDiasMesActual() async {
    final now = DateTime.now();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EstadisticasDias(
          year: now.year,
          month: now.month,
          monthName: _nombreMes(now.month),
          reporteros: _reporteros,
          noticias: _noticias,
        ),
      ),
    );
  }

  // ------------------- UI -------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estadísticas'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Día'),
            Tab(text: 'Semana'),
            Tab(text: 'Mes'),
            Tab(text: 'Año'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_range == StatsRange.month) {
      return EstadisticasMes(
        reporteros: _reporteros,
        noticias: _noticias,
      );
    }

    if (_range == StatsRange.week) {
      final now = DateTime.now();
      return EstadisticasSemanas(
        embedded: true,
        year: now.year,
        month: now.month,
        monthName: _nombreMes(now.month),
        reporteros: _reporteros,
        noticias: _noticias,
      );
    }

    final List<ReporterStats> stats =
        (_range == StatsRange.day) ? _buildStatsToday() : _buildStatsLegacy(_range);

    if (stats.isEmpty) {
      return const Center(child: Text('No hay datos para mostrar.'));
    }

    final totalCompletadas = stats.fold<int>(0, (a, b) => a + b.completadas);
    final totalAgendadas = stats.fold<int>(0, (a, b) => a + b.agendadas);
    final totalEnCurso = stats.fold<int>(0, (a, b) => a + b.enCurso);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _tituloRange(_range),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),

                  if (_range == StatsRange.day) ...[
                    _pill('Agendadas: $totalAgendadas'),
                    const SizedBox(width: 8),
                    _pill('Completadas: $totalCompletadas'),
                    const SizedBox(width: 8),
                    _pill('En curso: $totalEnCurso'),
                  ] else ...[
                    _pill('En curso: $totalEnCurso'),
                    const SizedBox(width: 8),
                    _pill('Completadas: $totalCompletadas'),
                  ],
                ],
              ),
            ),
          ),

          if (_range == StatsRange.day) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month),
                label: const Text('Días'),
                onPressed: _openDiasMesActual,
              ),
            ),
          ],

          const SizedBox(height: 10),

          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: (_range == StatsRange.day)
                  ? _buildChartDia(stats, key: ValueKey('day_${_animSeed}'))
                  : _buildChartLegacy(stats, key: ValueKey('${_tab.index}_$_animSeed')),
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

  Widget _buildChartDia(List<ReporterStats> stats, {required Key key}) {
    final theme = Theme.of(context);
    final hasMany = stats.length > 8;

    return SfCartesianChart(
      key: key,
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
        ColumnSeries<ReporterStats, String>(
          name: 'Completadas',
          dataSource: stats,
          xValueMapper: (d, _) => d.nombre,
          yValueMapper: (d, _) => d.completadas,
          dataLabelSettings: const DataLabelSettings(isVisible: true),
          animationDuration: 650,
        ),
        ColumnSeries<ReporterStats, String>(
          name: 'En curso',
          dataSource: stats,
          xValueMapper: (d, _) => d.nombre,
          yValueMapper: (d, _) => d.enCurso,
          dataLabelSettings: const DataLabelSettings(isVisible: true),
          animationDuration: 650,
        ),
        ColumnSeries<ReporterStats, String>(
          name: 'Agendadas',
          dataSource: stats,
          xValueMapper: (d, _) => d.nombre,
          yValueMapper: (d, _) => d.agendadas,
          dataLabelSettings: const DataLabelSettings(isVisible: true),
          animationDuration: 650,
        ),
      ],
    );
  }

  Widget _buildChartLegacy(List<ReporterStats> stats, {required Key key}) {
    final theme = Theme.of(context);
    final hasMany = stats.length > 8;

    return SfCartesianChart(
      key: key,
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
        ColumnSeries<ReporterStats, String>(
          name: 'En curso',
          dataSource: stats,
          xValueMapper: (d, _) => d.nombre,
          yValueMapper: (d, _) => d.enCurso,
          dataLabelSettings: const DataLabelSettings(isVisible: true),
          animationDuration: 650,
        ),
        ColumnSeries<ReporterStats, String>(
          name: 'Completadas',
          dataSource: stats,
          xValueMapper: (d, _) => d.nombre,
          yValueMapper: (d, _) => d.completadas,
          dataLabelSettings: const DataLabelSettings(isVisible: true),
          animationDuration: 650,
        ),
      ],
    );
  }
}
