import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as latlng;

import '../models/noticia.dart';
import 'mapa_ubicacion_page.dart';

class NoticiaDetallePage extends StatefulWidget {
  final Noticia noticia;

  const NoticiaDetallePage({super.key, required this.noticia});

  @override
  State<NoticiaDetallePage> createState() => _NoticiaDetallePageState();
}

class _NoticiaDetallePageState extends State<NoticiaDetallePage> {
  late Noticia _noticia;

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
          );
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
        title: Text('Noticia #${_noticia.id}'),
      ),
      body: Column(
        children: [
          // ------- Datos arriba -------
          Expanded(
            child: SingleChildScrollView(
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

                  if (_noticia.cliente != null &&
                      _noticia.cliente!.trim().isNotEmpty)
                    Text('Cliente: ${_noticia.cliente}'),
                  const SizedBox(height: 4),
                  Text('Reportero: ${_noticia.reportero}'),
                  const SizedBox(height: 4),
                  Text('Domicilio: ${_noticia.domicilio ?? 'Sin domicilio'}'),
                  const SizedBox(height: 8),
                  Text(
                    'Fecha de cita: '
                    '${_noticia.fechaCita != null ? _formatearFecha(_noticia.fechaCita!) : 'Sin fecha de cita'}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Fecha de pago: '
                    '${_noticia.fechaPago != null ? _formatearFecha(_noticia.fechaPago!) : 'Sin pago registrado'}',
                  ),
                  const SizedBox(height: 16),

                  // Botón Agregar/Editar ubicación
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _abrirMapaUbicacion,
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

                  const SizedBox(height: 8),
                  if (!tieneCoordenadas)
                    const Text(
                      'No hay coordenadas para mostrar en el mapa.',
                      style: TextStyle(color: Colors.red),
                    ),
                ],
              ),
            ),
          ),

          // ------- Mapa abajo (solo si hay ubicación) -------
          SizedBox(
            height: 250,
            child: tieneCoordenadas && punto != null
                ? FlutterMap(
                    key: ValueKey(
                        '${_noticia.latitud}-${_noticia.longitud}'), // fuerza reconstrucción
                    options: MapOptions(
                      initialCenter: punto,
                      initialZoom: 16,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName:
                            'com.example.seguimientomapacnt',
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
        ],
      ),
    );
  }
}
