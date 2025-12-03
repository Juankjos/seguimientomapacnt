import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as latlng;

import '../services/api_service.dart';

class DireccionSugerida {
  final String displayName;
  final double lat;
  final double lon;

  DireccionSugerida({
    required this.displayName,
    required this.lat,
    required this.lon,
  });
}

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
  final TextEditingController _searchController = TextEditingController();

  bool _cargando = false;
  bool _buscando = false;

  List<DireccionSugerida> _sugerencias = [];

  // Coordenadas de Tepatitlán de Morelos (centro visual inicial)
  // Aproximadamente 20.8169, -102.7635 
  final latlng.LatLng _tepaCenter =
      latlng.LatLng(20.8169, -102.7635);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    // Si ya hay ubicación, centramos ahí; si no, en Tepatitlán.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lat = widget.latitudInicial;
      final lon = widget.longitudInicial;

      if (lat != null && lon != null) {
        _mapController.move(latlng.LatLng(lat, lon), 16);
      } else {
        _mapController.move(_tepaCenter, 14);
      }

      // Si ya había domicilio, lo ponemos en el buscador
      if (widget.domicilioInicial != null &&
          widget.domicilioInicial!.trim().isNotEmpty) {
        _searchController.text = widget.domicilioInicial!;
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _buscarDirecciones(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _sugerencias = [];
      });
      return;
    }

    setState(() {
      _buscando = true;
    });

    try {
      // Limitamos búsqueda a Jalisco, México
      final params = {
        'format': 'jsonv2',
        'addressdetails': '1',
        'limit': '5',
        'q': '$query, Jalisco, Mexico',
        'countrycodes': 'mx',
        // bounding box aproximado de Jalisco (lon_min,lat_max,lon_max,lat_min)
        'viewbox': '-105.90,22.80,-101.60,18.90',
        'bounded': '1',
      };

      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        params,
      );

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'seguimientomapacnt/1.0 (tvc.s34rch@gmail.com)',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<DireccionSugerida> resultados = data.map((item) {
          final lat = double.tryParse(item['lat'].toString()) ?? 0.0;
          final lon = double.tryParse(item['lon'].toString()) ?? 0.0;
          final name = item['display_name']?.toString() ?? 'Sin nombre';
          return DireccionSugerida(
            displayName: name,
            lat: lat,
            lon: lon,
          );
        }).toList();

        setState(() {
          _sugerencias = resultados;
        });
      }
    } catch (e) {
      // Podrías mostrar un SnackBar si quieres
    } finally {
      if (mounted) {
        setState(() {
          _buscando = false;
        });
      }
    }
  }

  Future<void> _moverMapaADireccion(DireccionSugerida dir) async {
    setState(() {
      _sugerencias = [];
      _searchController.text = dir.displayName;
    });

    final destino = latlng.LatLng(dir.lat, dir.lon);
    _mapController.move(destino, 17);
  }

  Future<void> _guardarUbicacion() async {
    setState(() {
      _cargando = true;
    });

    try {
      final camera = _mapController.camera;
      final center = camera.center;  
      final lat = center.latitude;
      final lon = center.longitude;

      // Mandamos también el texto de domicilio (opcional)
      final domicilio = _searchController.text.trim();

      await ApiService.actualizarUbicacionNoticia(
        noticiaId: widget.noticiaId,
        latitud: lat,
        longitud: lon,
        domicilio: domicilio.isNotEmpty ? domicilio : null,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ubicación guardada correctamente'),
        ),
      );

      // Regresamos las coordenadas al caller
      Navigator.pop<Map<String, dynamic>>(
        context,
        {
          'lat': lat,
          'lon': lon,
          'domicilio': domicilio.isNotEmpty ? domicilio : null,
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
          // --------- Barra superior: PIN + búsqueda + sugerencias ----------
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Buscar domicilio (Jalisco)',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _buscando
                        ? const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _sugerencias = [];
                              });
                            },
                          ),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    _buscarDirecciones(value);
                  },
                ),
                if (_sugerencias.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 160),
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 4,
                          color: Colors.black.withOpacity(0.1),
                        ),
                      ],
                    ),
                    child: ListView.builder(
                      itemCount: _sugerencias.length,
                      itemBuilder: (context, index) {
                        final s = _sugerencias[index];
                        return ListTile(
                          title: Text(
                            s.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _moverMapaADireccion(s),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // --------- Mapa con mira en el centro ----------
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
                // Mira en el centro
                const Center(
                  child: IgnorePointer(
                    child: Icon(
                      Icons.add_location_alt,
                      size: 40,
                    ),
                  ),
                ),
                // Leyenda abajo
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