import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../models/noticia.dart';

class TrayectoRutaPage extends StatefulWidget {
  final Noticia noticia;

  const TrayectoRutaPage({
    super.key,
    required this.noticia,
  });

  @override
  State<TrayectoRutaPage> createState() => _TrayectoRutaPageState();
}

class _TrayectoRutaPageState extends State<TrayectoRutaPage> {
  final MapController _mapController = MapController();

  latlng.LatLng? _origen;
  late latlng.LatLng _destino;

  List<latlng.LatLng> _rutaPuntos = [];

  bool _cargando = true;
  String? _error;

  bool _mapIsReady = false;

  // Seguimiento de la ubicación del usuario
  bool _seguirUsuario = false;
  StreamSubscription<Position>? _posicionSub;

  // Zoom cercano para ver calles
  static const double _zoomSeguir = 17.0;

  @override
  void initState() {
    super.initState();

    if (widget.noticia.latitud == null ||
        widget.noticia.longitud == null) {
      _error = 'La noticia no tiene coordenadas de destino.';
      _cargando = false;
    } else {
      _destino = latlng.LatLng(
        widget.noticia.latitud!,
        widget.noticia.longitud!,
      );
      _inicializarRuta();
    }
  }

  @override
  void dispose() {
    _posicionSub?.cancel();
    super.dispose();
  }

  Future<void> _inicializarRuta() async {
    try {
      final origenPos = await _obtenerUbicacionActual();
      if (origenPos == null) {
        setState(() {
          _error = 'No se pudo obtener la ubicación actual.';
          _cargando = false;
        });
        return;
      }

      _origen = latlng.LatLng(origenPos.latitude, origenPos.longitude);

      final puntos = await _solicitarRutaOSRM(_origen!, _destino);

      setState(() {
        _rutaPuntos = puntos;
        _cargando = false;
      });

      if (_mapIsReady) {
        _moverMapaInicial();
      }
    } catch (e) {
      setState(() {
        _error = 'Error al calcular ruta: $e';
        _cargando = false;
      });
    }
  }

  Future<Position?> _obtenerUbicacionActual() async {
    bool servicioHabilitado = await Geolocator.isLocationServiceEnabled();
    if (!servicioHabilitado) {
      return null;
    }

    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) {
        return null;
      }
    }

    if (permiso == LocationPermission.deniedForever) {
      return null;
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    return pos;
  }

  Future<List<latlng.LatLng>> _solicitarRutaOSRM(
    latlng.LatLng origen,
    latlng.LatLng destino,
  ) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${origen.longitude},${origen.latitude};'
      '${destino.longitude},${destino.latitude}'
      '?overview=full&geometries=geojson',
    );

    final resp = await http.get(url);
    if (resp.statusCode != 200) {
      throw Exception('OSRM respondió con código ${resp.statusCode}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;

    if (data['routes'] == null || (data['routes'] as List).isEmpty) {
      throw Exception('No se encontró una ruta entre los puntos.');
    }

    final route = data['routes'][0];
    final geometry = route['geometry'];
    if (geometry == null || geometry['coordinates'] == null) {
      throw Exception('Respuesta de ruta inválida.');
    }

    final List coords = geometry['coordinates'];
    final List<latlng.LatLng> puntos = [];
    for (var c in coords) {
      if (c is List && c.length >= 2) {
        final lon = (c[0] as num).toDouble();
        final lat = (c[1] as num).toDouble();
        puntos.add(latlng.LatLng(lat, lon));
      }
    }

    return puntos;
  }

  // Se llama cuando el mapa ya está listo
  void _moverMapaInicial() {
    if (!_mapIsReady || _origen == null) return;

    if (_rutaPuntos.isNotEmpty) {
      _ajustarMapaBounds();
    } else {
      final center = latlng.LatLng(
        (_origen!.latitude + _destino.latitude) / 2,
        (_origen!.longitude + _destino.longitude) / 2,
      );
      _mapController.move(center, 13);
    }
  }

  void _ajustarMapaBounds() {
    if (_origen == null) return;
    final allPoints = [..._rutaPuntos, _origen!, _destino];

    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLon = allPoints.first.longitude;
    double maxLon = allPoints.first.longitude;

    for (final p in allPoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    final center = latlng.LatLng(
      (minLat + maxLat) / 2,
      (minLon + maxLon) / 2,
    );

    _mapController.move(center, 13);
  }

  // --------- Seguimiento de usuario (centrar cerca) ---------

  Future<void> _toggleSeguirUsuario() async {
    if (_seguirUsuario) {
      // Apagar seguimiento
      setState(() {
        _seguirUsuario = false;
      });
      _posicionSub?.cancel();
      _posicionSub = null;
      return;
    }

    // Encender seguimiento
    if (_origen == null) {
      final pos = await _obtenerUbicacionActual();
      if (pos == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo obtener la ubicación actual.'),
          ),
        );
        return;
      }
      _origen = latlng.LatLng(pos.latitude, pos.longitude);
    }

    setState(() {
      _seguirUsuario = true;
    });

    // Centrar inmediatamente con zoom cercano
    if (_mapIsReady && _origen != null) {
      _mapController.move(_origen!, _zoomSeguir);
    }

    // Iniciar stream de posición
    _posicionSub?.cancel();
    _posicionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5, // metros para actualizar
      ),
    ).listen((pos) {
      _origen = latlng.LatLng(pos.latitude, pos.longitude);
      if (_mapIsReady && _seguirUsuario && _origen != null) {
        // Seguimos al usuario con zoom cercano
        _mapController.move(_origen!, _zoomSeguir);
      }
      setState(() {}); // para redibujar marker de origen
    });
  }

  void _verRutaCompleta() {
    if (!_mapIsReady) return;
    if (_origen == null && _rutaPuntos.isEmpty) return;

    if (_rutaPuntos.isNotEmpty) {
      _ajustarMapaBounds();
    } else if (_origen != null) {
      final center = latlng.LatLng(
        (_origen!.latitude + _destino.latitude) / 2,
        (_origen!.longitude + _destino.longitude) / 2,
      );
      _mapController.move(center, 13);
    }
  }

  void _centrarEnDestino() {
    if (!_mapIsReady) return;
    _mapController.move(_destino, _zoomSeguir);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ruta hacia el destino'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _buildMapa(theme),
    );
  }

  Widget _buildMapa(ThemeData theme) {
    if (_origen == null) {
      return const Center(
        child: Text('No se pudo obtener la ubicación actual.'),
      );
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _origen!,
            initialZoom: 13,
            onMapReady: () {
              _mapIsReady = true;
              _moverMapaInicial();
            },
            // Cuando seguimos al usuario, bloqueamos drag pero dejamos zoom
            interactionOptions: InteractionOptions(
              flags: _seguirUsuario
                  ? InteractiveFlag.pinchZoom |
                      InteractiveFlag.doubleTapZoom |
                      InteractiveFlag.scrollWheelZoom
                  : InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName:
                  'com.example.seguimientomapacnt',
            ),
            PolylineLayer(
              polylines: [
                if (_rutaPuntos.isNotEmpty)
                  Polyline(
                    points: _rutaPuntos,
                    strokeWidth: 4,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
            MarkerLayer(
              markers: [
                if (_origen != null)
                  Marker(
                    point: _origen!,
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.my_location,
                      color: Colors.blue,
                      size: 30,
                    ),
                  ),
                Marker(
                  point: _destino,
                  width: 40,
                  height: 40,
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 36,
                  ),
                ),
              ],
            ),
          ],
        ),

        // --------- Botones flotantes (Seguir / Ruta / Destino) ---------
        Positioned(
          top: 16,
          right: 16,
          child: Column(
            children: [
              // CENTRAR / SEGUIR
              FloatingActionButton.small(
                heroTag: 'centrar_btn',
                onPressed: _toggleSeguirUsuario,
                tooltip: _seguirUsuario
                    ? 'Desactivar seguimiento'
                    : 'Centrar y seguir ubicación',
                child: Icon(
                  _seguirUsuario ? Icons.gps_off : Icons.gps_fixed,
                ),
              ),
              const SizedBox(height: 8),

              // VER RUTA COMPLETA (se deshabilita si seguimos al usuario)
              FloatingActionButton.small(
                heroTag: 'ruta_btn',
                onPressed: _seguirUsuario ? null : _verRutaCompleta,
                tooltip: 'Ver ruta completa',
                backgroundColor: _seguirUsuario
                    ? theme.disabledColor.withOpacity(0.3)
                    : null,
                foregroundColor: _seguirUsuario
                    ? theme.disabledColor
                    : null,
                child: const Icon(Icons.alt_route),
              ),
              const SizedBox(height: 8),

              // UBICAR DESTINO (se deshabilita si seguimos al usuario)
              FloatingActionButton.small(
                heroTag: 'destino_btn',
                onPressed: _seguirUsuario ? null : _centrarEnDestino,
                tooltip: 'Ubicar destino',
                backgroundColor: _seguirUsuario
                    ? theme.disabledColor.withOpacity(0.3)
                    : null,
                foregroundColor: _seguirUsuario
                    ? theme.disabledColor
                    : null,
                child: const Icon(Icons.place),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
