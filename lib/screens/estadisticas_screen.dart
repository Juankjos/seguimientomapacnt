import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../models/noticia.dart';
import '../models/reportero_admin.dart';
import '../services/api_service.dart';
import 'estadisticas_mes.dart';

enum StatsRange { day, week, month, year }

class ReporterStats {
  final int reporteroId;
  final String nombre;
  final int enCurso;
  final int completadas;

  const ReporterStats({
    required this.reporteroId,
    required this.nombre,
    required this.enCurso,
    required this.completadas,
  });

  int get total => enCurso + completadas;
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
      // Reporteros + noticias (admin)
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

  // ------------------- Helpers de rango de fechas -------------------

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _startOfWeek(DateTime d) {
    final day = _startOfDay(d);
    final diff = day.weekday - DateTime.monday; // lunes = 1
    return day.subtract(Duration(days: diff));
  }

  DateTime _startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

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
        final start = _startOfMonth(now);
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

  DateTime? _timestampFor(Noticia n) {
    if (n.pendiente == false) {
      return n.horaLlegada ?? n.ultimaMod ?? n.fechaCita;
    }
    return n.ultimaMod ?? n.fechaCita;
  }

  bool _inRange(DateTime? dt, DateTime start, DateTime end) {
    if (dt == null) return false;
    return !dt.isBefore(start) && dt.isBefore(end); 
  }

  List<ReporterStats> _buildStats(StatsRange range) {
    final bounds = _rangeBounds(range);

    final Map<int, ReporterStats> map = {
      for (final r in _reporteros)
        r.id: ReporterStats(
          reporteroId: r.id,
          nombre: r.nombre,
          enCurso: 0,
          completadas: 0,
        ),
    };

    for (final n in _noticias) {
      final ts = _timestampFor(n);
      if (!_inRange(ts, bounds.start, bounds.end)) continue;

      final rid = n.reporteroId ?? 0;

      if (!map.containsKey(rid)) {
        map[rid] = ReporterStats(
          reporteroId: rid,
          nombre: rid == 0 ? 'Sin asignar' : 'Reportero #$rid',
          enCurso: 0,
          completadas: 0,
        );
      }

      final cur = map[rid]!;
      if (n.pendiente == true) {
        map[rid] = ReporterStats(
          reporteroId: cur.reporteroId,
          nombre: cur.nombre,
          enCurso: cur.enCurso + 1,
          completadas: cur.completadas,
        );
      } else {
        map[rid] = ReporterStats(
          reporteroId: cur.reporteroId,
          nombre: cur.nombre,
          enCurso: cur.enCurso,
          completadas: cur.completadas + 1,
        );
      }
    }

    final list = map.values.toList();

    list.sort((a, b) => b.total.compareTo(a.total));

    return list;
  }

  String _tituloRange(StatsRange r) {
    switch (r) {
      case StatsRange.day:
        return 'Hoy';
      case StatsRange.week:
        return 'Esta semana';
      case StatsRange.month:
        return 'Este mes';
      case StatsRange.year:
        return 'Este año';
    }
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

    final stats = _buildStats(_range);

    if (stats.isEmpty) {
      return const Center(child: Text('No hay datos para mostrar.'));
    }

    final totalEnCurso = stats.fold<int>(0, (a, b) => a + b.enCurso);
    final totalCompletadas = stats.fold<int>(0, (a, b) => a + b.completadas);

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
                  _pill('En curso: $totalEnCurso'),
                  const SizedBox(width: 8),
                  _pill('Completadas: $totalCompletadas'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _buildChart(stats, key: ValueKey('${_tab.index}_$_animSeed')),
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

  Widget _buildChart(List<ReporterStats> stats, {required Key key}) {
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
