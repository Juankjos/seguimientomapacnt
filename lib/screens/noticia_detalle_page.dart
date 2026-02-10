// lib/screens/noticia_detalle_page.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as latlng;

import '../models/noticia.dart';
import '../services/api_service.dart';
import 'editar_noticia_page.dart';
import 'espectador_ruta_page.dart';
import 'mapa_completo_page.dart';
import 'mapa_ubicacion_page.dart';
import 'trayecto_ruta_page.dart';

const double _kWebMaxContentWidth = 1200;
const double _kWebWideBreakpoint = 980;

bool _isWebWide(BuildContext context) =>
    kIsWeb && MediaQuery.of(context).size.width >= _kWebWideBreakpoint;

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
      side: BorderSide(
        color: theme.dividerColor.withOpacity(0.70),
        width: 0.9,
      ),
    );

class NoticiaDetallePage extends StatefulWidget {
  final Noticia noticia;
  final bool soloLectura;
  final String role;

  const NoticiaDetallePage({
    super.key,
    required this.noticia,
    this.soloLectura = false,
    required this.role,
  });

  @override
  State<NoticiaDetallePage> createState() => _NoticiaDetallePageState();
}

class _NoticiaDetallePageState extends State<NoticiaDetallePage> {
  late Noticia _noticia;
  bool _eliminando = false;

  Timer? _clockTick;

  bool get _soloLectura => widget.soloLectura || _noticia.pendiente == false;

  bool get _yaTieneHoraLlegada => _noticia.horaLlegada != null;

  String _formatearFechaHora(DateTime dt) {
    return DateFormat("d 'de' MMMM 'de' y, HH:mm", 'es_MX').format(dt);
  }

  String _formatearFechaCitaAmPm(DateTime dt) {
    final fecha = DateFormat("d 'de' MMMM 'del' y", 'es_MX').format(dt);
    final hora = DateFormat("h:mm a", 'en_US').format(dt).toLowerCase();
    return '$fecha, $hora';
  }

  @override
  void initState() {
    super.initState();
    _noticia = widget.noticia;

    _clockTick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTick?.cancel();
    super.dispose();
  }

  DateTime _aMinuto(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute);

  ({bool allowed, String? message}) _validarInicioRuta() {
    final cita = _noticia.fechaCita;
    if (cita == null) {
      return (
        allowed: false,
        message: 'No hay fecha de cita, asigna Fecha/Hora para iniciar ruta.',
      );
    }

    final now = DateTime.now();
    final nowDay = DateTime(now.year, now.month, now.day);
    final citaDay = DateTime(cita.year, cita.month, cita.day);

    if (nowDay.isBefore(citaDay)) {
      return (
        allowed: false,
        message: 'Estás adelantado a la cita, cambia la Fecha para iniciar ruta.',
      );
    }

    if (nowDay.isAfter(citaDay)) {
      return (
        allowed: false,
        message: 'Estás atrasado, cambia la Fecha/Hora para iniciar ruta.',
      );
    }

    final nowMin = _aMinuto(now);
    final citaMin = _aMinuto(cita);

    if (nowMin.isAfter(citaMin)) {
      return (
        allowed: false,
        message: 'Estás atrasado, cambia la Hora para iniciar ruta.',
      );
    }

    return (allowed: true, message: null);
  }

  Color? _colorHoraLlegada() {
    final llegada = _noticia.horaLlegada;
    final cita = _noticia.fechaCita;

    if (llegada == null || cita == null) return null;

    final llegadaMin = _aMinuto(llegada);
    final citaMin = _aMinuto(cita);

    if (!llegadaMin.isAfter(citaMin)) {
      return Colors.green.shade900;
    }

    return Colors.red;
  }

  bool get _tieneCoordenadas =>
      _noticia.latitud != null && _noticia.longitud != null;

  Future<void> _refrescarNoticia() async {
    if (widget.role != 'admin') return;

    try {
      final list = await ApiService.getNoticiasAdmin();
      final updated = list.firstWhere(
        (n) => n.id == _noticia.id,
        orElse: () => _noticia,
      );

      if (!mounted) return;
      setState(() => _noticia = updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar la noticia: $e')),
      );
    }
  }

  Future<void> _abrirMapaUbicacion() async {
    if (_yaTieneHoraLlegada) return;

    final resultado = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MapaUbicacionPage(
          noticiaId: _noticia.id,
          latitudInicial: _noticia.latitud,
          longitudInicial: _noticia.longitud,
          domicilioInicial: _noticia.domicilio,
        ),
      ),
    );

    if (resultado != null) {
      final double? lat = resultado['lat'] as double?;
      final double? lon = resultado['lon'] as double?;
      final String? domicilio = resultado['domicilio'] as String?;

      if (lat != null && lon != null) {
        setState(() {
          _noticia = Noticia(
            id: _noticia.id,
            noticia: _noticia.noticia,
            descripcion: _noticia.descripcion,
            cliente: _noticia.cliente,
            domicilio: domicilio ?? _noticia.domicilio,
            reportero: _noticia.reportero,
            fechaCita: _noticia.fechaCita,
            fechaCitaAnterior: _noticia.fechaCitaAnterior,
            fechaCitaCambios: _noticia.fechaCitaCambios,
            fechaPago: _noticia.fechaPago,
            latitud: lat,
            longitud: lon,
            horaLlegada: _noticia.horaLlegada,
            llegadaLatitud: _noticia.llegadaLatitud,
            llegadaLongitud: _noticia.llegadaLongitud,
            pendiente: _noticia.pendiente,
            rutaIniciada: _noticia.rutaIniciada,
            rutaIniciadaAt: _noticia.rutaIniciadaAt,
            ultimaMod: DateTime.now(),
          );
        });
      }
    }
  }

  Future<void> _onEliminarPendientePressed() async {
    if (_eliminando) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eliminar de mis pendientes'),
          content: const Text('¿Seguro que deseas eliminar este pendiente?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sí'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    await _eliminarDePendientes();
  }

  Future<void> _eliminarDePendientes() async {
    setState(() => _eliminando = true);

    try {
      await ApiService.eliminarNoticiaDePendientes(widget.noticia.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Noticia eliminada de tus pendientes.')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar pendiente: $e')),
      );
    } finally {
      if (mounted) setState(() => _eliminando = false);
    }
  }

  // ===================== UI helpers =====================

  Widget _buildMapWidget({
    required bool tieneCoordenadas,
    required latlng.LatLng? punto,
    double? forcedHeight,
  }) {
    final theme = Theme.of(context);

    final keyStr =
        '${_noticia.latitud}-${_noticia.longitud}-${_noticia.llegadaLatitud}-${_noticia.llegadaLongitud}';

    if (!tieneCoordenadas || punto == null) {
      return Container(
        height: forcedHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor.withOpacity(0.6), width: 0.8),
        ),
        child: const Text('Sin mapa disponible'),
      );
    }

    final map = FlutterMap(
      key: ValueKey(keyStr),
      options: MapOptions(
        initialCenter: punto,
        initialZoom: _isWebWide(context) ? 15.5 : 16,
        // En web conviene permitir interacción completa
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.seguimientomapacnt',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: punto,
              width: 80,
              height: 80,
              child: const Icon(Icons.location_on, size: 40, color: Colors.red),
            ),
            if (_noticia.llegadaLatitud != null && _noticia.llegadaLongitud != null)
              Marker(
                point: latlng.LatLng(
                  _noticia.llegadaLatitud!,
                  _noticia.llegadaLongitud!,
                ),
                width: 80,
                height: 80,
                child: const Icon(Icons.no_crash_sharp, size: 38, color: Color.fromARGB(255, 30, 85, 204)),
              ),
          ],
        ),
      ],
    );

    return SizedBox(
      height: forcedHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned.fill(child: map),
            // En web, un pequeño “hint”
            if (kIsWeb)
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: theme.dividerColor.withOpacity(0.6),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    'Arrastra / rueda para zoom',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ===================== Build =====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = _isWebWide(context);

    final tieneCoordenadas = _tieneCoordenadas;
    final int cambios = _noticia.fechaCitaCambios ?? 0;
    final bool limiteCambiosFecha = (widget.role == 'reportero') && cambios >= 2;
    final bool esAdmin = widget.role == 'admin';
    final bool rutaYaIniciada = _noticia.rutaIniciada == true;

    final routeGate = (!esAdmin && !_soloLectura && !rutaYaIniciada)
        ? _validarInicioRuta()
        : (allowed: true, message: null);

    final domicilio = (_noticia.domicilio ?? '').trim();
    final domicilioTxt = domicilio.isNotEmpty ? domicilio : 'Sin domicilio';

    final nombreReportero = (_noticia.reportero.trim().isNotEmpty)
        ? _noticia.reportero.trim()
        : 'Sin reportero asignado';

    latlng.LatLng? punto;
    if (tieneCoordenadas) {
      punto = latlng.LatLng(_noticia.latitud!, _noticia.longitud!);
    }

    final detallesCard = Card(
      elevation: kIsWeb ? 0.6 : 2,
      shape: _softShape(theme),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_noticia.noticia, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Reportero: $nombreReportero',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (_noticia.descripcion != null && _noticia.descripcion!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(_noticia.descripcion!, style: theme.textTheme.bodyMedium),
              ),
            if (_noticia.cliente != null && _noticia.cliente!.trim().isNotEmpty)
              Text('Cliente: ${_noticia.cliente}'),
            const SizedBox(height: 4),

            // Domicilio (copy)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InkWell(
                    onLongPress: (!kIsWeb && domicilio.isNotEmpty)
                        ? () async {
                            await Clipboard.setData(ClipboardData(text: domicilio));
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Domicilio copiado')),
                            );
                          }
                        : null,
                    child: Text(
                      'Domicilio: $domicilioTxt',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Copiar domicilio',
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: domicilio.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: domicilio));
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Domicilio copiado')),
                          );
                        },
                ),
              ],
            ),

            if (_noticia.ultimaMod != null) ...[
              const SizedBox(height: 4),
              Text(
                'Última modificación: ${_formatearFechaHora(_noticia.ultimaMod!)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey[700],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            const SizedBox(height: 8),
            Text(
              'Fecha de cita: '
              '${_noticia.fechaCita != null ? _formatearFechaCitaAmPm(_noticia.fechaCita!) : 'Sin fecha de cita'}',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),

            if (_noticia.fechaCitaAnterior != null &&
                _noticia.fechaCita != null &&
                _noticia.fechaCitaAnterior!.toIso8601String() !=
                    _noticia.fechaCita!.toIso8601String()) ...[
              const SizedBox(height: 4),
              Text(
                'Fecha de cita anterior: ${_formatearFechaHora(_noticia.fechaCitaAnterior!)}',
                style: const TextStyle(
                  color: Color.fromARGB(255, 54, 117, 244),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],

            if (_noticia.horaLlegada != null) ...[
              const SizedBox(height: 4),
              Text(
                'Hora de llegada: ${_formatearFechaCitaAmPm(_noticia.horaLlegada!)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _colorHoraLlegada() ?? Colors.grey[700],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // ---------- Editar noticia ----------
            if (limiteCambiosFecha) ...[
              const SizedBox(height: 6),
              const Text(
                'Límite alcanzado: ya no puedes cambiar la fecha de cita.',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
              ),
            ],

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text('Editar noticia'),
                onPressed: (_soloLectura || limiteCambiosFecha)
                    ? null
                    : () async {
                        final updated = await Navigator.push<Noticia>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EditarNoticiaPage(
                              noticia: _noticia,
                              role: widget.role,
                            ),
                          ),
                        );

                        if (updated != null && mounted) {
                          setState(() => _noticia = updated);
                        }
                      },
              ),
            ),



            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_soloLectura || _yaTieneHoraLlegada) ? null : _abrirMapaUbicacion,
                icon: Icon(
                  tieneCoordenadas ? Icons.edit_location_alt : Icons.add_location_alt,
                ),
                label: Text(
                  _yaTieneHoraLlegada
                      ? 'Ubicación bloqueada'
                      : (tieneCoordenadas ? 'Editar ubicación' : 'Agregar ubicación'),
                ),
              ),
            ),

            if (tieneCoordenadas) ...[
              const SizedBox(height: 10),

              // ---------------- ADMIN ----------------
              if (esAdmin) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.visibility),
                    label: const Text('Ser espectador de ruta'),
                    onPressed: _soloLectura
                        ? null
                        : () async {
                            final changed = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EspectadorRutaPage(
                                  noticiaId: _noticia.id,
                                  destinoLat: _noticia.latitud!,
                                  destinoLon: _noticia.longitud!,
                                  wsUrl: ApiService.wsBaseUrl,
                                  wsToken: ApiService.wsToken,
                                ),
                              ),
                            );

                            if (!mounted) return;
                            if (changed == true) {
                              await _refrescarNoticia();
                            }
                          },
                  ),
                ),

                if (_soloLectura) ...[
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Esta noticia está cerrada.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ]

              // ---------------- REPORTERO ----------------
              else ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: (!_soloLectura && rutaYaIniciada)
                        ? ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                          )
                        : null,
                    icon: Icon(_soloLectura
                        ? Icons.map
                        : (rutaYaIniciada ? Icons.play_arrow : Icons.directions)),
                    label: Text(
                      _soloLectura
                          ? 'Mostrar mapa completo'
                          : (rutaYaIniciada ? 'Continuar ruta' : 'Iniciar ruta'),
                      textAlign: TextAlign.center,
                    ),
                    onPressed: _soloLectura
                        ? () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MapaCompletoPage(noticia: _noticia),
                              ),
                            );
                          }
                        : (routeGate.allowed
                            ? () async {
                                // 1) marcar inicio solo si es primera vez
                                if (!rutaYaIniciada) {
                                  try {
                                    final updated = await ApiService.marcarRutaIniciada(
                                      noticiaId: _noticia.id,
                                      role: widget.role,
                                    );
                                    if (!mounted) return;
                                    setState(() => _noticia = updated);
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('No se pudo iniciar ruta: $e')),
                                    );
                                    return;
                                  }
                                }

                                // 2) abrir trayecto
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TrayectoRutaPage(
                                      noticia: _noticia,
                                      wsToken: ApiService.wsToken,
                                      wsBaseUrl: ApiService.wsBaseUrl,
                                    ),
                                  ),
                                );

                                if (!mounted) return;
                                if (result == null) return;

                                DateTime _parseMysqlDateTime(String? v) {
                                  if (v == null || v.trim().isEmpty) return DateTime.now();
                                  final s = v.trim().replaceFirst(' ', 'T');
                                  return DateTime.tryParse(s) ?? DateTime.now();
                                }

                                final Map<String, dynamic> r = Map<String, dynamic>.from(result as Map);
                                final lat = (r['llegadaLatitud'] as num?)?.toDouble();
                                final lon = (r['llegadaLongitud'] as num?)?.toDouble();
                                final horaStr = r['horaLlegada']?.toString();
                                final hora = _parseMysqlDateTime(horaStr);

                                if (lat != null && lon != null) {
                                  setState(() {
                                    _noticia = Noticia(
                                      id: _noticia.id,
                                      noticia: _noticia.noticia,
                                      descripcion: _noticia.descripcion,
                                      cliente: _noticia.cliente,
                                      domicilio: _noticia.domicilio,
                                      reportero: _noticia.reportero,
                                      fechaCita: _noticia.fechaCita,
                                      fechaCitaAnterior: _noticia.fechaCitaAnterior,
                                      fechaCitaCambios: _noticia.fechaCitaCambios,
                                      fechaPago: _noticia.fechaPago,
                                      latitud: _noticia.latitud,
                                      longitud: _noticia.longitud,
                                      horaLlegada: hora,
                                      llegadaLatitud: lat,
                                      llegadaLongitud: lon,
                                      pendiente: _noticia.pendiente,
                                      ultimaMod: DateTime.now(),

                                      rutaIniciada: _noticia.rutaIniciada,
                                      rutaIniciadaAt: _noticia.rutaIniciadaAt,
                                    );
                                  });
                                }
                              }
                            : null),
                  ),
                ),

                if (!_soloLectura && !routeGate.allowed && routeGate.message != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    routeGate.message!,
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],

              if (!_soloLectura &&
                  _noticia.llegadaLatitud != null &&
                  _noticia.llegadaLongitud != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: _eliminando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(_eliminando ? 'Eliminando...' : 'Eliminar de mis pendientes'),
                    onPressed: _eliminando ? null : _onEliminarPendientePressed,
                  ),
                ),
              ],
            ] else ...[
              const SizedBox(height: 8),
              const Text(
                'No hay coordenadas para mostrar en el mapa.',
                style: TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );

    // ---- WEB WIDE: 2 columnas (detalle + mapa grande) ----
    if (wide) {
      final left = _maybeScrollbar(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(_hPad(context), 12, 0, 12),
          child: detallesCard,
        ),
      );

      final right = Padding(
        padding: EdgeInsets.fromLTRB(12, 12, _hPad(context), 12),
        child: Card(
          elevation: 0.6,
          shape: _softShape(theme),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.map),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Mapa',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.fullscreen),
                      label: const Text('Mapa completo'),
                      onPressed: !tieneCoordenadas
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MapaCompletoPage(noticia: _noticia),
                                ),
                              );
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _buildMapWidget(
                    tieneCoordenadas: tieneCoordenadas,
                    punto: punto,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      return Scaffold(
        appBar: AppBar(
          title: const Text('Panel de Detalles'),
          actions: [
            if (esAdmin)
              IconButton(
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh),
                onPressed: _refrescarNoticia,
              ),
          ],
        ),
        body: _wrapWebWidth(
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 7, child: left),
              Expanded(flex: 5, child: right),
            ],
          ),
        ),
      );
    }

    // ---- NARROW ----
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Detalles'),
        actions: [
          if (esAdmin)
            IconButton(
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh),
              onPressed: _refrescarNoticia,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refrescarNoticia,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(_hPad(context)),
                child: detallesCard,
              ),
            ),
          ),

          SizedBox(
            height: 200,
            child: Padding(
              padding: EdgeInsets.all(_hPad(context)),
              child: _buildMapWidget(
                tieneCoordenadas: tieneCoordenadas,
                punto: punto,
                forcedHeight: 200,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
