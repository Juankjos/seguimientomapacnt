import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:web_socket_channel/web_socket_channel.dart';

class EspectadorRutaPage extends StatefulWidget {
  final int noticiaId;
  final double destinoLat;
  final double destinoLon;

  final String wsUrl;   // ej: ws://167.99.163.209:3001
  final String wsToken; // token del login

  const EspectadorRutaPage({
    super.key,
    required this.noticiaId,
    required this.destinoLat,
    required this.destinoLon,
    required this.wsUrl,
    required this.wsToken,
  });

  @override
  State<EspectadorRutaPage> createState() => _EspectadorRutaPageState();
}

class _EspectadorRutaPageState extends State<EspectadorRutaPage> {
  final MapController _map = MapController();

  WebSocketChannel? _ws;

  bool _conectado = false;
  String? _error;

  // Estado “ruta en curso”
  bool _hayRutaEnCurso = false;
  int? _sessionId; // session actual para esa noticia

  // Para no spamear diálogos
  bool _dialogNoRutaMostrado = false;

  final List<latlng.LatLng> _puntos = [];
  latlng.LatLng? _ultimo;
  late final latlng.LatLng _destino;

  bool _seguirReportero = true;

  @override
  void initState() {
    super.initState();
    _destino = latlng.LatLng(widget.destinoLat, widget.destinoLon);
    _connect();
  }

  @override
  void dispose() {
    try { _ws?.sink.close(); } catch (_) {}
    _ws = null;
    super.dispose();
  }

  void _connect() {
    setState(() {
      _error = null;
      _conectado = false;
      _hayRutaEnCurso = false;
      _sessionId = null;
      _puntos.clear();
      _ultimo = null;
      _dialogNoRutaMostrado = false;
    });

    try {
      final base = Uri.parse(widget.wsUrl);

      // conserva query existente y agrega token
      final uri = base.replace(queryParameters: {
        ...base.queryParameters,
        'token': widget.wsToken,
      });

      _ws = WebSocketChannel.connect(uri);

      _ws!.stream.listen(
        (event) {
          Map<String, dynamic>? msg;
          try {
            msg = jsonDecode(event as String) as Map<String, dynamic>;
          } catch (_) {
            return;
          }

          final type = msg['type']?.toString();

          // 1) Confirmar conexión real (authed)
          if (type == 'authed') {
            setState(() {
              _conectado = true;
            });

            // 2) Pedir sesiones activas
            _sendSubscribeAll();
            return;
          }

          // 3) Lista inicial de sesiones activas
          if (type == 'active_sessions') {
            final sessions = (msg['sessions'] as List?) ?? [];

            final match = sessions.cast<dynamic>().map((e) {
              return (e as Map).map((k, v) => MapEntry(k.toString(), v));
            }).firstWhere(
              (s) => (s['noticia_id'] as num?)?.toInt() == widget.noticiaId,
              orElse: () => <String, dynamic>{},
            );

            if (match.isNotEmpty) {
              final sid = (match['session_id'] as num?)?.toInt();
              final lastLat = (match['last_lat'] as num?)?.toDouble();
              final lastLon = (match['last_lon'] as num?)?.toDouble();

              setState(() {
                _hayRutaEnCurso = true;
                _sessionId = sid;
                _dialogNoRutaMostrado = false;
              });

              // Sembrar última posición (si existe)
              if (lastLat != null && lastLon != null) {
                final p = latlng.LatLng(lastLat, lastLon);
                _puntos.add(p);
                _ultimo = p;
                _moveIfFollowing(p);
                setState(() {});
              }
            } else {
              setState(() {
                _hayRutaEnCurso = false;
                _sessionId = null;
              });
              _mostrarDialogNoRutaSiAplica();
            }

            return;
          }

          // 4) Cuando el reportero inicia trayecto (llega a TODOS los admins)
          if (type == 'tracking_started') {
            final noticiaId = (msg['noticia_id'] as num?)?.toInt();
            if (noticiaId != widget.noticiaId) return;

            final sid = (msg['session_id'] as num?)?.toInt();

            setState(() {
              _hayRutaEnCurso = true;
              _sessionId = sid;
              _puntos.clear();
              _ultimo = null;
            });

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reportero con trayecto en curso')),
              );
            }
            return;
          }

          // 5) Ubicación en vivo (llega a TODOS los admins) → filtrar por session_id/noticia_id
          if (type == 'tracking_location') {
            // preferente por session_id (más exacto)
            final sid = (msg['session_id'] as num?)?.toInt();
            final noticiaId = (msg['noticia_id'] as num?)?.toInt();

            if (_sessionId != null) {
              if (sid != _sessionId) return;
            } else {
              // fallback: si aún no tengo sessionId, filtro por noticiaId
              if (noticiaId != widget.noticiaId) return;
            }

            final lat = (msg['lat'] as num?)?.toDouble();
            final lon = (msg['lon'] as num?)?.toDouble();
            if (lat == null || lon == null) return;

            final p = latlng.LatLng(lat, lon);

            if (_puntos.isNotEmpty) {
              final last = _puntos.last;
              if (last.latitude == p.latitude && last.longitude == p.longitude) {
                return;
              }
            }

            // si empieza a llegar ubicación, definitivamente hay ruta
            if (!_hayRutaEnCurso) {
              setState(() => _hayRutaEnCurso = true);
            }

            _puntos.add(p);
            _ultimo = p;

            if (_puntos.length > 800) {
              _puntos.removeRange(0, _puntos.length - 800);
            }

            _moveIfFollowing(p);
            setState(() {});
            return;
          }

          // 6) Fin del trayecto
          if (type == 'tracking_stopped') {
            final sid = (msg['session_id'] as num?)?.toInt();
            if (_sessionId != null && sid != _sessionId) return;

            setState(() {
              _hayRutaEnCurso = false;
              _sessionId = null;
            });

            _mostrarDialogNoRutaSiAplica();
            return;
          }
        },
        onError: (e) {
          setState(() => _error = 'WS error: $e');
        },
        onDone: () {
          setState(() => _error = 'Conexión cerrada');
        },
      );
    } catch (e) {
      setState(() => _error = 'No se pudo conectar: $e');
    }
  }

  void _sendSubscribeAll() {
    try {
      _ws?.sink.add(jsonEncode({'type': 'subscribe_all'}));
    } catch (_) {}
  }

  void _mostrarDialogNoRutaSiAplica() {
    if (!mounted) return;
    if (_dialogNoRutaMostrado) return;
    _dialogNoRutaMostrado = true;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Estado de ruta'),
        content: const Text('Aún no hay una ruta en curso.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Seguir esperando'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // salir de espectador
            },
            child: const Text('Salir'),
          ),
        ],
      ),
    );
  }

  void _moveIfFollowing(latlng.LatLng p) {
    if (!_seguirReportero) return;
    _map.move(p, 17.0);
  }

  void _toggleFollow() {
    setState(() {
      _seguirReportero = !_seguirReportero;
    });
    if (_seguirReportero && _ultimo != null) {
      _map.move(_ultimo!, 17.0);
    }
  }

  void _verTodo() {
    if (_puntos.isEmpty && _ultimo == null) return;

    final all = <latlng.LatLng>[
      ..._puntos,
      if (_ultimo != null) _ultimo!,
      _destino,
    ];

    double minLat = all.first.latitude, maxLat = all.first.latitude;
    double minLon = all.first.longitude, maxLon = all.first.longitude;

    for (final p in all) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    final center = latlng.LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);
    _map.move(center, 13.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final destino = _destino;

    final tituloEstado = _hayRutaEnCurso
        ? 'Reportero con trayecto en curso'
        : 'Aún no hay una ruta en curso';

    final subtitulo = !_conectado
        ? 'Conectando…'
        : (_hayRutaEnCurso
            ? (_ultimo == null ? 'Esperando ubicación del reportero…' : 'En vivo • puntos: ${_puntos.length}')
            : 'En espera');

    return Scaffold(
      appBar: AppBar(
        title: Text('Espectador: Ruta #${widget.noticiaId}'),
        actions: [
          IconButton(
            tooltip: _seguirReportero ? 'Dejar de seguir' : 'Seguir reportero',
            onPressed: _toggleFollow,
            icon: Icon(_seguirReportero ? Icons.gps_off : Icons.gps_fixed),
          ),
          IconButton(
            tooltip: 'Ver todo',
            onPressed: _verTodo,
            icon: const Icon(Icons.alt_route),
          ),
          IconButton(
            tooltip: 'Reconectar',
            onPressed: _connect,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _ultimo ?? destino,
                    initialZoom: 13,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.seguimientomapacnt',
                    ),
                    PolylineLayer(
                      polylines: [
                        if (_puntos.length >= 2)
                          Polyline(
                            points: _puntos,
                            strokeWidth: 4,
                            color: theme.colorScheme.primary,
                          ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: destino,
                          width: 44,
                          height: 44,
                          child: const Icon(Icons.location_on, color: Colors.red, size: 36),
                        ),
                        if (_ultimo != null)
                          Marker(
                            point: _ultimo!,
                            width: 44,
                            height: 44,
                            child: const Icon(Icons.directions_run, color: Colors.blue, size: 34),
                          ),
                      ],
                    ),
                  ],
                ),

                // overlay estado (2 líneas)
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.62),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tituloEstado,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitulo,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
