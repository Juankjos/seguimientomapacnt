// lib/screens/empleado_destacado.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

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

  bool _isRoleReportero(ReporteroAdmin r) {
    final role = (r.role).toString().trim().toLowerCase();
    return role == 'reportero';
  }

  bool _noticiaPerteneceAMes(Noticia n, int anio, int mes) {
    final bool pendiente = (n.pendiente == true);

    DateTime? dt;
    if (!pendiente && n.horaLlegada != null) {
      dt = n.horaLlegada;
    } else if (pendiente && n.fechaCita != null) {
      dt = n.fechaCita;
    } else {
      dt = n.fechaPago ?? n.fechaCita ?? n.horaLlegada;
    }

    if (dt == null) return false;
    return dt.year == anio && dt.month == mes;
  }

  Future<void> _abrirDesglose() async {
    // Loader
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }

    List<ReporteroAdmin> reporteros = [];

    try {
      final all = await ApiService.getReporterosAdmin();
      reporteros = all.where(_isRoleReportero).toList()
        ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));

      if (!mounted) return;
      Navigator.pop(context); // cierra loader
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar reporteros: $e')),
      );
      return;
    }

    int? selectedId;
    String selectedNombre = '';

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setModalState) {
            return AlertDialog(
              title: Text('Desglose • ${_meses[_mes]} $_anio'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      value: selectedId,
                      decoration: const InputDecoration(
                        labelText: 'Selecciona reportero',
                        border: OutlineInputBorder(),
                      ),
                      items: reporteros
                          .map((r) => DropdownMenuItem<int>(
                                value: r.id,
                                child: Text(r.nombre, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) {
                        final rid = v;
                        final rep = reporteros.where((x) => x.id == rid).toList();
                        setModalState(() {
                          selectedId = rid;
                          selectedNombre = rep.isNotEmpty ? rep.first.nombre : '';
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Se descargará un PDF con noticias del mes seleccionado.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cerrar'),
                ),
                FilledButton.icon(
                  onPressed: (selectedId == null)
                      ? null
                      : () async {
                          Navigator.pop(dialogCtx);
                          await _descargarPdfDesglose(
                            reporteroId: selectedId!,
                            reporteroNombre: selectedNombre,
                          );
                        },
                  icon: const Icon(Icons.download),
                  label: const Text('Descargar PDF'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _descargarPdfDesglose({
    required int reporteroId,
    required String reporteroNombre,
  }) async {
    // Loader
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      final all = await ApiService.getNoticiasPorReportero(
        reporteroId: reporteroId,
        incluyeCerradas: true,
      );

      final monthList = all.where((n) => _noticiaPerteneceAMes(n, _anio, _mes)).toList();

      if (!mounted) return;
      Navigator.pop(context); 

      if (monthList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay noticias para este reportero en el mes seleccionado.')),
        );
        return;
      }

      final bytes = await _buildPdfDesgloseBytes(
        reporteroNombre: reporteroNombre.isEmpty ? 'Reportero #$reporteroId' : reporteroNombre,
        anio: _anio,
        mes: _mes,
        mesNombre: _meses[_mes] ?? 'Mes',
        minimoMeta: _minimo,
        noticias: monthList,
      );

      final safeName = (reporteroNombre.isEmpty ? 'reportero_$reporteroId' : reporteroNombre)
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');

      final fileName = 'desglose_${safeName}_${_anio}_${_mes.toString().padLeft(2, '0')}.pdf';

      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al generar PDF: $e')),
      );
    }
  }

  Future<Uint8List> _buildPdfDesgloseBytes({
    required String reporteroNombre,
    required int anio,
    required int mes,
    required String mesNombre,
    required int minimoMeta,
    required List<Noticia> noticias,
  }) async {
    final doc = pw.Document();

    // final df = DateFormat('dd/MM/yyyy hh:mm a', 'es_MX');  
    final dfWeek = DateFormat('EEEE dd/MM/yyyy h:mm a', 'es_MX');
    final dfWeekDate = DateFormat('EEEE dd/MM/yyyy', 'es_MX');

    // ---------------- Helpers semana (Lun–Dom recortadas al mes) ----------------

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

    List<({DateTime start, DateTime endExclusive})> _buildWeeksForMonth(int year, int month) {
      final mStart = _monthStart(year, month);
      final mEndEx = _monthEndExclusive(year, month);

      var cursorWeekStart = _startOfWeekMonday(mStart);
      final out = <({DateTime start, DateTime endExclusive})>[];

      while (cursorWeekStart.isBefore(mEndEx)) {
        final cursorWeekEndEx = cursorWeekStart.add(const Duration(days: 7));

        final start = cursorWeekStart.isBefore(mStart) ? mStart : cursorWeekStart;
        final endEx = cursorWeekEndEx.isAfter(mEndEx) ? mEndEx : cursorWeekEndEx;

        out.add((start: start, endExclusive: endEx));
        cursorWeekStart = cursorWeekStart.add(const Duration(days: 7));
      }

      return out;
    }

    bool _inRange(DateTime? dt, DateTime start, DateTime endExclusive) {
      if (dt == null) return false;
      final d = _dayOnly(dt);
      return !d.isBefore(start) && d.isBefore(endExclusive);
    }

    DateTime? _fechaParaSemana(Noticia n) {
      final pendiente = (n.pendiente == true);

      if (!pendiente && n.horaLlegada != null) return n.horaLlegada;
      if (pendiente && n.fechaCita != null) return n.fechaCita;

      return n.fechaPago ?? n.fechaCita ?? n.horaLlegada;
    }

    String _weekTitle(DateTime start, DateTime endInclusive) {
      return 'Semana del ${start.day} al ${endInclusive.day} $mesNombre $anio';
    }

    pw.Widget _bulletLine(String text) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 4,
            height: 4,
            margin: const pw.EdgeInsets.only(top: 4),
            decoration: const pw.BoxDecoration(
              color: PdfColors.black,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Text(text, style: const pw.TextStyle(fontSize: 10.5)),
          ),
        ],
      );
    }

    // ---------------- Conteos globales ----------------

    int realizadas = 0;
    int pendientes = 0;
    for (final n in noticias) {
      if (n.pendiente == true) {
        pendientes++;
      } else {
        realizadas++;
      }
    }

    // ---------------- Detección extras del mes ----------------
    final realizadasValidas = noticias
        .where((n) => (n.pendiente == false) && (n.horaLlegada != null))
        .toList()
      ..sort((a, b) => a.horaLlegada!.compareTo(b.horaLlegada!));

    final extrasIds = <int>{};
    if (realizadasValidas.length > minimoMeta) {
      for (int i = minimoMeta; i < realizadasValidas.length; i++) {
        final id = realizadasValidas[i].id;
        if (id != null) extrasIds.add(id);
      }
    }

    final weeks = _buildWeeksForMonth(anio, mes);

    final Map<int, List<Noticia>> byWeek = {for (int i = 0; i < weeks.length; i++) i: <Noticia>[]};

    for (final n in noticias) {
      final dt = _fechaParaSemana(n);
      if (dt == null) continue;

      for (int i = 0; i < weeks.length; i++) {
        final w = weeks[i];
        if (_inRange(dt, w.start, w.endExclusive)) {
          byWeek[i]!.add(n);
          break;
        }
      }
    }

    int _cmpNoticia(Noticia a, Noticia b) {
      final ap = (a.pendiente == true);
      final bp = (b.pendiente == true);
      if (ap != bp) return ap ? -1 : 1;

      DateTime? ad = ap ? a.fechaCita : a.horaLlegada;
      DateTime? bd = bp ? b.fechaCita : b.horaLlegada;

      ad ??= a.fechaPago ?? a.fechaCita ?? a.horaLlegada;
      bd ??= b.fechaPago ?? b.fechaCita ?? b.horaLlegada;

      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    }

    for (final e in byWeek.entries) {
      e.value.sort(_cmpNoticia);
    }

    // ---------------- PDF UI helpers ----------------

    pw.Widget _weekHeader({
      required String title,
      required int total,
      required int wRealizadas,
      required int wPendientes,
      required int wExtras,
    }) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 10, bottom: 8),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.8),
          borderRadius: pw.BorderRadius.circular(8),
          color: PdfColors.grey100,
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(
              child: pw.Text(
                '$title: Total $total',
                style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Text('Realizadas: $wRealizadas', style: const pw.TextStyle(fontSize: 10.5)),
            pw.SizedBox(width: 6),
            pw.Text('Pendientes: $wPendientes', style: const pw.TextStyle(fontSize: 10.5)),
            if (wExtras > 0) ...[
              pw.SizedBox(width: 6),
              pw.Text('Extras: $wExtras', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
            ],
          ],
        ),
      );
    }

    pw.Widget _noticiaCard(Noticia n) {
      final bool pendiente = (n.pendiente == true);
      final estado = pendiente ? 'Pendiente' : 'Realizada';

      final titulo = (n.noticia).toString();
      final tipo = (n.tipoDeNota).toString().trim();
      final desc = (n.descripcion ?? '').toString();
      final cliente = (n.cliente ?? '').toString();
      final domicilio = (n.domicilio ?? '').toString();

      final cita = n.fechaCita;
      final llegada = n.horaLlegada;
      final pago = n.fechaPago;

      final baseLineStyle = const pw.TextStyle(fontSize: 10.5);
      final boldLabelStyle = pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold);

      String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

      String _ampmEs(String s) =>
          s.replaceAll('AM', 'A.M.').replaceAll('PM', 'P.M.');

      String fechaLinea = '';

      if (pendiente) {
        fechaLinea = cita != null ? _ampmEs(_cap(dfWeek.format(cita))) : '—';
      } else {
        if (llegada != null) {
          final l = llegada.toLocal();
          fechaLinea = _ampmEs(_cap(dfWeek.format(l)));
        } else if (pago != null) {
          fechaLinea = _cap(dfWeekDate.format(pago));
        } else {
          fechaLinea = '—';
        }
      }

      final id = n.id;
      final bool isExtra = (!pendiente) && (id != null) && extrasIds.contains(id);

      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.7),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (isExtra) ...[
                  pw.Text(' ', style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold, color: PdfColors.amber800)),
                ],
                pw.Expanded(
                  child: pw.Wrap(
                    crossAxisAlignment: pw.WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      pw.Text(
                        titulo.isEmpty ? '(Sin título)' : titulo,
                        style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold),
                      ),

                      if (tipo.isNotEmpty)
                        pw.Container(
                          margin: const pw.EdgeInsets.symmetric(horizontal: 4),
                          width: 1,
                          height: 12,
                          color: PdfColors.grey600,
                        ),

                      if (tipo.isNotEmpty)
                        pw.Text(
                          tipo,
                          style: pw.TextStyle(
                            fontSize: 10.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey800,
                          ),
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Text(
                  estado,
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
            if (isExtra)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.Text(
                  'Extra del mes',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.amber800),
                ),
              ),
            pw.SizedBox(height: 4),
            if (cliente.isNotEmpty) pw.Text('Cliente: $cliente', style: const pw.TextStyle(fontSize: 10.5)),
            pw.RichText(
              text: pw.TextSpan(
                style: baseLineStyle,
                children: [
                  pw.TextSpan(
                    text: pendiente ? 'Fecha de cita' : 'Fecha y Hora de llegada',
                    style: boldLabelStyle,
                  ),
                  pw.TextSpan(text: pendiente ? ' (Pendiente): ' : ': '),
                  pw.TextSpan(text: fechaLinea),
                ],
              ),
            ),
            if (domicilio.isNotEmpty) pw.RichText(
              text: pw.TextSpan(
                style: baseLineStyle,
                children: [
                  pw.TextSpan(text: 'Domicilio: ', style: boldLabelStyle),
                  pw.TextSpan(text: domicilio),
                ],
              ),
            ),
            if (desc.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text('Descripción:', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
              pw.Text(desc, style: const pw.TextStyle(fontSize: 10.5)),
            ],
          ],
        ),
      );
    }

    // ---------------- Construcción del PDF ----------------
    final base = pw.Font.ttf(await rootBundle.load('assets/fonts/SourceSans3-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/SourceSans3-SemiBold.ttf'));

    doc.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: base, bold: bold),
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
        build: (context) {
          final widgets = <pw.Widget>[
            pw.Text(
              'Desglose de noticias',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text('Reportero: $reporteroNombre'),
            pw.Text('Periodo: $mesNombre $anio'),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 0.8),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Total: ${noticias.length}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text('Realizadas: $realizadas'),
                      pw.Text('Pendientes: $pendientes'),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Mínimo del mes: $minimoMeta     Extras: ${extrasIds.length}',
                    style: const pw.TextStyle(fontSize: 10.5),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text('Secciones por semana', style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold)),
          ];

          for (int i = 0; i < weeks.length; i++) {
            final list = byWeek[i] ?? const <Noticia>[];
            if (list.isEmpty) continue;

            final w = weeks[i];
            final endIncl = w.endExclusive.subtract(const Duration(days: 1));
            final title = _weekTitle(w.start, endIncl);

            final wPend = list.where((n) => n.pendiente == true).length;
            final wReal = list.length - wPend;
            final wExtras = list.where((n) {
              final id = n.id;
              return (n.pendiente == false) && id != null && extrasIds.contains(id);
            }).length;

            widgets.add(
              _bulletLine(
                '$title: ${list.length} (Realizadas:$wReal | Pendientes:$wPend${wExtras > 0 ? ' | Extras:$wExtras' : ''})',
              ),
            );
          }

          widgets.add(pw.SizedBox(height: 8));

          for (int i = 0; i < weeks.length; i++) {
            final list = byWeek[i] ?? const <Noticia>[];
            if (list.isEmpty) continue;

            final w = weeks[i];
            final endIncl = w.endExclusive.subtract(const Duration(days: 1));
            final title = _weekTitle(w.start, endIncl);

            final wPend = list.where((n) => n.pendiente == true).length;
            final wReal = list.length - wPend;
            final wExtras = list.where((n) {
              final id = n.id;
              return (n.pendiente == false) && id != null && extrasIds.contains(id);
            }).length;

            widgets.add(
              _weekHeader(
                title: title,
                total: list.length,
                wRealizadas: wReal,
                wPendientes: wPend,
                wExtras: wExtras,
              ),
            );

            for (final n in list) {
              widgets.add(_noticiaCard(n));
            }
          }

          return widgets;
        },
      ),
    );

    return doc.save();
  }

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

  final ScrollController _chartHController = ScrollController();
  @override
  void dispose() {
    _chartHController.dispose();
    super.dispose();
  }

  Future<void> _abrirSemanasRealizadas() async {
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

    final header = LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 520;

    final titleRow = Row(
      children: [
        const Icon(Icons.star_rounded),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Empleado del Mes',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );

    final actions = Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        TextButton.icon(
          onPressed: _cargar,
          icon: const Icon(Icons.refresh),
          label: const Text('Refrescar'),
        ),
        TextButton.icon(
              onPressed: _abrirSemanasRealizadas,
              icon: const Icon(Icons.view_week),
              label: const Text('Semanas'),
            ),
            TextButton.icon(
              onPressed: _abrirDesglose,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Desglose'),
            ),
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleRow,
              const SizedBox(height: 8),
              actions,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: titleRow),
            actions,
          ],
        );
      },
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
    final contentW = n * (barW + gap) + 40;

    final maxY = math.max(
      _minimo.toDouble(),
      (_items.map((e) => e.total).fold<int>(0, math.max)).toDouble(),
    );

    return SizedBox(
      height: 320,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportW = constraints.maxWidth;

          final width = math.max(viewportW, contentW);

          return Scrollbar(
            controller: _chartHController,
            thumbVisibility: true,
            interactive: true,
            child: SingleChildScrollView(
              controller: _chartHController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: SizedBox(
                width: width,
                height: 320,
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
        },
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
      textDirection: ui.TextDirection.ltr,
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
