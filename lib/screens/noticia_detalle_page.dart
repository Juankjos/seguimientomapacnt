//lib/screens/noticia_detalle_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlng;

import '../models/noticia.dart';

class NoticiaDetallePage extends StatelessWidget {
  final Noticia noticia;

  const NoticiaDetallePage({super.key, required this.noticia});

  String _formatearFecha(DateTime fecha) {
    final formatter = DateFormat("d 'de' MMMM 'del' y", 'es_MX');
    return formatter.format(fecha);
  }

  @override
  Widget build(BuildContext context) {
    final tieneCoordenadas =
        noticia.latitud != null && noticia.longitud != null;

    latlng.LatLng? punto;
    if (tieneCoordenadas) {
      punto = latlng.LatLng(noticia.latitud!, noticia.longitud!);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Detalles'),
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
                    noticia.noticia,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (noticia.cliente != null &&
                      noticia.cliente!.trim().isNotEmpty)
                    Text('Cliente: ${noticia.cliente}'),
                  const SizedBox(height: 4),
                  Text('Reportero: ${noticia.reportero}'),
                  const SizedBox(height: 4),
                  Text('Domicilio: ${noticia.domicilio}'),
                  const SizedBox(height: 8),
                  Text('Fecha de cita: ${_formatearFecha(noticia.fechaCita)}'),
                  const SizedBox(height: 4),
                  Text(
                    'Fecha de pago: '
                    '${noticia.fechaPago != null ? _formatearFecha(noticia.fechaPago!) : 'Sin pago registrado'}',
                  ),
                  const SizedBox(height: 16),
                  if (!tieneCoordenadas)
                    const Text(
                      'No hay coordenadas para mostrar en el mapa.',
                      style: TextStyle(color: Colors.red),
                    ),
                ],
              ),
            ),
          ),

          // ------- Mapa abajo con flutter_map -------
          SizedBox(
            height: 250,
            child: tieneCoordenadas && punto != null
                ? FlutterMap(
                    options: MapOptions(
                      initialCenter: punto,
                      initialZoom: 16,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
