import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as latlng;

import '../models/noticia.dart';
import '../services/api_service.dart';
import 'mapa_ubicacion_page.dart';
import 'trayecto_ruta_page.dart';
import 'mapa_completo_page.dart';

class NoticiaDetallePage extends StatefulWidget {
  final Noticia noticia;
  final bool soloLectura;

  const NoticiaDetallePage({
    super.key,
    required this.noticia,
    this.soloLectura = false,
  });

  @override
  State<NoticiaDetallePage> createState() => _NoticiaDetallePageState();
}

class _NoticiaDetallePageState extends State<NoticiaDetallePage> {
  late Noticia _noticia;
  bool _eliminando = false;
  bool get _soloLectura => widget.soloLectura || _noticia.pendiente == false;

  String _formatearFechaHora(DateTime dt) {
    return DateFormat("d 'de' MMMM 'de' y, HH:mm", 'es_MX').format(dt);
  }

  String _formatearFechaCitaAmPm(DateTime dt) {
    final fecha = DateFormat("d 'de' MMMM 'del' y", 'es_MX').format(dt);
    final hora = DateFormat("h:mm a", 'en_US').format(dt).toLowerCase(); // am/pm
    return '$fecha, $hora';
  }

  @override
  void initState() {
    super.initState();
    _noticia = widget.noticia;
  }

  String _formatearFecha(DateTime fecha) {
    final formatter = DateFormat("d 'de' MMMM 'del' y", 'es_MX');
    return formatter.format(fecha);
  }

  bool get _tieneCoordenadas =>
      _noticia.latitud != null && _noticia.longitud != null;

  Future<void> _abrirMapaUbicacion() async {
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
            fechaPago: _noticia.fechaPago,
            latitud: lat,
            longitud: lon,
            horaLlegada: _noticia.horaLlegada,
            llegadaLatitud: _noticia.llegadaLatitud,
            llegadaLongitud: _noticia.llegadaLongitud,
            pendiente: _noticia.pendiente,
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
          content: const Text(
            '¿Seguro que deseas eliminar este pendiente?',
          ),
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
    setState(() {
      _eliminando = true;
    });

    try {
      await ApiService.eliminarNoticiaDePendientes(widget.noticia.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Noticia eliminada de tus pendientes.'),
        ),
      );

      // Cerramos la pantalla de detalle para que ya no la veas
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar pendiente: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _eliminando = false;
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final tieneCoordenadas = _tieneCoordenadas;

    latlng.LatLng? punto;
    if (tieneCoordenadas) {
      punto = latlng.LatLng(_noticia.latitud!, _noticia.longitud!);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Panel de Detalles'),
      ),
      body: Column(
        children: [
          // ------- Datos arriba -------
          Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _noticia.noticia,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),

                      if (_noticia.descripcion != null &&
                          _noticia.descripcion!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text(
                            _noticia.descripcion!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),

                      if (_noticia.cliente != null && _noticia.cliente!.trim().isNotEmpty)
                      Text(
                        'Cliente: ${_noticia.cliente}',
                      ),
                      const SizedBox(height: 4),
                      Text('Domicilio: ${_noticia.domicilio ?? 'Sin domicilio'}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),

                      if (_noticia.ultimaMod != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Última modificación: ${_formatearFechaHora(_noticia.ultimaMod!)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[700],
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                      ],

                      const SizedBox(height: 8),
                      Text(
                        'Fecha de cita: '
                        '${_noticia.fechaCita != null ? _formatearFechaCitaAmPm(_noticia.fechaCita!) : 'Sin fecha de cita'}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4),

                      // Botón Agregar/Editar ubicación
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _soloLectura ? null : _abrirMapaUbicacion,
                      icon: Icon(
                        tieneCoordenadas
                            ? Icons.edit_location_alt
                            : Icons.add_location_alt,
                      ),
                      label: Text(
                        tieneCoordenadas
                            ? 'Editar ubicación'
                            : 'Agregar ubicación',
                      ),
                    ),
                  ),
                  if (_soloLectura) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Esta noticia está cerrada.',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ],
                  if (widget.noticia.latitud != null && widget.noticia.longitud != null)...[
                    const SizedBox(height: 8),

                    if (_noticia.latitud != null && _noticia.longitud != null) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: Icon(_soloLectura ? Icons.map : Icons.directions),
                          label: Text(_soloLectura ? 'Mostrar mapa completo' : 'Ir a destino ahora'),
                          onPressed: () {
                            if (_soloLectura) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MapaCompletoPage(noticia: _noticia),
                                ),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TrayectoRutaPage(noticia: _noticia),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],

                    // Mostrar sólo si ya tiene llegada_latitud y llegada_longitud
                    if (!_soloLectura &&
                      _noticia.llegadaLatitud != null &&
                      _noticia.llegadaLongitud != null) ...[
                        const SizedBox(height: 8),
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

                      const SizedBox(height: 8),
                      if (!tieneCoordenadas)
                        const Text(
                          'No hay coordenadas para mostrar en el mapa.',
                          style: TextStyle(color: Colors.red),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          SizedBox(
            height: 500,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: tieneCoordenadas && punto != null
                    ? FlutterMap(
                        key: ValueKey('${_noticia.latitud}-${_noticia.longitud}'),
                        options: MapOptions(
                          initialCenter: punto,
                          initialZoom: 16,
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
                                child: const Icon(
                                  Icons.location_on,
                                  size: 40,
                                  color: Colors.red,
                                ),
                              ),
                              if (_noticia.llegadaLatitud != null && _noticia.llegadaLongitud != null)
                              Marker(
                                point: latlng.LatLng(_noticia.llegadaLatitud!, _noticia.llegadaLongitud!),
                                width: 80,
                                height: 80,
                                child: const Icon(
                                  Icons.no_crash_sharp,
                                  size: 38,
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : const Center(
                        child: Text('Sin mapa disponible'),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
