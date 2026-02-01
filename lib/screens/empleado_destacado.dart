// lib/screens/empleado_destacado.dart
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../models/noticia.dart';
import '../models/reportero_admin.dart';
import 'estadisticas_semanas_realizadas.dart';

const double _kWebMaxContentWidth = 1200;
const double _kWebWideBreakpoint = 980;

bool _isWebWide(BuildContext context) => kIsWeb && MediaQuery.of(context).size.width >= _kWebWideBreakpoint;

double _hPad(BuildContext context) => _isWebWide(context) ? 20 : 16;

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

Widget _maybeScrollbar({required Widget child}) {
  if (!kIsWeb) return child;
  return Scrollbar(thumbVisibility: true, interactive: true, child: child);
}

ShapeBorder _softShape(ThemeData theme) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: theme.dividerColor.withOpacity(0.7), width: 0.9),
    );

const Color _kFailFill = Color(0xFFFFD6D6);
const Color _kFailAccent = Color(0xFFC62828); 

const Color _kOkFill = Color(0xFFCFE8FF);
const Color _kOkAccent = Color(0xFF1565C0);

const Color _kOverFill = Color(0xFFFFF2B2);
const Color _kOverAccent = Color(0xFFF9A825);

typedef _StatusPalette = ({Color fill, Color accent});

_StatusPalette _paletteForTotal(int total, int minimo) {
  if (total < minimo) return (fill: _kFailFill, accent: _kFailAccent);
  if (total == minimo) return (fill: _kOkFill, accent: _kOkAccent);
  return (fill: _kOverFill, accent: _kOverAccent);
}

class EmpleadoDestacadoItem {
  final int id;
  final String nombre;
  final int total;

  EmpleadoDestacadoItem({required this.id, required this.nombre, required this.total});

  factory EmpleadoDestacadoItem.fromJson(Map<String, dynamic> j) {
    return EmpleadoDestacadoItem(
      id: (j['id'] as num).toInt(),
      nombre: (j['nombre'] ?? '').toString(),
      total: (j['total'] as num?)?.toInt() ?? 0,
    );
  }
}

class EmpleadoDestacadoPage extends StatefulWidget {
  final String role;
  final int? myReporteroId;

  const EmpleadoDestacadoPage({
    super.key,
    required this.role,
    this.myReporteroId,
  });

  @override
  State<EmpleadoDestacadoPage> createState() => _EmpleadoDestacadoPageState();
}

class _EmpleadoDestacadoPageState extends State<EmpleadoDestacadoPage> {
  late int _anio;
  late int _mes;

  bool _loading = false;
  String? _error;

  int _minimo = 10;
  List<EmpleadoDestacadoItem> _items = [];

  bool get _esAdmin => widget.role == 'admin';

  static const _meses = <int, String>{
    1: 'Enero',
    2: 'Febrero',
    3: 'Marzo',
    4: 'Abril',
    5: 'Mayo',
    6: 'Junio',
    7: 'Julio',
    8: 'Agosto',
    9: 'Septiembre',
    10: 'Octubre',
    11: 'Noviembre',
    12: 'Diciembre',
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _anio = now.year;
    _mes = now.month;
    _cargar();
  }

  Future<void> _abrirSemanasRealizadas() async {
  // loader modal
  if (mounted) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }

  try {
    final results = await Future.wait([
      ApiService.getReporterosAdmin(),
      ApiService.getNoticiasAdmin(),
    ]);

    final reporteros = results[0] as List<ReporteroAdmin>;
    final noticias = results[1] as List<Noticia>;

    if (!mounted) return;
    Navigator.pop(context);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EstadisticasSemanasRealizadas(
          year: _anio,
          month: _mes,
          monthName: _meses[_mes] ?? 'Mes',
          reporteros: reporteros,
          noticias: noticias,
        ),
      ),
    );
  } catch (e) {
    if (mounted) Navigator.pop(context); 
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error al abrir semanas: $e')),
    );
  }
}


  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await ApiService.getEmpleadoDestacado(anio: _anio, mes: _mes);

      final minimo = (resp['data']?['minimo'] as num?)?.toInt() ?? 10;
      final list = (resp['data']?['reporteros'] as List<dynamic>? ?? [])
          .map((e) => EmpleadoDestacadoItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      if (!mounted) return;
      setState(() {
        _minimo = minimo;
        _items = list;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editarMinimo() async {
    if (!_esAdmin) return;

    final ctrl = TextEditingController(text: _minimo.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Mínimo • ${_meses[_mes]} $_anio'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Nuevo mínimo',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );

    if (ok != true) return;

    final v = int.tryParse(ctrl.text.trim());
    if (v == null || v < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mínimo inválido')),
      );
      return;
    }

    try {
      await ApiService.setMinimoEmpleadoDestacado(
        anio: _anio,
        mes: _mes,
        minimo: v,
        role: widget.role,
        updatedBy: widget.myReporteroId,
      );

      if (!mounted) return;
      setState(() => _minimo = v);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mínimo actualizado')),
      );

      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = _isWebWide(context);

    final header = Row(
      children: [
        const Icon(Icons.star_rounded),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Empleado del Mes',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        TextButton.icon(
          onPressed: _cargar,
          icon: const Icon(Icons.refresh),
          label: const Text('Refrescar'),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: _abrirSemanasRealizadas,
          icon: const Icon(Icons.view_week),
          label: const Text('Semanas'),
        ),
      ],
    );

    final filtros = Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<int>(
            value: _mes,
            decoration: const InputDecoration(
              labelText: 'Mes',
              border: OutlineInputBorder(),
            ),
            items: _meses.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) async {
              if (v == null) return;
              setState(() => _mes = v);
              await _cargar();
            },
          ),
        ),
        SizedBox(
          width: 140,
          child: DropdownButtonFormField<int>(
            value: _anio,
            decoration: const InputDecoration(
              labelText: 'Año',
              border: OutlineInputBorder(),
            ),
            items: List.generate(5, (i) {
              final y = DateTime.now().year - 2 + i;
              return DropdownMenuItem(value: y, child: Text('$y'));
            }),
            onChanged: (v) async {
              if (v == null) return;
              setState(() => _anio = v);
              await _cargar();
            },
          ),
        ),
        Card(
          elevation: 0,
          shape: _softShape(theme),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Mínimo: ', style: theme.textTheme.bodyMedium),
                Text('$_minimo', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900)),
                if (_esAdmin) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Editar mínimo',
                    onPressed: _editarMinimo,
                    icon: const Icon(Icons.edit),
                  )
                ],
              ],
            ),
          ),
        ),
      ],
    );

    final legend = Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        _LegendChip(fill: _kFailFill, accent: _kFailAccent, label: 'No alcanza meta'),
        _LegendChip(fill: _kOkFill, accent: _kOkAccent, label: 'Meta alcanzada'),
        _LegendChip(fill: _kOverFill, accent: _kOverAccent, label: 'Sobrepasa Meta'),
      ],
    );

    final chartCard = Card(
      elevation: kIsWeb ? 0.6 : 2,
      shape: _softShape(theme),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            const SizedBox(height: 12),
            filtros,
            const SizedBox(height: 10),
            legend,
            const SizedBox(height: 12),

            if (_loading)
              const SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Error: $_error'),
              )
            else if (_items.isEmpty)
              const SizedBox(
                height: 220,
                child: Center(child: Text('No hay datos para mostrar')),
              )
            else
              _buildChart(theme),
          ],
        ),
      ),
    );

    final resumenCard = Card(
      elevation: kIsWeb ? 0.6 : 2,
      shape: _softShape(theme),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.list_alt),
                SizedBox(width: 8),
                Text('Resumen', style: TextStyle(fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 10),
            if (_items.isEmpty && !_loading && _error == null)
              const Text('Sin datos')
            else
              Expanded(
                child: _maybeScrollbar(
                  child: ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final it = _items[i];
                      final extra = math.max(0, it.total - _minimo);
                      final p = _paletteForTotal(it.total, _minimo);

                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor: p.fill,
                          foregroundColor: p.accent,
                          child: Text(it.nombre.isNotEmpty ? it.nombre[0].toUpperCase() : '?'),
                        ),
                        title: Text(it.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          extra > 0 ? 'Total: ${it.total}  (Extras: $extra)' : 'Total: ${it.total}',
                        ),
                        trailing: Icon(Icons.circle, color: p.accent, size: 12),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (wide) {
      return Scaffold(
        appBar: AppBar(title: const Text('Regresar')),
        body: _wrapWebWidth(
          Padding(
            padding: EdgeInsets.all(_hPad(context)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 8, child: chartCard),
                const SizedBox(width: 12),
                Expanded(flex: 4, child: resumenCard),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Regresar')),
      body: _maybeScrollbar(
        child: ListView(
          padding: EdgeInsets.all(_hPad(context)),
          children: [
            chartCard,
            const SizedBox(height: 12),
            SizedBox(height: 420, child: resumenCard),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(ThemeData theme) {
    const barW = 54.0;
    const gap = 18.0;
    final n = _items.length;
    final width = math.max(640.0, n * (barW + gap) + 40);

    final maxY = math.max(
      _minimo.toDouble(),
      (_items.map((e) => e.total).fold<int>(0, math.max)).toDouble(),
    );

    return SizedBox(
      height: 320,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: CustomPaint(
            painter: _ColumnChartPainter(
              items: _items,
              minimo: _minimo,
              maxY: (maxY * 1.15).clamp(1, 999999).toDouble(),
              theme: theme,
              barWidth: barW,
              gap: gap,
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color fill;
  final Color accent;
  final String label;

  const _LegendChip({required this.fill, required this.accent, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: accent,
        ),
      ),
    );
  }
}

class _ColumnChartPainter extends CustomPainter {
  final List<EmpleadoDestacadoItem> items;
  final int minimo;
  final double maxY;
  final ThemeData theme;
  final double barWidth;
  final double gap;

  _ColumnChartPainter({
    required this.items,
    required this.minimo,
    required this.maxY,
    required this.theme,
    required this.barWidth,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final leftPad = 16.0;
    final topPad = 16.0;
    final bottomPad = 52.0;

    final chartH = size.height - topPad - bottomPad;
    final startX = leftPad;

    final axisPaint = Paint()
      ..color = theme.dividerColor.withOpacity(0.8)
      ..strokeWidth = 1;

    final baseY = topPad + chartH;
    canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY), axisPaint);

    final minY = baseY - (minimo / maxY) * chartH;

    for (int i = 0; i < items.length; i++) {
      final it = items[i];
      final total = it.total;

      final x = startX + i * (barWidth + gap);
      final h = (total / maxY) * chartH;
      final p = _paletteForTotal(total, minimo);

      final rect = Rect.fromLTWH(x, baseY - h, barWidth, h);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));

      final barPaint = Paint()..color = p.fill;
      canvas.drawRRect(rrect, barPaint);

      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = p.accent.withOpacity(0.35);
      canvas.drawRRect(rrect, borderPaint);

      final extra = math.max(0, total - minimo);
      final label = (extra > 0) ? '$minimo + $extra' : '$total';
      _drawText(
        canvas,
        label,
        Offset(x + barWidth + 6, baseY - h - 10),
        theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w900, color: p.accent) ??
            TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.accent),
      );

      final short = _shortName(it.nombre);
      _drawText(
        canvas,
        short,
        Offset(x, baseY + 8),
        theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.grey[700],
            ) ??
            const TextStyle(fontSize: 11),
      );
    }

    final haloPaint = Paint()
      ..color = theme.colorScheme.surface.withOpacity(0.95)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(0, minY), Offset(size.width, minY), haloPaint);

    final minPaint = Paint()
      ..color = theme.colorScheme.primary.withOpacity(0.65)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(0, minY), Offset(size.width, minY), minPaint);

    _drawText(
      canvas,
      'Meta: $minimo',
      Offset(8, math.max(4, minY - 20)),
      theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: theme.colorScheme.primary,
          ) ??
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
    );
  }

  String _shortName(String s) {
    final t = s.trim();
    if (t.isEmpty) return '?';
    final parts = t.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.length > 10 ? '${parts.first.substring(0, 10)}…' : parts.first;
    final first = parts.first;
    final last = parts.last;
    final v = '${first[0].toUpperCase()}${last[0].toUpperCase()}';
    return v;
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 140);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _ColumnChartPainter oldDelegate) {
    return oldDelegate.items != items ||
        oldDelegate.minimo != minimo ||
        oldDelegate.maxY != maxY ||
        oldDelegate.theme != theme;
  }
}
