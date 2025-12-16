import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlng;

import '../models/noticia.dart';

class MapaCompletoPage extends StatelessWidget {
  final Noticia noticia;

  const MapaCompletoPage({
    super.key,
    required this.noticia,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (noticia.latitud == null || noticia.longitud == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mapa')),
        body: const Center(child: Text('No hay coordenadas para mostrar.')),
      );
    }

    final destino = latlng.LatLng(noticia.latitud!, noticia.longitud!);
    final llegada = (noticia.llegadaLatitud != null && noticia.llegadaLongitud != null)
        ? latlng.LatLng(noticia.llegadaLatitud!, noticia.llegadaLongitud!)
        : null;

    // Centro y zoom: si hay llegada, mostramos un poco más abierto para ver ambos puntos
    final center = llegada ?? destino;
    final zoom = llegada != null ? 14.5 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa completo'),
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: center,
          initialZoom: zoom,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.seguimientomapacnt',
          ),
          MarkerLayer(
            markers: [
              // Destino (pin rojo)
              Marker(
                point: destino,
                width: 56,
                height: 56,
                child: const Icon(
                  Icons.location_on,
                  size: 42,
                  color: Colors.red,
                ),
              ),

              // Llegada (si existe)
              if (llegada != null)
                Marker(
                  point: llegada,
                  width: 56,
                  height: 56,
                  child: Icon(
                    Icons.no_crash_sharp,
                    size: 38,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
