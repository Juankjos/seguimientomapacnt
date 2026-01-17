// lib/screens/espectador_ruta_page.dart
import 'dart:async';
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
  final String wsToken; // token (admin)

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
  StreamSubscription? _wsSub;

  Timer? _pollTimer;
  Timer? _reconnectTimer;
  bool _reconnecting = false;

  bool _conectado = false;
  String? _error;

  bool _hayRutaEnCurso = false;
  int? _sessionId;

  bool _dialogNoRutaMostrado = false;

  final List<latlng.LatLng> _puntos = [];
  latlng.LatLng? _ultimo;
  late final latlng.LatLng _destino;

  bool _seguirReportero = true;
  DateTime? _lastLocationAt;

  int _noSessionStreak = 0;

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  @override
  void initState() {
    super.initState();
    _destino = latlng.LatLng(widget.destinoLat, widget.destinoLon);
    unawaited(_connect());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    unawaited(_disposeWs());
    super.dispose();
  }

  Future<void> _disposeWs() async {
    await _wsSub?.cancel();
    _wsSub = null;

    try {
      await _ws?.sink.close();
    } catch (_) {}

    _ws = null;
    if (mounted) setState(() => _conectado = false);
  }

  Future<void> _connect() async {
    _reconnectTimer?.cancel();
    _pollTimer?.cancel();

    await _disposeWs();

    if (!mounted) return;
    setState(() {
      _error = null;
      _conectado = false;

      _hayRutaEnCurso = false;
      _sessionId = null;

      _puntos.clear();
      _ultimo = null;

      _dialogNoRutaMostrado = false;
      _lastLocationAt = null;

      _noSessionStreak = 0;
    });

    try {
      final base = Uri.parse(widget.wsUrl);
      final uri = base.replace(queryParameters: {
        ...base.queryParameters,
        'token': widget.wsToken,
      });

      final ch = WebSocketChannel.connect(uri);
      _ws = ch;

      _wsSub = ch.stream.listen(
        _onWsMessage,
        onError: (e) => _scheduleReconnect('WS error: $e'),
        onDone: () => _scheduleReconnect('Conexión cerrada'),
        cancelOnError: true,
      );

      await ch.ready.timeout(const Duration(seconds: 8));

      // poll cada 10s
      _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (_ws != null) _sendSubscribeAll();
        _watchdog();
      });
    } catch (e) {
      _scheduleReconnect('No se pudo conectar: $e');
    }
  }

  void _scheduleReconnect(String err) {
    if (!mounted) return;
    setState(() => _error = err);

    if (_reconnecting) return;
    _reconnecting = true;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () async {
      _reconnecting = false;
      if (!mounted) return;
      await _connect();
    });
  }

  void _sendSubscribeAll() {
    try {
      _ws?.sink.add(jsonEncode({'type': 'subscribe_all'}));
    } catch (_) {}
  }

  void _watchdog() {
    if (!_conectado) return;
    if (!_hayRutaEnCurso) return;

    final last = _lastLocationAt;
    if (last == null) return;

    final secs = DateTime.now().difference(last).inSeconds;

    if (secs >= 20) _sendSubscribeAll();
    if (secs >= 45) _scheduleReconnect('Sin ubicación nueva (${secs}s). Reconectando…');
  }

  void _onWsMessage(dynamic event) {
    try {
      final msg = jsonDecode(event as String) as Map<String, dynamic>;
      final type = msg['type']?.toString();

      if (type == 'authed') {
        if (!mounted) return;
        setState(() {
          _conectado = true;
          _error = null;
        });

        // pide inmediatamente
        _sendSubscribeAll();
        return;
      }

      if (type == 'active_sessions') {
        final sessions = (msg['sessions'] as List?) ?? [];

        Map<String, dynamic> match = <String, dynamic>{};

        for (final e in sessions) {
          if (e is! Map) continue;
          final s = e.map((k, v) => MapEntry(k.toString(), v));
          final noticia = _toInt(s['noticia_id']);
          if (noticia == widget.noticiaId) {
            match = s;
            break;
          }
        }

        if (match.isNotEmpty) {
          _noSessionStreak = 0;

          final sid = _toInt(match['session_id']);
          final lastLat = _toDouble(match['last_lat']);
          final lastLon = _toDouble(match['last_lon']);

          final sessionChanged = (sid != null && _sessionId != null && sid != _sessionId);
          if (sessionChanged) {
            _puntos.clear();
            _ultimo = null;
          }

          if (!mounted) return;
          setState(() {
            _hayRutaEnCurso = true;
            _sessionId = sid;
            _dialogNoRutaMostrado = false;
          });

          if (lastLat != null && lastLon != null) {
            final p = latlng.LatLng(lastLat, lastLon);

            final isNew = _ultimo == null ||
                _ultimo!.latitude != p.latitude ||
                _ultimo!.longitude != p.longitude;

            if (isNew) {
              _lastLocationAt = DateTime.now();

              _puntos.add(p);
              _ultimo = p;

              if (_puntos.length > 800) {
                _puntos.removeRange(0, _puntos.length - 800);
              }

              _moveIfFollowing(p);
              if (mounted) setState(() {});
            }
          }
        } else {
          _noSessionStreak++;

          if (!mounted) return;
          setState(() {
            _hayRutaEnCurso = false;
            _sessionId = null;
          });

          if (_noSessionStreak >= 3) _mostrarDialogNoRutaSiAplica();
        }
        return;
      }

      if (type == 'tracking_started') {
        final noticiaId = _toInt(msg['noticia_id']);
        if (noticiaId != widget.noticiaId) return;

        final sid = _toInt(msg['session_id']);

        if (!mounted) return;
        setState(() {
          _hayRutaEnCurso = true;
          _sessionId = sid;
          _puntos.clear();
          _ultimo = null;
          _dialogNoRutaMostrado = false;
          _lastLocationAt = null;
          _noSessionStreak = 0;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reportero con trayecto en curso')),
        );
        return;
      }

      if (type == 'tracking_location') {
        final sid = _toInt(msg['session_id']);
        final noticiaId = _toInt(msg['noticia_id']);

        if (_sessionId != null) {
          if (sid != _sessionId) return;
        } else {
          if (noticiaId != widget.noticiaId) return;
        }

        final lat = _toDouble(msg['lat']);
        final lon = _toDouble(msg['lon']);
        if (lat == null || lon == null) return;

        final p = latlng.LatLng(lat, lon);

        if (_puntos.isNotEmpty) {
          final last = _puntos.last;
          if (last.latitude == p.latitude && last.longitude == p.longitude) return;
        }

        _lastLocationAt = DateTime.now();

        if (!_hayRutaEnCurso) setState(() => _hayRutaEnCurso = true);

        _puntos.add(p);
        _ultimo = p;

        if (_puntos.length > 800) {
          _puntos.removeRange(0, _puntos.length - 800);
        }

        _moveIfFollowing(p);
        if (mounted) setState(() {});
        return;
      }

      if (type == 'tracking_stopped') {
        final sid = _toInt(msg['session_id']);
        if (_sessionId != null && sid != _sessionId) return;

        if (!mounted) return;
        setState(() {
          _hayRutaEnCurso = false;
          _sessionId = null;
        });

        _mostrarDialogNoRutaSiAplica();
        return;
      }

      if (type == 'error') {
        final m = msg['message']?.toString() ?? 'Error';
        _scheduleReconnect(m);
        return;
      }
    } catch (e, st) {
      debugPrint('WS message error: $e\n$st');
    }
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
              Navigator.pop(context);
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
    setState(() => _seguirReportero = !_seguirReportero);
    if (_seguirReportero && _ultimo != null) _map.move(_ultimo!, 17.0);
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
    setState(() => _seguirReportero = false);
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
            ? (_ultimo == null
                ? 'Esperando ubicación del reportero…'
                : 'En vivo • puntos: ${_puntos.length}')
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
            onPressed: () => unawaited(_connect()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => unawaited(_connect()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
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
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 36,
                          ),
                        ),
                        if (_ultimo != null)
                          Marker(
                            point: _ultimo!,
                            width: 44,
                            height: 44,
                            child: const Icon(
                              Icons.directions_run,
                              color: Colors.blue,
                              size: 34,
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
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
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _conectado ? Icons.wifi : Icons.wifi_off,
                          size: 14,
                          color: _conectado ? Colors.greenAccent : Colors.redAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _conectado ? 'Conectado' : 'Sin conexión',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
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
