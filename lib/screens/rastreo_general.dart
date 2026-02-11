// lib/screens/rastreo_general.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/api_service.dart';

const double _kWebMaxContentWidth = 1200;
const double _kWebWideBreakpoint = 980;

bool _isWebWide(BuildContext context) =>
    kIsWeb && MediaQuery.of(context).size.width >= _kWebWideBreakpoint;

double _hPad(BuildContext context) => _isWebWide(context) ? 20 : 16;

Widget _wrapWebWidth(Widget child) {
  if (!kIsWeb) return child;
  return Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _kWebMaxContentWidth),
      child: child,
    ),
  );
}

ShapeBorder _softShape(ThemeData theme) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: theme.dividerColor.withOpacity(0.70),
        width: 0.9,
      ),
    );

class _TrackInfo {
  _TrackInfo({
    required this.sessionId,
    required this.noticiaId,
  });

  final int sessionId;
  int noticiaId;

  final List<latlng.LatLng> puntos = [];
  latlng.LatLng? ultimo;
  DateTime? lastAt;

  int missingPolls = 0;

  int get total => puntos.length;

  void addPoint(latlng.LatLng p, {int maxPoints = 650}) {
    if (ultimo != null &&
        ultimo!.latitude == p.latitude &&
        ultimo!.longitude == p.longitude) {
      return;
    }
    puntos.add(p);
    ultimo = p;
    lastAt = DateTime.now();

    if (puntos.length > maxPoints) {
      puntos.removeRange(0, puntos.length - maxPoints);
    }
  }
}

class RastreoGeneralPage extends StatefulWidget {
  final String role; // ✅ guard de rol
  const RastreoGeneralPage({super.key, required this.role});

  @override
  State<RastreoGeneralPage> createState() => _RastreoGeneralPageState();
}

class _RastreoGeneralPageState extends State<RastreoGeneralPage> {
  final MapController _map = MapController();

  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;

  Timer? _pollTimer;
  Timer? _reconnectTimer;
  bool _reconnecting = false;

  bool _conectado = false;
  String? _error;

  late final String _wsUrl;
  late final String _token;

  bool _forbidden = false;

  /// session_id -> track
  final Map<int, _TrackInfo> _tracks = {};

  /// UI
  int? _selectedSessionId;
  bool _seguirSeleccion = false;

  DateTime? _lastAnyUpdateAt;

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

    final role = widget.role.trim().toLowerCase();
    if (role != 'admin') {
      _forbidden = true;
      _error = 'No autorizado: solo un admin puede ver Rastreo General.';
      return;
    }

    _wsUrl = ApiService.wsBaseUrl.trim();
    _token = ApiService.wsToken.trim();

    if (_wsUrl.isEmpty || _token.isEmpty) {
      _error = 'No hay token de WebSocket. Inicia sesión como admin.';
      return;
    }

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
    if (_forbidden) return;

    _reconnectTimer?.cancel();
    _pollTimer?.cancel();

    await _disposeWs();

    if (!mounted) return;
    setState(() {
      _error = null;
      _conectado = false;
      _lastAnyUpdateAt = null;
      // Nota: NO limpiamos _tracks aquí para conservar continuidad visual al reconectar.
    });

    try {
      final base = Uri.parse(_wsUrl);
      final uri = base.replace(queryParameters: {
        ...base.queryParameters,
        'token': _token,
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

      // poll: pide sesiones activas cada 10s
      _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _sendSubscribeAll();
        _watchdog();
      });
    } catch (e) {
      _scheduleReconnect('No se pudo conectar: $e');
    }
  }

  void _scheduleReconnect(String err) {
    if (!mounted) return;
    if (_forbidden) return;

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

    final last = _lastAnyUpdateAt;
    if (last == null) return;

    final secs = DateTime.now().difference(last).inSeconds;
    if (secs >= 20) _sendSubscribeAll();
    if (secs >= 45) _scheduleReconnect('Sin datos nuevos (${secs}s). Reconectando…');
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
        _sendSubscribeAll();
        return;
      }

      if (type == 'active_sessions') {
        _lastAnyUpdateAt = DateTime.now();

        final sessions = (msg['sessions'] as List?) ?? [];

        // marca “no visto” en este poll
        for (final t in _tracks.values) {
          t.missingPolls += 1;
        }

        for (final e in sessions) {
          if (e is! Map) continue;
          final s = e.map((k, v) => MapEntry(k.toString(), v));

          final sid = _toInt(s['session_id']);
          final noticiaId = _toInt(s['noticia_id']);
          if (sid == null || noticiaId == null) continue;

          final lastLat = _toDouble(s['last_lat']);
          final lastLon = _toDouble(s['last_lon']);

          final t = _tracks.putIfAbsent(
            sid,
            () => _TrackInfo(sessionId: sid, noticiaId: noticiaId),
          );

          // por si el backend cambia noticia_id (raro), actualiza
          t.noticiaId = noticiaId;

          t.missingPolls = 0;

          if (lastLat != null && lastLon != null) {
            t.addPoint(latlng.LatLng(lastLat, lastLon));
            _maybeAutoFollow();
          }
        }

        // limpia tracks que ya no están activos por varios polls
        final toRemove = <int>[];
        _tracks.forEach((sid, t) {
          if (t.missingPolls >= 4) toRemove.add(sid);
        });

        for (final sid in toRemove) {
          _tracks.remove(sid);
          if (_selectedSessionId == sid) {
            _selectedSessionId = null;
            _seguirSeleccion = false;
          }
        }

        if (mounted) setState(() {});
        return;
      }

      if (type == 'tracking_location') {
        _lastAnyUpdateAt = DateTime.now();

        final sid = _toInt(msg['session_id']);
        final noticiaId = _toInt(msg['noticia_id']);
        if (sid == null) return;

        final lat = _toDouble(msg['lat']);
        final lon = _toDouble(msg['lon']);
        if (lat == null || lon == null) return;

        final effectiveNoticia = noticiaId ?? (_tracks[sid]?.noticiaId ?? -1);
        if (effectiveNoticia <= 0) return;

        final t = _tracks.putIfAbsent(
          sid,
          () => _TrackInfo(sessionId: sid, noticiaId: effectiveNoticia),
        );
        t.noticiaId = effectiveNoticia;

        t.missingPolls = 0;
        t.addPoint(latlng.LatLng(lat, lon));
        _maybeAutoFollow();

        if (mounted) setState(() {});
        return;
      }

      if (type == 'tracking_stopped') {
        _lastAnyUpdateAt = DateTime.now();

        final sid = _toInt(msg['session_id']);
        if (sid == null) return;

        _tracks.remove(sid);
        if (_selectedSessionId == sid) {
          _selectedSessionId = null;
          _seguirSeleccion = false;
        }

        if (mounted) setState(() {});
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

  void _maybeAutoFollow() {
    if (!_seguirSeleccion) return;
    final sid = _selectedSessionId;
    if (sid == null) return;

    final p = _tracks[sid]?.ultimo;
    if (p == null) return;

    _map.move(p, 17.0);
  }

  Color _colorForSession(int sid, ThemeData theme) {
    final base = HSLColor.fromColor(theme.colorScheme.primary);
    final hueShift = (sid % 9) * 22.0;
    return base.withHue((base.hue + hueShift) % 360).toColor();
  }

  void _selectSession(int sid) {
    setState(() {
      _selectedSessionId = sid;
      _seguirSeleccion = true;
    });
    _maybeAutoFollow();
  }

  void _toggleSeguir() {
    if (_selectedSessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una ruta (toca un marcador o usa Lista).')),
      );
      return;
    }
    setState(() => _seguirSeleccion = !_seguirSeleccion);
    _maybeAutoFollow();
  }

  void _verTodo() {
    if (_tracks.isEmpty) return;

    final all = <latlng.LatLng>[];
    for (final t in _tracks.values) {
      if (t.ultimo != null) all.add(t.ultimo!);
    }
    if (all.isEmpty) return;

    double minLat = all.first.latitude, maxLat = all.first.latitude;
    double minLon = all.first.longitude, maxLon = all.first.longitude;

    for (final p in all) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    final center = latlng.LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2);

    final deltaLat = (maxLat - minLat).abs();
    final deltaLon = (maxLon - minLon).abs();
    final delta = (deltaLat > deltaLon) ? deltaLat : deltaLon;

    double zoom = 13.0;
    if (delta < 0.005) zoom = 16.0;
    else if (delta < 0.02) zoom = 15.0;
    else if (delta < 0.06) zoom = 14.0;
    else if (delta < 0.15) zoom = 13.0;
    else zoom = 12.0;

    setState(() => _seguirSeleccion = false);
    _map.move(center, zoom);
  }

  void _abrirListaSesiones() {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        final entries = _tracks.values.toList()
          ..sort((a, b) => a.noticiaId.compareTo(b.noticiaId));

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.route),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Trayectos activos (${entries.length})',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No hay rutas activas por el momento.',
                      style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7)),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final t = entries[i];
                        final selected = _selectedSessionId == t.sessionId;
                        final secs = (t.lastAt == null)
                            ? null
                            : DateTime.now().difference(t.lastAt!).inSeconds;

                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor: _colorForSession(t.sessionId, theme),
                            child: const Icon(Icons.directions_run, color: Colors.white, size: 18),
                          ),
                          title: Text(
                            'Noticia #${t.noticiaId}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            'Sesión: ${t.sessionId}${secs != null ? ' • Último: ${secs}s' : ''} • Puntos: ${t.total}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: selected
                              ? const Icon(Icons.check_circle)
                              : const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.pop(context);
                            _selectSession(t.sessionId);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _overlayCard({required Widget child}) {
    final theme = Theme.of(context);
    return Card(
      elevation: kIsWeb ? 0.6 : 2,
      shape: _softShape(theme),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final activos = _tracks.length;
    final selected = (_selectedSessionId != null) ? _tracks[_selectedSessionId!] : null;

    final statusTitle = activos == 0 ? 'Sin trayectos activos' : 'Trayectos activos: $activos';

    final statusSubtitle = !_conectado
        ? 'Conectando…'
        : (_lastAnyUpdateAt == null
            ? 'Esperando datos…'
            : 'En vivo • Última actualización hace ${DateTime.now().difference(_lastAnyUpdateAt!).inSeconds}s');

    final initialCenter = () {
      if (selected?.ultimo != null) return selected!.ultimo!;
      for (final t in _tracks.values) {
        if (t.ultimo != null) return t.ultimo!;
      }
      // Tepatitlán aprox
      return latlng.LatLng(20.8167, -102.7667);
    }();

    final polylines = <Polyline>[];
    for (final t in _tracks.values) {
      if (t.puntos.length >= 2) {
        polylines.add(
          Polyline(
            points: t.puntos,
            strokeWidth: 4,
            color: _colorForSession(t.sessionId, theme),
          ),
        );
      }
    }

    final markers = <Marker>[];
    for (final t in _tracks.values) {
      final p = t.ultimo;
      if (p == null) continue;

      final isSel = _selectedSessionId == t.sessionId;
      final c = _colorForSession(t.sessionId, theme);

      markers.add(
        Marker(
          point: p,
          width: 52,
          height: 52,
          child: GestureDetector(
            onTap: () => _selectSession(t.sessionId),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.location_on,
                  size: isSel ? 46 : 42,
                  color: isSel ? c : c.withOpacity(0.9),
                ),
                Positioned(
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: theme.dividerColor.withOpacity(0.65), width: 0.8),
                    ),
                    child: Text(
                      '#${t.noticiaId}',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final body = _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  if (_forbidden)
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Volver'),
                    )
                  else
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
                  initialCenter: initialCenter,
                  initialZoom: 13,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.seguimientomapacnt',
                  ),
                  PolylineLayer(polylines: polylines),
                  MarkerLayer(markers: markers),
                ],
              ),

              // Top status
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: _wrapWebWidth(
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: _hPad(context)),
                    child: _overlayCard(
                      child: Row(
                        children: [
                          Icon(
                            _conectado ? Icons.wifi : Icons.wifi_off,
                            color: _conectado ? theme.colorScheme.secondary : theme.colorScheme.error,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(statusTitle, style: const TextStyle(fontWeight: FontWeight.w900)),
                                const SizedBox(height: 2),
                                Text(
                                  statusSubtitle,
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface.withOpacity(0.70),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: _abrirListaSesiones,
                            icon: const Icon(Icons.list),
                            label: const Text('Lista'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom selected info
              if (selected != null)
                Positioned(
                  bottom: 12,
                  left: 12,
                  right: 12,
                  child: _wrapWebWidth(
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: _hPad(context)),
                      child: _overlayCard(
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: _colorForSession(selected.sessionId, theme),
                              child: const Icon(Icons.route, color: Colors.white, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Noticia #${selected.noticiaId}',
                                    style: const TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                  Text(
                                    'Sesión: ${selected.sessionId} • Puntos: ${selected.total}',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurface.withOpacity(0.70),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _toggleSeguir,
                              icon: Icon(_seguirSeleccion ? Icons.gps_fixed : Icons.gps_not_fixed),
                              label: Text(_seguirSeleccion ? 'Siguiendo' : 'Seguir'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rastreo General'),
        actions: [
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
      body: body,
    );
  }
}
