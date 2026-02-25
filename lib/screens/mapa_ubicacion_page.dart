// lib/screens/mapa_ubicacion_page.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as latlng;

import '../services/api_service.dart';

class MapaUbicacionPage extends StatefulWidget {
  final int noticiaId;
  final double? latitudInicial;
  final double? longitudInicial;
  final String? domicilioInicial;

  const MapaUbicacionPage({
    super.key,
    required this.noticiaId,
    this.latitudInicial,
    this.longitudInicial,
    this.domicilioInicial,
  });

  @override
  State<MapaUbicacionPage> createState() => _MapaUbicacionPageState();
}

class _MapaUbicacionPageState extends State<MapaUbicacionPage> {
  late final MapController _mapController;

  bool _cargando = false;

  // Centro visual inicial: Tepatitlán de Morelos
  final latlng.LatLng _tepaCenter = latlng.LatLng(20.8169, -102.7635);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lat = widget.latitudInicial;
      final lon = widget.longitudInicial;

      if (lat != null && lon != null) {
        _mapController.move(latlng.LatLng(lat, lon), 16);
      } else {
        _mapController.move(_tepaCenter, 14);
      }
    });
  }

  // 🔁 Reverse geocoding: de lat/lon a "Calle, CP Municipio"
  Future<String?> _obtenerDomicilioDesdeCoordenadas(
      double lat, double lon) async {
    try {
      final params = {
        'format': 'jsonv2',
        'lat': lat.toString(),
        'lon': lon.toString(),
        'addressdetails': '1',
        'accept-language': 'es',
        'zoom': '18',
      };

      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/reverse',
        params,
      );

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'seguimientomapacnt/1.0 (tvc.s34rch@gmail.com)',
        },
      );

      if (response.statusCode != 200) return null;

      final Map<String, dynamic> data = jsonDecode(response.body);

      final addr = data['address'] as Map<String, dynamic>? ?? {};

      final road = addr['road'] ??
          addr['pedestrian'] ??
          addr['footway'] ??
          addr['residential'];
      final house = addr['house_number'];
      final postcode = addr['postcode'];
      final city = addr['city'] ??
          addr['town'] ??
          addr['municipality'] ??
          addr['village'] ??
          addr['county'];

      String? parteCalle;
      if (road != null) {
        parteCalle = house != null ? '$road $house' : road.toString();
      }

      String? parteCP;
      if (postcode != null) {
        parteCP = postcode.toString();
      }

      String? parteMunicipio;
      if (city != null) {
        parteMunicipio = city.toString();
      }

      final partes = <String>[];
      if (parteCalle != null && parteCalle.trim().isNotEmpty) {
        partes.add(parteCalle);
      }
      if (parteCP != null && parteCP.trim().isNotEmpty) {
        partes.add(parteCP);
      }
      if (parteMunicipio != null && parteMunicipio.trim().isNotEmpty) {
        partes.add(parteMunicipio);
      }

      if (partes.isEmpty) {
        // Si no logramos formatear nada, intentamos usar display_name
        final raw = data['display_name']?.toString();
        return raw;
      }

      return partes.join(', ');
    } catch (_) {
      return null;
    }
  }

  Future<void> _guardarUbicacion() async {
    // 🔹 Paso 1: Confirmar
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Marcar destino'),
        content: const Text('¿Marcar este destino?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );

    if (confirmar != true) {
      // El usuario canceló
      return;
    }

    // 🔹 Paso 2: Guardar si confirmó
    setState(() {
      _cargando = true;
    });

    try {
      final camera = _mapController.camera;
      final center = camera.center;
      final lat = center.latitude;
      final lon = center.longitude;

      // Reverse geocoding: construye "Calle, CP Municipio"
      final ubicacion = await _obtenerDomicilioDesdeCoordenadas(lat, lon);

      await ApiService.actualizarUbicacionNoticia(
        noticiaId: widget.noticiaId,
        latitud: lat,
        longitud: lon,
        ubicacionEnMapa: ubicacion,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ubicacion != null
                ? 'Ubicación guardada:\n$ubicacion'
                : 'Ubicación guardada correctamente',
          ),
        ),
      );

      Navigator.pop<Map<String, dynamic>>(
        context,
        {
          'lat': lat,
          'lon': lon,
          'ubicacion_en_mapa': ubicacion,
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar ubicación: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleccionar ubicación'),
      ),
      body: Column(
        children: [
          // (Ya no hay barra de búsqueda, solo el mapa)
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _tepaCenter,
                    initialZoom: 14,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName:
                          'com.example.seguimientomapacnt',
                    ),
                  ],
                ),
                const Center(
                  child: IgnorePointer(
                    child: Icon(
                      Icons.add_location_alt,
                      size: 40,
                      color: Colors.red,
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Mueve el mapa y presiona "Marcar" para fijar la ubicación.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // --------- Botón MARCAR ----------
          SafeArea(
            top: false,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _cargando ? null : _guardarUbicacion,
                  icon: const Icon(Icons.check),
                  label: _cargando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Marcar'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}