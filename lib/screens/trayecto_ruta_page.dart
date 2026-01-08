// lib/screens/trayecto_ruta_page.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../models/noticia.dart';
import '../services/api_service.dart';
import '../services/tracking_task_handler.dart';

class TrayectoRutaPage extends StatefulWidget {
  final Noticia noticia;
  final String wsToken;
  final String wsBaseUrl;

  const TrayectoRutaPage({
    super.key,
    required this.noticia,
    required this.wsToken,
    required this.wsBaseUrl,
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

  StreamSubscription<Position>? _posicionSub;
  bool _streamIniciado = false;

  bool _followCamera = true;

  static const double _zoomSeguir = 17.0;

  bool _enviandoLlegada = false;

  bool _notificacionInicioEnviada = false;

  // Notificación a admin para inicio de trayecto
  Future<void> _notificarInicioTrayecto() async {
    if (_notificacionInicioEnviada) return;
    _notificacionInicioEnviada = true;

    try {
      final url = Uri.parse('${ApiService.baseUrl}/inicio_trayecto_noticia.php');

      final resp = await http.post(url, body: {
        'noticia_id': widget.noticia.id.toString(),
      });

      if (resp.statusCode != 200) {
        debugPrint('⚠️ inicio_trayecto_noticia: HTTP ${resp.statusCode} ${resp.body}');
        return;
      }

      final data = jsonDecode(resp.body);
      if (data is Map && data['success'] != true) {
        debugPrint('⚠️ inicio_trayecto_noticia error: ${data['message']}');
      }
    } catch (e) {
      debugPrint('⚠️ Error notificando inicio trayecto: $e');
    }
  }

  // ------------------- Navegación / salir -------------------

  Future<bool> _confirmarCancelarTrayecto() async {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancelar ruta'),
          content: const Text('¿Estás seguro que quieres cancelar la ruta?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Volver a trayecto'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sí Cancelar trayecto'),
            ),
          ],
        );
      },
    );
    return res == true;
  }

  Future<void> _cancelarTrackingYSalir() async {
    _posicionSub?.cancel();
    _posicionSub = null;

    if (!kIsWeb) {
      try {
        await FlutterForegroundTask.stopService();
      } catch (_) {}
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _onBackRequested() async {
    final confirmar = await _confirmarCancelarTrayecto();
    if (!confirmar) return;
    await _cancelarTrackingYSalir();
  }

  Future<void> _iniciarTrackingForeground() async {
    if (kIsWeb) return;

    final payload = {
      'ws_url': widget.wsBaseUrl,
      'token': widget.wsToken,
      'noticia_id': widget.noticia.id,
      'save_history': false,
    };

    await FlutterForegroundTask.saveData(
      key: 'tracking_payload',
      value: jsonEncode(payload),
    );

    await FlutterForegroundTask.startService(
      notificationTitle: 'Trayecto en curso',
      notificationText: 'Enviando ubicación cada 7s',
      callback: startCallback,
    );
  }

  // ------------------- ciclo de vida -------------------

  @override
  void initState() {
    super.initState();

    if (widget.noticia.latitud == null || widget.noticia.longitud == null) {
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

      await _iniciarTrackingForeground();

      unawaited(_notificarInicioTrayecto());

      _iniciarStreamUbicacion();

      _followCamera = true;

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

  // ------------------- ubicación -------------------

  Future<Position?> _obtenerUbicacionActual() async {
    final servicioHabilitado = await Geolocator.isLocationServiceEnabled();
    if (!servicioHabilitado) return null;

    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) return null;
    }

    if (permiso == LocationPermission.deniedForever) return null;

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  void _iniciarStreamUbicacion() {
    if (_streamIniciado) return;
    _streamIniciado = true;

    _posicionSub?.cancel();

    final settings = kIsWeb
        ? const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          )
        : AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
            intervalDuration: const Duration(seconds: 7),
          );

    _posicionSub = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen((pos) {
      _origen = latlng.LatLng(pos.latitude, pos.longitude);

      if (_mapIsReady && _followCamera && _origen != null) {
        _mapController.move(_origen!, _zoomSeguir);
      }

      if (mounted) setState(() {});
    });
  }

  // ------------------- ruta OSRM -------------------

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

  // ------------------- mapa / cámara -------------------

  void _moverMapaInicial() {
    if (!_mapIsReady || _origen == null) return;

    if (_rutaPuntos.isNotEmpty) {
      _ajustarMapaBounds();
    } else {
      _mapController.move(_origen!, 13);
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

  void _centrarEnMiUbicacion() {
    if (!_mapIsReady || _origen == null) return;
    setState(() => _followCamera = true);
    _mapController.move(_origen!, _zoomSeguir);
  }

  void _verRutaCompleta() {
    if (!_mapIsReady) return;
    if (_origen == null && _rutaPuntos.isEmpty) return;

    setState(() => _followCamera = false);

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
    setState(() => _followCamera = false);
    _mapController.move(_destino, _zoomSeguir);
  }

  // ------------------- finalizar trayecto -------------------

  Future<void> _onFinalizarTrayectoPressed() async {
    if (_enviandoLlegada) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Finalizar ruta'),
          content: const Text('¿Seguro que deseas finalizar la ruta?'),
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

    await _enviarLlegada();
  }

  Future<void> _enviarLlegada() async {
    setState(() {
      _enviandoLlegada = true;
    });

    try {
      final pos = await _obtenerUbicacionActual();
      if (pos == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo obtener la ubicación actual para registrar la llegada.',
            ),
          ),
        );
        return;
      }

      await ApiService.registrarLlegadaNoticia(
        noticiaId: widget.noticia.id,
        latitud: pos.latitude,
        longitud: pos.longitude,
      );

      await FlutterForegroundTask.stopService();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Trayecto finalizado y llegada registrada.'),
        ),
      );

      Navigator.pop(context, {
        'llegadaLatitud': pos.latitude,
        'llegadaLongitud': pos.longitude,
        'horaLlegada': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al registrar llegada: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _enviandoLlegada = false;
        });
      }
    }
  }

  // ------------------- UI -------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        unawaited(_onBackRequested());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ruta hacia el destino'),
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : _buildMapa(theme),
      ),
    );
  }
  Widget _buildMapa(ThemeData theme) {
    if (_origen == null) {
      return const Center(
        child: Text('No se pudo obtener la ubicación actual.'),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
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

                  onPositionChanged: (pos, hasGesture) {
                    if (hasGesture && _followCamera) {
                      setState(() => _followCamera = false);
                    }
                  },

                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.seguimientomapacnt',
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

              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.62),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _followCamera ? Icons.gps_fixed : Icons.touch_app,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _followCamera ? 'Siguiendo tu ubicación' : 'Explorando mapa',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Positioned(
                top: 16,
                right: 16,
                child: Column(
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'centrar_btn',
                      onPressed: _centrarEnMiUbicacion,
                      tooltip: _followCamera ? 'Mi ubicación (siguiendo)' : 'Mi ubicación',
                      child: Icon(_followCamera ? Icons.gps_fixed : Icons.gps_not_fixed),
                    ),
                    const SizedBox(height: 8),

                    FloatingActionButton.small(
                      heroTag: 'ruta_btn',
                      onPressed: _verRutaCompleta,
                      tooltip: 'Ver ruta completa',
                      child: const Icon(Icons.alt_route),
                    ),
                    const SizedBox(height: 8),

                    FloatingActionButton.small(
                      heroTag: 'destino_btn',
                      onPressed: _centrarEnDestino,
                      tooltip: 'Ubicar destino',
                      child: const Icon(Icons.place),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _enviandoLlegada
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.flag),
                label: Text(_enviandoLlegada ? 'Guardando...' : 'Finalizar trayecto'),
                onPressed: _enviandoLlegada ? null : _onFinalizarTrayectoPressed,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
