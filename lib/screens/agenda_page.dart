// lib/screens/agenda_page.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'dart:convert';
import 'dart:async';

import '../services/session_service.dart';
import '../auth_controller.dart';
import '../models/noticia.dart';
import '../models/admin_notificacion.dart';
import '../services/api_service.dart';
import 'noticia_detalle_page.dart';
import 'crear_noticia_page.dart';
import 'login_screen.dart';
import 'update_perfil_page.dart';
import 'gestion_reporteros_page.dart';
import 'gestion_noticias_page.dart';
import 'estadisticas_screen.dart';
import 'empleado_destacado.dart';
import 'rastreo_general.dart';
import 'package:intl/intl.dart';
import 'avisos_page.dart';
import 'clientes_page.dart';

enum AgendaView { year, month, day }

class MesEfemeride {
  final IconData icon;
  final Color color;
  final String tooltip;

  MesEfemeride({
    required this.icon,
    required this.color,
    required this.tooltip,
  });
}
class _AgendaDayLayoutItem {
  final Noticia noticia;
  final int startMinutes;
  final int endMinutes;
  int column;
  int totalColumns;

  _AgendaDayLayoutItem({
    required this.noticia,
    required this.startMinutes,
    required this.endMinutes,
    required this.column,
    this.totalColumns = 1,
  });
}

MesEfemeride efemerideMes(int month, ThemeData theme) {
  switch (month) {
    case 1:
      return MesEfemeride(
        icon: Icons.celebration,
        color: const Color(0xFFF94144),
        tooltip: 'Año Nuevo',
      );
    case 2:
      return MesEfemeride(
        icon: Icons.favorite,
        color: const Color(0xFFF3722C),
        tooltip: 'Día del Amor y la Amistad',
      );
    case 3:
      return MesEfemeride(
        icon: Icons.emoji_nature,
        color: const Color(0xFFF8961E),
        tooltip: 'Primavera',
      );
    case 4:
      return MesEfemeride(
        icon: Icons.face_outlined,
        color: const Color(0xFFF9844A),
        tooltip: 'Día del Niño',
      );
    case 5:
      return MesEfemeride(
        icon: Icons.face_2_rounded,
        color: const Color(0xFFF9C74F),
        tooltip: 'Día de las Madres',
      );
    case 6:
      return MesEfemeride(
        icon: Icons.wb_sunny,
        color: const Color(0xFF90BE6D),
        tooltip: 'Verano',
      );
    case 7:
      return MesEfemeride(
        icon: Icons.beach_access,
        color: const Color(0xFF43AA8B),
        tooltip: 'Vacaciones de verano',
      );
    case 8:
      return MesEfemeride(
        icon: Icons.school,
        color: const Color(0xFF4D908E),
        tooltip: 'Regreso a clases',
      );
    case 9:
      return MesEfemeride(
        icon: Icons.flag,
        color: const Color(0xFF577590),
        tooltip: 'Independencia de México',
      );
    case 10:
      return MesEfemeride(
        icon: Icons.nights_stay,
        color: const Color(0xFF277DA1),
        tooltip: 'Día de Muertos',
      );
    case 11:
      return MesEfemeride(
        icon: Icons.local_florist,
        color: const Color(0xFF4D908E),
        tooltip: 'Día de Muertos',
      );
    case 12:
      return MesEfemeride(
        icon: Icons.ice_skating_outlined,
        color: const Color(0xFFF94144),
        tooltip: 'Navidad',
      );
    default:
      return MesEfemeride(
        icon: Icons.event,
        color: theme.colorScheme.primary,
        tooltip: 'Mes',
      );
  }
}

class AgendaPage extends StatefulWidget {
  final int reporteroId;
  final String reporteroNombre;
  final bool esAdmin;
  final bool? puedeCrearNoticias;

  const AgendaPage({
    super.key,
    required this.reporteroId,
    required this.reporteroNombre,
    this.esAdmin = false,
    this.puedeCrearNoticias,
  });

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  bool _loading = true;
  String? _error;

  Timer? _notifTimer;
  bool _notifLoading = false;
  int _notifUnreadCount = 0;
  List<AdminNotificacion> _notificaciones = [];

  final LayerLink _notifLayerLink = LayerLink();
  OverlayEntry? _notifOverlayEntry;
  final GlobalKey _notifButtonKey = GlobalKey();
  final ScrollController _notifScrollController = ScrollController();

  final Map<DateTime, List<Noticia>> _eventosPorDia = {};
  final Map<int, int> _lastLayoutColumnByNoticiaId = {};

  AgendaView _vista = AgendaView.month;

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  late int _selectedMonthInYear;
  late String _nombreActual;

  // ---- Ajustes SOLO de dimensiones para Chrome/Web ----
  static const double _kWebMaxContentWidth = 1200;
  static const double _kWebWideBreakpoint = 980;

  double? _dragPreviewStartMinutes;
  int? _dragLockedColumn;
  int? _dragLockedTotalColumns;

  bool _isWebWide(BuildContext context) =>
      kIsWeb && MediaQuery.of(context).size.width >= _kWebWideBreakpoint;

  bool _modoModificarJornada = false;
  bool _savingCambiosAgenda = false;

  final Map<int, DateTime> _draftFechaCitaPorNoticia = {};

  int? _draggingNoticiaId;
  double? _dragStartGlobalDy;
  int? _dragStartMinutes;

  final GlobalKey _agendaGridKey = GlobalKey();

  double? _dragGrabOffsetDy;
  double? _dragPointerLocalDy;

  static const int _kAgendaSnapMinutes = 15;

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

  double _hPad(BuildContext context) => _isWebWide(context) ? 20 : 12;
  double _selectorHPad(BuildContext context) => _isWebWide(context) ? 20 : 16;

  int _eventDurationMinutes(Noticia noticia) {
    final raw = noticia.tiempoEnNota ?? noticia.limiteTiempoMinutos ?? 60;
    return raw.clamp(45, 180).toInt();
  }

  String _fmtHoraMin(int totalMinutes) {
    final clamped = totalMinutes.clamp(0, 1439);
    final h = (clamped ~/ 60).toString().padLeft(2, '0');
    final m = (clamped % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  DateTime _fechaLayoutAgenda(Noticia noticia) {
    if (_draggingNoticiaId == noticia.id) {
      return _draftFechaCitaPorNoticia[noticia.id] ?? noticia.fechaCita!;
    }
    return _fechaCitaVisible(noticia);
  }

  // ---- helpers visuales (sin cambiar lógica) ----
  ShapeBorder _softShape(ThemeData theme) => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.dividerColor.withOpacity(0.65),
          width: 0.9,
        ),
      );

  Widget _cardShell({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(10),
    double? elevation,
    Color? color,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: elevation ?? (kIsWeb ? 0.5 : 1),
      color: color ?? theme.colorScheme.surface,
      shape: _softShape(theme),
      child: Padding(padding: padding, child: child),
    );
  }

  Widget _maybeScrollbar({required Widget child}) {
    if (!kIsWeb) return child;
    return Scrollbar(
      thumbVisibility: true,
      interactive: true,
      child: child,
    );
  }

  Color _gridLineColor(ThemeData theme) {
    final base = theme.colorScheme.onSurface;
    final opacity = theme.brightness == Brightness.dark ? 0.10 : 0.08;
    return base.withOpacity(opacity);
  }

  static const List<Color> _reporteroLightPalette = [
    Color(0xFFE3F2FD),
    Color(0xFFE8F5E9),
    Color(0xFFFFF3E0),
    Color(0xFFF3E5F5),
    Color(0xFFE0F7FA),
    Color(0xFFFFEBEE),
    Color(0xFFF1F8E9),
    Color(0xFFEDE7F6),
    Color(0xFFE8EAF6),
    Color(0xFFFFF8E1),
  ];

  static const List<Color> _reporteroAccentPalette = [
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFFFB8C00),
    Color(0xFF8E24AA),
    Color(0xFF00ACC1),
    Color(0xFFE53935),
    Color(0xFF7CB342),
    Color(0xFF5E35B1),
    Color(0xFF3949AB),
    Color(0xFFF9A825),
  ];

  String _reporteroKey(String? nombre) {
    return (nombre ?? '').trim().toLowerCase();
  }

  // String _fmtHoraMin(int totalMinutes) {
  //   final clamped = totalMinutes.clamp(0, 1439);
  //   final h = (clamped ~/ 60).toString().padLeft(2, '0');
  //   final m = (clamped % 60).toString().padLeft(2, '0');
  //   return '$h:$m';
  // }

  int _stableStringHash(String value) {
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = ((hash * 31) + unit) & 0x7fffffff;
    }
    return hash;
  }

  int _reporteroColorIndex(String? nombre) {
    final key = _reporteroKey(nombre);
    if (key.isEmpty) return 0;
    return _stableStringHash(key) % _reporteroAccentPalette.length;
  }

  Color _reporteroAccentColor(String? nombre, ThemeData theme) {
    final key = _reporteroKey(nombre);
    if (key.isEmpty) return theme.colorScheme.outline;
    return _reporteroAccentPalette[_reporteroColorIndex(nombre)];
  }

  Color _reporteroBgColor(String? nombre, ThemeData theme, bool isDark) {
    final key = _reporteroKey(nombre);
    if (key.isEmpty) {
      return isDark
          ? theme.colorScheme.surfaceVariant.withOpacity(0.55)
          : theme.colorScheme.surfaceVariant.withOpacity(0.90);
    }

    final accent = _reporteroAccentColor(nombre, theme);
    if (isDark) {
      return accent.withOpacity(0.22);
    }

    return _reporteroLightPalette[_reporteroColorIndex(nombre)];
  }

  Color _readableTextOn(Color color) {
    final brightness = ThemeData.estimateBrightnessForColor(color);
    return brightness == Brightness.dark ? Colors.white : Colors.black87;
  }

  Widget _calDayCell({
    required ThemeData theme,
    required DateTime day,
    required bool wide,
    bool isSelected = false,
    bool isToday = false,
    bool isOutside = false,
  }) {
    final bool isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

    final Color border = isSelected
        ? theme.colorScheme.secondary.withOpacity(0.25)
        : _gridLineColor(theme);

    final Color bg = isSelected
        ? theme.colorScheme.secondary.withOpacity(theme.brightness == Brightness.dark ? 0.35 : 0.22)
        : isToday
            ? theme.colorScheme.primary.withOpacity(theme.brightness == Brightness.dark ? 0.22 : 0.12)
            : Colors.transparent;

    Color textColor;
    if (isSelected) {
      textColor = theme.colorScheme.onSecondary;
    } else if (isToday) {
      textColor = theme.colorScheme.primary;
    } else if (isOutside) {
      textColor = theme.colorScheme.onSurface.withOpacity(0.35);
    } else if (isWeekend) {
      textColor = theme.colorScheme.error.withOpacity(0.95);
    } else {
      textColor = theme.colorScheme.onSurface;
    }

    final double fontSize = wide ? 13 : 12;

    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border, width: 0.55),
      ),
      child: Text(
        '${day.day}',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: (isSelected || isToday) ? FontWeight.w800 : FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildAgendaDropPlaceholder({
    required ThemeData theme,
    required bool isDark,
    required Noticia noticia,
    required bool cerrada,
    required String horaTexto,
  }) {
    final accent = _reporteroAccentColor(noticia.reportero, theme);

    return Container(
      decoration: BoxDecoration(
        color: accent.withOpacity(isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accent.withOpacity(0.95),
          width: 1.4,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CustomPaint(
                painter: _AgendaPlaceholderPainter(
                  color: accent.withOpacity(isDark ? 0.16 : 0.12),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Icon(
                    Icons.place_outlined,
                    size: 16,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  noticia.noticia,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withOpacity(0.85),
                  ),
                ),
                const Spacer(),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(isDark ? 0.20 : 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        horaTexto,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                          color: accent,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (cerrada
                                ? theme.colorScheme.secondary
                                : theme.colorScheme.primary)
                            .withOpacity(isDark ? 0.20 : 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        cerrada ? 'Cerrada' : 'Pendiente',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                          color: cerrada
                              ? theme.colorScheme.secondary
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Panel lateral (Vista Día, escritorio) ----
  Widget _pill({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.30),
          width: 0.7,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: fg,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _daySidePanel({
    required ThemeData theme,
    required DateTime dia,
    required List<Noticia> eventos,
  }) {
    final total = eventos.length;
    final pendientes = eventos.where((e) => e.pendiente == true).length;
    final cerradas = total - pendientes;

    final preview = eventos.take(4).toList();

    return _cardShell(
      padding: const EdgeInsets.all(10),
      elevation: 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Resumen del día',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_nombreMes(dia.month)} ${dia.day}, ${dia.year}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: theme.colorScheme.onSurface.withOpacity(0.75),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _pill(
                theme: theme,
                icon: Icons.list_alt,
                label: '$total Total',
                bg: theme.colorScheme.primaryContainer,
                fg: theme.colorScheme.onPrimaryContainer,
              ),
              _pill(
                theme: theme,
                icon: Icons.schedule,
                label: '$pendientes Pendientes',
                bg: theme.colorScheme.surfaceVariant.withOpacity(0.55),
                fg: theme.colorScheme.onSurface.withOpacity(0.88),
              ),
              _pill(
                theme: theme,
                icon: Icons.check_circle,
                label: '$cerradas Cerradas',
                bg: theme.colorScheme.secondaryContainer,
                fg: theme.colorScheme.onSecondaryContainer,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: theme.dividerColor.withOpacity(0.45)),
          const SizedBox(height: 8),
          Text(
            'Vista rápida',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
              color: theme.colorScheme.onSurface.withOpacity(0.88),
            ),
          ),
          const SizedBox(height: 6),
          if (total == 0)
            Text(
              'No hay noticias para este día.',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withOpacity(0.65),
              ),
            )
          else
            ...preview.map((n) {
              final cerrada = n.pendiente == false;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: _reporteroAccentColor(n.reportero, theme),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        n.noticia,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          if (total > preview.length) ...[
            const SizedBox(height: 4),
            Text(
              '…y ${total - preview.length} más',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.60),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _nombreActual = widget.reporteroNombre;
    _selectedMonthInYear = _focusedDay.month;

    Future.microtask(() async {
      await _initPermisosLocal();
      await _refrescarPerfilDesdeServidor(showError: false);
      await _cargarNoticias();

      if (widget.esAdmin && kIsWeb) {
        await _cargarNotificacionesAdmin(silent: false);
        _notifTimer?.cancel();
        _notifTimer = Timer.periodic(const Duration(seconds: 15), (_) {
          _cargarNotificacionesAdmin(silent: true);
        });
      }
    });
  }

  @override
  void dispose() {
    _notifTimer?.cancel();
    super.dispose();
  }

  Future<void> _openAndRefresh(Widget page, {bool refreshPerms = true}) async {
    Navigator.pop(context); // cierra drawer
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    if (!mounted) return;

    if (refreshPerms) {
      await _refrescarPerfilDesdeServidor(showError: false);
    }
  }

  Future<void> _initPermisosLocal() async {
    final prefs = await SharedPreferences.getInstance();

    if (!widget.esAdmin) {
      AuthController.puedeCrearNoticias.value =
          prefs.getBool('auth_puede_crear_noticias') ??
          prefs.getBool('last_puede_crear_noticias') ??
          false;

      AuthController.menuPerms.value = const MenuPerms();
      return;
    }

    bool getOrFalse(String k) => prefs.getBool(k) ?? false;

    AuthController.puedeCrearNoticias.value = true;

    AuthController.menuPerms.value = MenuPerms(
      gestionNoticias: getOrFalse('auth_puede_ver_gestion_noticias'),
      estadisticas: getOrFalse('auth_puede_ver_estadisticas'),
      rastreoGeneral: getOrFalse('auth_puede_ver_rastreo_general'),
      empleadoMes: getOrFalse('auth_puede_ver_empleado_mes'),
      gestion: getOrFalse('auth_puede_ver_gestion'),
      clientes: getOrFalse('auth_puede_ver_clientes'),
    );
  }

  Future<void> _cargarNotificacionesAdmin({bool silent = true}) async {
    if (!(widget.esAdmin && kIsWeb)) return;
    if (_notifLoading) return;

    _notifLoading = true;
    try {
      final feed = await ApiService.getAdminNotificaciones(limit: 20);

      if (!mounted) return;
      setState(() {
        _notificaciones = feed.items;
        _notifUnreadCount = feed.unreadCount;
      });
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No pude cargar notificaciones: $e')),
        );
      }
    } finally {
      _notifLoading = false;
    }
  }

  Noticia? _buscarNoticiaPorId(int noticiaId) {
    for (final lista in _eventosPorDia.values) {
      for (final n in lista) {
        if (n.id == noticiaId) return n;
      }
    }
    return null;
  }

  String _fmtNotifDate(DateTime? dt) {
    if (dt == null) return '';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }

  void _toggleNotifOverlay() {
    if (_notifOverlayEntry != null) {
      _cerrarNotifOverlay();
    } else {
      _abrirNotifOverlay();
    }
  }

  void _cerrarNotifOverlay() {
    _notifOverlayEntry?.remove();
    _notifOverlayEntry = null;
  }

  void _assignStableColumnsToCluster(List<_AgendaDayLayoutItem> cluster) {
    cluster.sort((a, b) {
      final aDragged = a.noticia.id == _draggingNoticiaId;
      final bDragged = b.noticia.id == _draggingNoticiaId;

      if (aDragged != bDragged) return aDragged ? -1 : 1;

      final c = a.startMinutes.compareTo(b.startMinutes);
      if (c != 0) return c;

      final aDur = a.endMinutes - a.startMinutes;
      final bDur = b.endMinutes - b.startMinutes;
      final d = bDur.compareTo(aDur);
      if (d != 0) return d;

      return a.noticia.id.compareTo(b.noticia.id);
    });

    final columnEnds = <int, int>{};
    int maxColumns = 0;

    bool canUseColumn(int col, int startMinutes) {
      final end = columnEnds[col];
      return end == null || end <= startMinutes;
    }

    for (final item in cluster) {
      final preferredColumn = item.noticia.id == _draggingNoticiaId
          ? _dragLockedColumn
          : _lastLayoutColumnByNoticiaId[item.noticia.id];

      int? chosen;

      if (preferredColumn != null && canUseColumn(preferredColumn, item.startMinutes)) {
        chosen = preferredColumn;
      } else {
        final reusable = <int>[];
        for (int c = 0; c < maxColumns; c++) {
          if (canUseColumn(c, item.startMinutes)) {
            reusable.add(c);
          }
        }

        if (reusable.isNotEmpty) {
          if (preferredColumn != null) {
            reusable.sort((a, b) {
              final da = (a - preferredColumn).abs();
              final db = (b - preferredColumn).abs();
              if (da != db) return da.compareTo(db);
              return a.compareTo(b);
            });
          }
          chosen = reusable.first;
        } else {
          chosen = maxColumns;
        }
      }

      item.column = chosen;
      columnEnds[chosen] = item.endMinutes;

      if (chosen + 1 > maxColumns) {
        maxColumns = chosen + 1;
      }
    }

    if (maxColumns < 1) maxColumns = 1;

    for (final item in cluster) {
      item.totalColumns = maxColumns;
    }

    cluster.sort((a, b) {
      final c = a.startMinutes.compareTo(b.startMinutes);
      if (c != 0) return c;
      return a.noticia.id.compareTo(b.noticia.id);
    });
  }

  List<_AgendaDayLayoutItem> _buildStableDayLayout(
    List<Noticia> eventos,
    int Function(Noticia noticia) durationMinutes,
  ) {
    final items = eventos
        .map((noticia) {
          final fecha = _fechaLayoutAgenda(noticia);
          final startMinutes = fecha.hour * 60 + fecha.minute;
          final endMinutes =
              (startMinutes + durationMinutes(noticia)).clamp(0, 24 * 60);

          return _AgendaDayLayoutItem(
            noticia: noticia,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            column: 0,
            totalColumns: 1,
          );
        })
        .toList()
      ..sort((a, b) {
        final c = a.startMinutes.compareTo(b.startMinutes);
        if (c != 0) return c;
        final d = a.endMinutes.compareTo(b.endMinutes);
        if (d != 0) return d;
        return a.noticia.id.compareTo(b.noticia.id);
      });

    final result = <_AgendaDayLayoutItem>[];
    var cluster = <_AgendaDayLayoutItem>[];
    var clusterMaxEnd = -1;

    void flushCluster() {
      if (cluster.isEmpty) return;
      _assignStableColumnsToCluster(cluster);
      result.addAll(cluster);
      cluster = <_AgendaDayLayoutItem>[];
      clusterMaxEnd = -1;
    }

    for (final item in items) {
      if (cluster.isEmpty) {
        cluster.add(item);
        clusterMaxEnd = item.endMinutes;
        continue;
      }

      if (item.startMinutes < clusterMaxEnd) {
        cluster.add(item);
        if (item.endMinutes > clusterMaxEnd) {
          clusterMaxEnd = item.endMinutes;
        }
      } else {
        flushCluster();
        cluster.add(item);
        clusterMaxEnd = item.endMinutes;
      }
    }

    flushCluster();

    _lastLayoutColumnByNoticiaId
      ..clear()
      ..addEntries(result.map((e) => MapEntry(e.noticia.id, e.column)));

    return result;
  }

  // void _onAgendaItemPointerMove(
  //   Noticia noticia,
  //   PointerMoveEvent event,
  //   double hourHeight,
  // ) {
  //   if (_draggingNoticiaId != noticia.id) return;
  //   if (_dragStartGlobalDy == null || _dragStartMinutes == null) return;

  //   final duracion = _eventDurationMinutes(noticia);

  //   final deltaDy = event.position.dy - _dragStartGlobalDy!;
  //   final deltaMinutes = (deltaDy / hourHeight) * 60.0;

  //   final double rawHeight =
  //       ((_eventDurationMinutes(noticia) / 60.0) * hourHeight);
  //   final double visualHeight =
  //       rawHeight < 92 ? 92 : rawHeight;

  //   final double maxTop = (hourHeight * 24) - visualHeight;
  //   final double previewTop = (((_dragStartMinutes!.toDouble() + deltaMinutes) / 60.0) * hourHeight)
  //       .clamp(0.0, maxTop);

  //   final double previewStartMinutes = (previewTop / hourHeight) * 60.0;

  //   final double maxStartMinutes =
  //       ((24 * 60) - duracion).clamp(0, 24 * 60).toDouble();

  //   final int snappedStartMinutes =
  //       _snapMinutes(previewStartMinutes.round()).clamp(0, maxStartMinutes.toInt());

  //   final original = noticia.fechaCita!;
  //   final normalizada = DateTime(
  //     original.year,
  //     original.month,
  //     original.day,
  //     snappedStartMinutes ~/ 60,
  //     snappedStartMinutes % 60,
  //   );

  //   final bool sinCambio =
  //       original.year == normalizada.year &&
  //       original.month == normalizada.month &&
  //       original.day == normalizada.day &&
  //       original.hour == normalizada.hour &&
  //       original.minute == normalizada.minute;

  //   setState(() {
  //     _dragPreviewStartMinutes = previewStartMinutes;

  //     if (sinCambio) {
  //       _draftFechaCitaPorNoticia.remove(noticia.id);
  //     } else {
  //       _draftFechaCitaPorNoticia[noticia.id] = normalizada;
  //     }
  //   });
  // }

  Future<void> _abrirNotifOverlay() async {
    await _cargarNotificacionesAdmin(silent: true);
    if (!mounted) return;

    final overlay = Overlay.of(context);
    final buttonContext = _notifButtonKey.currentContext;
    if (overlay == null || buttonContext == null) return;

    final renderBox = buttonContext.findRenderObject() as RenderBox;
    final buttonSize = renderBox.size;

    _notifOverlayEntry = OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _cerrarNotifOverlay,
                child: const SizedBox.expand(),
              ),
            ),

            CompositedTransformFollower(
              link: _notifLayerLink,
              showWhenUnlinked: false,
              offset: Offset(-320 + buttonSize.width, buttonSize.height + 8),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 360,
                  constraints: const BoxConstraints(
                    maxHeight: 420,
                    minHeight: 80,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: theme.dividerColor.withOpacity(0.25),
                      width: 0.9,
                    ),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                        color: Colors.black.withOpacity(0.16),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: theme.dividerColor.withOpacity(0.18),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Notificaciones',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (_notifUnreadCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '$_notifUnreadCount nuevas',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      if (_notificaciones.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                          child: Text('No hay notificaciones.'),
                        )
                      else
                        Flexible(
                          child: Scrollbar(
                            controller: _notifScrollController,
                            thumbVisibility: true,
                            child: ListView.separated(
                              controller: _notifScrollController,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              shrinkWrap: true,
                              itemCount: _notificaciones.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: theme.dividerColor.withOpacity(0.12),
                              ),
                              itemBuilder: (_, index) {
                                final item = _notificaciones[index];

                                return InkWell(
                                  onTap: () => _abrirNotificacion(item),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    color: item.leida
                                        ? Colors.transparent
                                        : theme.colorScheme.primary.withOpacity(0.06),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Icon(
                                            item.leida
                                                ? Icons.notifications_none
                                                : Icons.notifications_active,
                                            size: 18,
                                            color: item.leida
                                                ? theme.colorScheme.onSurface.withOpacity(0.65)
                                                : theme.colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.mensaje,
                                                style: TextStyle(
                                                  fontWeight: item.leida
                                                      ? FontWeight.w500
                                                      : FontWeight.w800,
                                                  fontSize: 13.5,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _fmtNotifDate(item.createdAt),
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: theme.colorScheme.onSurface.withOpacity(0.62),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(
                                          Icons.chevron_right,
                                          size: 18,
                                          color: theme.colorScheme.onSurface.withOpacity(0.45),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_notifOverlayEntry!);
  }

  Future<void> _abrirNotificacion(AdminNotificacion item) async {
    _cerrarNotifOverlay();
    try {
      if (!item.leida) {
        await ApiService.marcarAdminNotificacionLeida(item.id);
      }
      await _cargarNotificacionesAdmin(silent: true);
      var noticia = _buscarNoticiaPorId(item.noticiaId);
      if (noticia == null) {
        await _cargarNoticias();
        noticia = _buscarNoticiaPorId(item.noticiaId);
      }
      if (!mounted) return;
      if (noticia == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No encontré la noticia para abrir detalles.'),
          ),
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NoticiaDetallePage(
            noticia: noticia!,
            soloLectura: (noticia.pendiente == false),
            role: 'admin',
          ),
        ),
      );
      await _cargarNoticias();
      await _cargarNotificacionesAdmin(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al abrir notificación: $e')),
      );
    }
  }

  bool _toBool(dynamic x) {
    if (x == null) return false;
    if (x is bool) return x;
    if (x is num) return x.toInt() == 1;
    final s = x.toString().trim().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes' || s == 'si';
  }

  Future<void> _refrescarPerfilDesdeServidor({bool showError = false}) async {
    if (!widget.esAdmin) return;

    try {
      final p = await ApiService.getPerfil();
      final prefs = await SharedPreferences.getInstance();

      bool b(String k) => _toBool(p[k]);

      final perms = MenuPerms(
        gestionNoticias: b('puede_ver_gestion_noticias'),
        estadisticas: b('puede_ver_estadisticas'),
        rastreoGeneral: b('puede_ver_rastreo_general'),
        empleadoMes: b('puede_ver_empleado_mes'),
        gestion: b('puede_ver_gestion'),
        clientes: b('puede_ver_clientes'),
      );

      AuthController.menuPerms.value = perms;

      await prefs.setBool('auth_puede_ver_gestion_noticias', perms.gestionNoticias);
      await prefs.setBool('auth_puede_ver_estadisticas', perms.estadisticas);
      await prefs.setBool('auth_puede_ver_rastreo_general', perms.rastreoGeneral);
      await prefs.setBool('auth_puede_ver_empleado_mes', perms.empleadoMes);
      await prefs.setBool('auth_puede_ver_gestion', perms.gestion);
      await prefs.setBool('auth_puede_ver_clientes', perms.clientes);
    } catch (e) {
      if (showError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No pude refrescar permisos: $e')),
        );
      }
    }
  }

  DateTime _soloFecha(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  Future<void> _abrirPerfilAdmin() async {
    Navigator.pop(context);

    final nuevoNombre = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => UpdatePerfilPage(
          reporteroId: widget.reporteroId,
          nombreActual: _nombreActual,
        ),
      ),
    );

    if (!mounted) return;

    if (nuevoNombre != null && nuevoNombre.trim().isNotEmpty) {
      setState(() => _nombreActual = nuevoNombre.trim());
    }
    await _refrescarPerfilDesdeServidor(showError: false);
  }

  Future<void> _abrirCrearAvisoDialog() async {
  final quill.QuillController avisoCtrl = quill.QuillController.basic();
  final FocusNode avisoFocus = FocusNode();
  final ScrollController avisoScroll = ScrollController();
  final parentCtx = context;
  final theme = Theme.of(parentCtx);

  final tituloCtrl = TextEditingController();
  DateTime? vigencia;

  final fmt = DateFormat('dd/MM/yyyy');

  try {
    await showDialog(
      context: parentCtx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        bool saving = false;

        // Tamaño “fijo” responsivo: buen marco en pantalla
        final size = MediaQuery.of(dialogCtx).size;
        final bool isWide = size.width >= 700;

        // ancho ideal: 560 en pantallas grandes, en móvil casi todo menos márgenes
        final double targetWidth = isWide ? 560 : size.width * 0.92;

        // alto máximo: 70% de pantalla (scroll interno)
        final double maxHeight = size.height * 0.70;

        // alto fijo del campo descripción (para que no “deforme” el dialog)
        final double descHeight = isWide ? 220 : 200;

        final scrollCtrl = ScrollController();

        Future<void> pickVigencia(StateSetter setStateDialog) async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: dialogCtx, // ✅ NO uses el context padre aquí
            initialDate: vigencia ?? now,
            firstDate: DateTime(now.year, now.month, now.day),
            lastDate: DateTime(now.year + 3, 12, 31),
            helpText: 'Selecciona vigencia',
            cancelText: 'Cancelar',
            confirmText: 'Aceptar',
          );

          if (picked == null) return;
          if (!dialogCtx.mounted) return; // ✅ evita context muerto
          setStateDialog(() => vigencia = picked);
        }

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Crear aviso'),

              // clave: forzar ancho/alto y scroll interno
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: targetWidth,
                  minWidth: targetWidth,
                  maxHeight: maxHeight,
                ),
                child: Scrollbar(
                  controller: scrollCtrl,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.only(right: 6), // espacio para scrollbar
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: tituloCtrl,
                          textInputAction: TextInputAction.next,
                          enabled: !saving,
                          decoration: const InputDecoration(
                            labelText: 'Título del aviso',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),

                        IgnorePointer(
                          ignoring: saving,
                          child: quill.QuillSimpleToolbar(
                            controller: avisoCtrl,
                            config: const quill.QuillSimpleToolbarConfig(
                              // ❌ nada de tamaños/fuentes/títulos
                              showFontFamily: false,
                              showFontSize: false,
                              showHeaderStyle: false,
                              showSmallButton: false,

                              // (opcional) si tampoco quieres colores:
                              showColorButton: false,
                              showBackgroundColorButton: false,

                              // ✅ estilos que sí quieres
                              showBoldButton: true,
                              showItalicButton: true,
                              showUnderLineButton: true,
                              showStrikeThrough: true,

                              // ✅ útiles tipo “Word/Docs”
                              showListBullets: true,
                              showListNumbers: true,
                              showLink: true,
                              showClearFormat: true,
                              showUndo: true,
                              showRedo: true,

                              // ❌ quita lo que no te interese
                              showInlineCode: false,
                              showCodeBlock: false,
                              showQuote: false,
                              showIndent: false,
                              showAlignmentButtons: false,
                              showDirection: false,
                              showSearchButton: false,
                              showSubscript: false,
                              showSuperscript: false,
                              showListCheck: false,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Campo descripción con altura fija y scroll propio
                        SizedBox(
                          height: descHeight,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: theme.dividerColor),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: quill.QuillEditor.basic(
                                controller: avisoCtrl,
                                focusNode: avisoFocus,
                                scrollController: avisoScroll,
                                config: quill.QuillEditorConfig(
                                  autoFocus: false,
                                  expands: true,
                                  padding: EdgeInsets.zero,
                                  placeholder: 'Descripción',
                                  showCursor: !saving,
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Vigencia'),
                          subtitle: Text(
                            vigencia == null
                                ? 'Selecciona una fecha'
                                : 'Hasta: ${fmt.format(vigencia!)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: vigencia == null
                                  ? theme.colorScheme.onSurface.withOpacity(0.65)
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                          trailing: const Icon(Icons.calendar_month),
                          onTap: saving ? null : () => pickVigencia(setStateDialog),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogCtx, rootNavigator: true).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final titulo = tituloCtrl.text.trim();
                          final plainDesc = avisoCtrl.document.toPlainText().trim();

                          // ✅ SnackBars SIEMPRE con parentCtx, no con context del diálogo
                          if (titulo.isEmpty) {
                            ScaffoldMessenger.of(parentCtx).showSnackBar(
                              const SnackBar(content: Text('Escribe el título del aviso')),
                            );
                            return;
                          }
                          if (plainDesc.isEmpty) {
                            ScaffoldMessenger.of(parentCtx).showSnackBar(
                              const SnackBar(content: Text('Escribe la descripción')),
                            );
                            return;
                          }
                          if (vigencia == null) {
                            ScaffoldMessenger.of(parentCtx).showSnackBar(
                              const SnackBar(content: Text('Selecciona la vigencia')),
                            );
                            return;
                          }

                          setStateDialog(() {
                            saving = true;
                            avisoCtrl.readOnly = true;
                          });

                          try {
                            final descDeltaJson = _deltaJsonSinTamanos(avisoCtrl);

                            await ApiService.crearAviso(
                              titulo: titulo,
                              descripcion: descDeltaJson,
                              vigenciaDia: vigencia!,
                            );

                            if (!dialogCtx.mounted) return; // ✅
                            Navigator.of(dialogCtx, rootNavigator: true).pop();

                            if (!mounted) return;
                            ScaffoldMessenger.of(parentCtx).showSnackBar(
                              const SnackBar(content: Text('Aviso creado')),
                            );
                          } catch (e) {
                            if (dialogCtx.mounted) {
                              setStateDialog(() => saving = false);
                            }
                            if (!mounted) return;
                            ScaffoldMessenger.of(parentCtx).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
    } finally {
      tituloCtrl.dispose();
      avisoFocus.dispose();
      avisoScroll.dispose();
      avisoCtrl.dispose();
    }
  }
  Future<void> _limpiarSesionLocal() async {
    await SessionService.clearSession();
    AuthController.reset();
  }

  void _confirmarCerrarSesion() {
    Navigator.pop(context);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro que deseas Cerrar Sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _limpiarSesionLocal();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
            child: const Text('Cerrar Sesión'),
          ),
        ],
      ),
    );
  }

  Drawer _buildDrawerByPerms(MenuPerms perms) {
    final roleStr = widget.esAdmin ? 'admin' : 'reportero';

    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(_nombreActual),
            accountEmail: Text(widget.esAdmin ? 'Admin' : 'Reportero'),
            currentAccountPicture: CircleAvatar(
              child: Text(
                _nombreActual.isNotEmpty ? _nombreActual[0].toUpperCase() : 'U',
              ),
            ),
          ),

          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Perfil'),
            onTap: _abrirPerfilAdmin,
          ),

          // Avisos: tú los dejaste como admin-only
          if (widget.esAdmin)
            ListTile(
              leading: const Icon(Icons.notifications),
              title: const Text('Avisos'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AvisosPage()),
                );
              },
            ),

          if (perms.gestionNoticias)
            ListTile(
              leading: const Icon(Icons.article),
              title: const Text('Gestión Noticias'),
              onTap: () => _openAndRefresh(const GestionNoticiasPage()),
            ),

          if (perms.estadisticas)
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: const Text('Estadísticas'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EstadisticasScreen()),
                );
              },
            ),

          if (perms.rastreoGeneral)
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('Rastreo General'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RastreoGeneralPage(role: roleStr),
                  ),
                );
              },
            ),

          if (perms.empleadoMes)
            ListTile(
              leading: const Icon(Icons.star_rounded),
              title: const Text('Empleado del Mes'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EmpleadoDestacadoPage(role: roleStr),
                  ),
                );
              },
            ),

          if (perms.gestion)
            ListTile(
              leading: const Icon(Icons.manage_accounts),
              title: const Text('Gestión'),
              onTap: () => _openAndRefresh(const GestionReporterosPage()),
            ),

          if (perms.clientes)
            ListTile(
              leading: const Icon(Icons.groups_rounded),
              title: const Text('Clientes'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ClientesPage()),
                );
              },
            ),

          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red)),
            onTap: _confirmarCerrarSesion,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _cargarNoticias() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final noticias = widget.esAdmin
          ? await ApiService.getNoticiasAdmin()
          : await ApiService.getNoticiasAgenda(widget.reporteroId);

      if (!mounted) return;

      _eventosPorDia.clear();
      for (final n in noticias) {
        if (n.fechaCita == null) continue;
        final fechaClave = _soloFecha(n.fechaCita!);
        _eventosPorDia.putIfAbsent(fechaClave, () => []);
        _eventosPorDia[fechaClave]!.add(n);
      }

      if (!mounted) return;
      setState(() {
        _selectedDay = _selectedDay ?? _soloFecha(_focusedDay);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Error al cargar agenda: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<Noticia> _eventosDeDia(DateTime day) {
    final clave = _soloFecha(day);
    return _eventosPorDia[clave] ?? [];
  }

  List<Noticia> _eventosDelMes(DateTime mesRef) {
    final List<Noticia> result = [];
    _eventosPorDia.forEach((fecha, lista) {
      if (fecha.year == mesRef.year && fecha.month == mesRef.month) {
        result.addAll(lista);
      }
    });

    result.sort((a, b) {
      final fa = a.fechaCita ?? DateTime(2100);
      final fb = b.fechaCita ?? DateTime(2100);
      return fa.compareTo(fb);
    });

    return result;
  }

  String _nombreMes(int month) {
    const nombres = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    return nombres[month - 1];
  }

  String _formatearFechaCorta(DateTime fecha) {
    final d = fecha.day.toString().padLeft(2, '0');
    final m = fecha.month.toString().padLeft(2, '0');
    final y = fecha.year.toString();
    return '$d/$m/$y';
  }

  DateTime _fechaCitaVisible(Noticia noticia) {
    return _draftFechaCitaPorNoticia[noticia.id] ?? noticia.fechaCita!;
  }

  bool get _hayCambiosAgenda => _draftFechaCitaPorNoticia.isNotEmpty;

  int _snapMinutes(int minutes) {
    return ((minutes / _kAgendaSnapMinutes).round()) * _kAgendaSnapMinutes;
  }

  void _entrarModoModificarJornada() {
    setState(() {
      _modoModificarJornada = true;
      _savingCambiosAgenda = false;
      _draftFechaCitaPorNoticia.clear();
      _draggingNoticiaId = null;
      _dragStartGlobalDy = null;
      _dragStartMinutes = null;
      _dragPreviewStartMinutes = null;
      _dragLockedColumn = null;
      _dragLockedTotalColumns = null;
    });
  }

  void _cancelarModificacionJornada() {
    setState(() {
      _modoModificarJornada = false;
      _savingCambiosAgenda = false;
      _draftFechaCitaPorNoticia.clear();
      _draggingNoticiaId = null;
      _dragStartGlobalDy = null;
      _dragStartMinutes = null;
      _dragPreviewStartMinutes = null;
      _dragLockedColumn = null;
      _dragLockedTotalColumns = null;
    });
  }

  RenderBox? _agendaGridBox() {
    final ro = _agendaGridKey.currentContext?.findRenderObject();
    return ro is RenderBox ? ro : null;
  }

  // String _fmtHoraMin(int totalMinutes) {
  //   final clamped = totalMinutes.clamp(0, (24 * 60) - 1);
  //   final h = (clamped ~/ 60).toString().padLeft(2, '0');
  //   final m = (clamped % 60).toString().padLeft(2, '0');
  //   return '$h:$m';
  // }

  void _updateFloatingAgendaDrag(
    Noticia noticia,
    Offset globalPosition,
    double hourHeight,
    double totalHeight,
  ) {
    if (_draggingNoticiaId != noticia.id) return;
    if (_dragStartMinutes == null || _dragGrabOffsetDy == null) return;

    final gridBox = _agendaGridBox();
    if (gridBox == null) return;

    final local = gridBox.globalToLocal(globalPosition);
    final duracion = _eventDurationMinutes(noticia);

    final rawHeight = (duracion / 60.0) * hourHeight;
    final visualHeight = rawHeight.clamp(92.0, totalHeight.toDouble());

    final maxTop = totalHeight - visualHeight;
    final top = (local.dy - _dragGrabOffsetDy!).clamp(0.0, maxTop);

    final previewStartMinutes = (top / hourHeight) * 60.0;
    final maxStartMinutes = ((24 * 60) - duracion).clamp(0, 24 * 60);
    final snappedStartMinutes =
        _snapMinutes(previewStartMinutes.round()).clamp(0, maxStartMinutes);

    final original = noticia.fechaCita!;
    final normalizada = DateTime(
      original.year,
      original.month,
      original.day,
      snappedStartMinutes ~/ 60,
      snappedStartMinutes % 60,
    );

    final sinCambio =
        original.year == normalizada.year &&
        original.month == normalizada.month &&
        original.day == normalizada.day &&
        original.hour == normalizada.hour &&
        original.minute == normalizada.minute;

    setState(() {
      _dragPointerLocalDy = local.dy.clamp(0.0, totalHeight);
      _dragPreviewStartMinutes = previewStartMinutes;

      if (sinCambio) {
        _draftFechaCitaPorNoticia.remove(noticia.id);
      } else {
        _draftFechaCitaPorNoticia[noticia.id] = normalizada;
      }
    });
  }

  // void _setDraftFechaCita(Noticia noticia, DateTime nuevaFechaCita) {
  //   final original = noticia.fechaCita!;
  //   final normalizada = DateTime(
  //     original.year,
  //     original.month,
  //     original.day,
  //     nuevaFechaCita.hour,
  //     nuevaFechaCita.minute,
  //   );

  //   final bool sinCambio =
  //       original.year == normalizada.year &&
  //       original.month == normalizada.month &&
  //       original.day == normalizada.day &&
  //       original.hour == normalizada.hour &&
  //       original.minute == normalizada.minute;

  //   setState(() {
  //     if (sinCambio) {
  //       _draftFechaCitaPorNoticia.remove(noticia.id);
  //     } else {
  //       _draftFechaCitaPorNoticia[noticia.id] = normalizada;
  //     }
  //   });
  // }

  void _beginAgendaItemDrag(
    Noticia noticia,
    _AgendaDayLayoutItem item,
    DragStartDetails details,
    double hourHeight,
    double totalHeight,
  ) {
    final fechaBase = _fechaCitaVisible(noticia);
    final baseMinutes = fechaBase.hour * 60 + fechaBase.minute;

    final rawHeight = ((_eventDurationMinutes(noticia) / 60.0) * hourHeight);
    final visualHeight = rawHeight.clamp(92.0, totalHeight.toDouble());

    setState(() {
      _draggingNoticiaId = noticia.id;
      _dragStartGlobalDy = details.globalPosition.dy;
      _dragStartMinutes = baseMinutes;
      _dragPreviewStartMinutes = baseMinutes.toDouble();
      _dragLockedColumn = item.column;
      _dragLockedTotalColumns = item.totalColumns > 0 ? item.totalColumns : 1;
      _dragGrabOffsetDy = details.localPosition.dy.clamp(0.0, visualHeight);
      _dragPointerLocalDy = null;
    });

    _updateFloatingAgendaDrag(
      noticia,
      details.globalPosition,
      hourHeight,
      totalHeight,
    );
  }

  void _onAgendaItemDragUpdate(
    Noticia noticia,
    DragUpdateDetails details,
    double hourHeight,
  ) {
    if (_draggingNoticiaId != noticia.id) return;
    if (_dragStartGlobalDy == null || _dragStartMinutes == null) return;

    final duracion = _eventDurationMinutes(noticia);

    final deltaDy = details.globalPosition.dy - _dragStartGlobalDy!;
    final deltaMinutes = (deltaDy / hourHeight) * 60.0;

    final double maxStartMinutes =
        ((24 * 60) - duracion).clamp(0, 24 * 60).toDouble();

    final double previewStartMinutes =
        (_dragStartMinutes!.toDouble() + deltaMinutes).clamp(0.0, maxStartMinutes);

    final int snappedStartMinutes =
        _snapMinutes(previewStartMinutes.round()).clamp(0, maxStartMinutes.toInt());

    final original = noticia.fechaCita!;
    final normalizada = DateTime(
      original.year,
      original.month,
      original.day,
      snappedStartMinutes ~/ 60,
      snappedStartMinutes % 60,
    );

    final bool sinCambio =
        original.year == normalizada.year &&
        original.month == normalizada.month &&
        original.day == normalizada.day &&
        original.hour == normalizada.hour &&
        original.minute == normalizada.minute;

    setState(() {
      _dragPreviewStartMinutes = previewStartMinutes;

      if (sinCambio) {
        _draftFechaCitaPorNoticia.remove(noticia.id);
      } else {
        _draftFechaCitaPorNoticia[noticia.id] = normalizada;
      }
    });
  }

  void _onAgendaItemDragEnd() {
    setState(() {
      _draggingNoticiaId = null;
      _dragStartGlobalDy = null;
      _dragStartMinutes = null;
      _dragPreviewStartMinutes = null;
      _dragLockedColumn = null;
      _dragLockedTotalColumns = null;
      _dragGrabOffsetDy = null;
      _dragPointerLocalDy = null;
    });
  }

  Future<void> _guardarCambiosJornada() async {
    if (!_hayCambiosAgenda || _savingCambiosAgenda) return;

    setState(() => _savingCambiosAgenda = true);

    final cambios = Map<int, DateTime>.from(_draftFechaCitaPorNoticia);
    final Map<int, DateTime> fallidos = {};

    try {
      for (final entry in cambios.entries) {
        try {
          await ApiService.actualizarHoraCitaNoticia(
            noticiaId: entry.key,
            nuevaFechaCita: entry.value,
          );
        } catch (_) {
          fallidos[entry.key] = entry.value;
        }
      }

      await _cargarNoticias();

      if (!mounted) return;

      setState(() {
        _draftFechaCitaPorNoticia
          ..clear()
          ..addAll(fallidos);
        _savingCambiosAgenda = false;
        if (fallidos.isEmpty) {
          _modoModificarJornada = false;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            fallidos.isEmpty
                ? 'Cambios guardados correctamente.'
                : 'Algunas noticias no pudieron actualizarse.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingCambiosAgenda = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar cambios: $e')),
      );
    }
  }

  String _deltaJsonSinTamanos(quill.QuillController c) {
    final ops = c.document.toDelta().toJson();
    final cleaned = ops.map((op) {
      if (op is Map && op['attributes'] is Map) {
        final m = Map<String, dynamic>.from(op);
        final attrs = Map<String, dynamic>.from(m['attributes'] as Map);

        attrs.remove('size');
        attrs.remove('font');
        attrs.remove('header');
        attrs.remove('small');
        attrs.remove('line-height');

        if (attrs.isEmpty) {
          m.remove('attributes');
        } else {
          m['attributes'] = attrs;
        }
        return m;
      }
      return op;
    }).toList();

    return jsonEncode(cleaned);
  }

  String _viewTitle(AgendaView view) {
    switch (view) {
      case AgendaView.year:
        return 'Panorama';
      case AgendaView.month:
        return 'Calendario';
      case AgendaView.day:
        return 'Jornada';
    }
  }

  String _viewSubtitle(AgendaView view) {
    switch (view) {
      case AgendaView.year:
        return 'Vista anual';
      case AgendaView.month:
        return 'Planeación mensual';
      case AgendaView.day:
        return 'Detalle del día';
    }
  }

  IconData _viewIcon(AgendaView view) {
    switch (view) {
      case AgendaView.year:
        return Icons.auto_awesome_mosaic_rounded;
      case AgendaView.month:
        return Icons.calendar_month_rounded;
      case AgendaView.day:
        return Icons.view_agenda_rounded;
    }
  }

  String _viewBadge(AgendaView view) {
    switch (view) {
      case AgendaView.year:
        final mesesActivos = <int>{};
        _eventosPorDia.forEach((fecha, lista) {
          if (fecha.year == _focusedDay.year && lista.isNotEmpty) {
            mesesActivos.add(fecha.month);
          }
        });
        return '${mesesActivos.length} meses';
      case AgendaView.month:
        return '${_eventosDelMes(_focusedDay).length} noticias';
      case AgendaView.day:
        final dia = _selectedDay ?? _soloFecha(_focusedDay);
        return '${_eventosDeDia(dia).length} noticias';
    }
  }

  String _contextLabel() {
    switch (_vista) {
      case AgendaView.year:
        return 'Cobertura ${_focusedDay.year}';
      case AgendaView.month:
        return 'Planeación de ${_nombreMes(_focusedDay.month)}';
      case AgendaView.day:
        final dia = _selectedDay ?? _soloFecha(_focusedDay);
        return 'Agenda del ${dia.day} de ${_nombreMes(dia.month).toLowerCase()}';
    }
  }

  Widget _buildViewOption(AgendaView view, ThemeData theme, bool wide) {
    final selected = _vista == view;

    final bg = selected
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surface;

    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.dividerColor.withOpacity(0.45);

    final fg = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => setState(() => _vista = view),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: wide ? 14 : 12,
          vertical: wide ? 14 : 12,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: borderColor,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                    color: theme.colorScheme.primary.withOpacity(0.12),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: wide ? 42 : 38,
              height: wide ? 42 : 38,
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primary.withOpacity(0.12)
                    : theme.colorScheme.surfaceVariant.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _viewIcon(view),
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.78),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _viewTitle(view),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: wide ? 14 : 13,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _viewSubtitle(view),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurface.withOpacity(0.66),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primary.withOpacity(0.12)
                    : theme.colorScheme.surfaceVariant.withOpacity(0.55),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _viewBadge(view),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.72),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MenuPerms>(
      valueListenable: AuthController.menuPerms,
      builder: (context, perms, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: AuthController.puedeCrearNoticias,
          builder: (context, showFabCrear, _) {
            final effectivePerms = widget.esAdmin ? perms : const MenuPerms();
            final showDrawer = widget.esAdmin;

            return Scaffold(
              appBar: AppBar(
                title: Text('Agenda de ${widget.reporteroNombre}'),
                actions: [
                  if (widget.esAdmin && kIsWeb)
                  CompositedTransformTarget(
                    link: _notifLayerLink,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          key: _notifButtonKey,
                          icon: const Icon(Icons.notifications_outlined),
                          tooltip: 'Notificaciones',
                          onPressed: _toggleNotifOverlay,
                        ),
                        if (_notifUnreadCount > 0)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: [
                                  BoxShadow(
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                    color: Colors.black.withOpacity(0.18),
                                  ),
                                ],
                              ),
                              child: Text(
                                _notifUnreadCount > 99 ? '99+' : '$_notifUnreadCount',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Actualizar',
                    onPressed: _loading
                        ? null
                        : () async {
                            _cerrarNotifOverlay();
                            await _refrescarPerfilDesdeServidor(showError: false);
                            await _cargarNoticias();
                            if (widget.esAdmin && kIsWeb) {
                              await _cargarNotificacionesAdmin(silent: true);
                            }
                          },
                  ),
                ],
              ),
              drawer: showDrawer ? _buildDrawerByPerms(effectivePerms) : null,
              body: _wrapWebWidth(_buildBody(showFabCrear: showFabCrear)),
              floatingActionButton: showFabCrear
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton.extended(
                          heroTag: 'fab_crear_noticia',
                          icon: const Icon(Icons.add),
                          label: const Text('Crear noticia'),
                          onPressed: () async {
                            final creado = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const CrearNoticiaPage()),
                            );
                            if (creado == true) {
                              await _refrescarPerfilDesdeServidor(showError: false);
                              await _cargarNoticias();
                            }
                          },
                        ),
                        if (widget.esAdmin) ...[
                          const SizedBox(width: 12),
                          FloatingActionButton.extended(
                            heroTag: 'fab_crear_aviso',
                            icon: const Icon(Icons.notifications),
                            label: const Text('Crear avisos'),
                            onPressed: _abrirCrearAvisoDialog,
                          ),
                        ],
                      ],
                    )
                  : null,
            );
          },
        );
      },
    );
  }

  Widget _buildBody({required bool showFabCrear}) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text(_error!));
    }

    if (_eventosPorDia.isEmpty) {
      return const Center(child: Text('No hay citas registradas en la agenda.'));
    }

    return Container(
      color: kIsWeb ? theme.colorScheme.surface : null,
      child: Column(
        children: [
          const SizedBox(height: 10),
          _buildSelectorVista(),
          const SizedBox(height: 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: KeyedSubtree(
                key: ValueKey(_vista),
                child: _buildVistaActual(showFabCrear: showFabCrear),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorVista() {
    final theme = Theme.of(context);
    final wide = _isWebWide(context);
    if (!wide) {
      final segmented = SegmentedButton<AgendaView>(
        segments: const [
          ButtonSegment(
            value: AgendaView.year,
            label: Text('Año'),
            icon: Icon(Icons.calendar_view_month),
          ),
          ButtonSegment(
            value: AgendaView.month,
            label: Text('Mes'),
            icon: Icon(Icons.calendar_month),
          ),
          ButtonSegment(
            value: AgendaView.day,
            label: Text('Día'),
            icon: Icon(Icons.view_day),
          ),
        ],
        selected: <AgendaView>{_vista},
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          padding: MaterialStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        onSelectionChanged: (set) {
          setState(() => _vista = set.first);
        },
      );

      return Padding(
        padding: EdgeInsets.symmetric(horizontal: _selectorHPad(context)),
        child: _cardShell(
          elevation: 0,
          color: theme.colorScheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              const SizedBox(width: 10),
              Expanded(child: segmented),
            ],
          ),
        ),
      );
    }

    // En web / escritorio: mantener el selector nuevo
    final options = Row(
      children: [
        Expanded(child: _buildViewOption(AgendaView.year, theme, wide)),
        const SizedBox(width: 10),
        Expanded(child: _buildViewOption(AgendaView.month, theme, wide)),
        const SizedBox(width: 10),
        Expanded(child: _buildViewOption(AgendaView.day, theme, wide)),
      ],
    );

    final shell = _cardShell(
      elevation: 0,
      color: theme.colorScheme.surface,
      padding: EdgeInsets.symmetric(
        horizontal: wide ? 12 : 10,
        vertical: wide ? 12 : 10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
            child: Text(
              _contextLabel(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          options,
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _selectorHPad(context)),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: shell,
        ),
      ),
    );
  }

  Widget _buildVistaActual({required bool showFabCrear}) {
    switch (_vista) {
      case AgendaView.year:
        return _buildVistaYear(showFabCrear: showFabCrear);
      case AgendaView.month:
        return _buildVistaMonth(showFabCrear: showFabCrear);
      case AgendaView.day:
        return _buildVistaDay(showFabCrear: showFabCrear);
    }
  }

  // ---------- Vista Año ----------
  Widget _buildVistaYear({required bool showFabCrear}) {
    final year = _focusedDay.year;
    final theme = Theme.of(context);

    final Map<int, int> eventosPorMes = {};
    _eventosPorDia.forEach((fecha, lista) {
      if (fecha.year == year) {
        eventosPorMes.update(
          fecha.month,
          (value) => value + lista.length,
          ifAbsent: () => lista.length,
        );
      }
    });

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _hPad(context)),
          child: _cardShell(
            elevation: 0.5,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Año anterior',
                  onPressed: () {
                    setState(() {
                      _focusedDay = DateTime(year - 1, _selectedMonthInYear, 1);
                    });
                  },
                ),
                Text(
                  '$year',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Año siguiente',
                  onPressed: () {
                    setState(() {
                      _focusedDay = DateTime(year + 1, _selectedMonthInYear, 1);
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Builder(
            builder: (context) {
              final bottomSafe = MediaQuery.of(context).padding.bottom;
              final fabClearance = showFabCrear ? 110.0 : 0.0;

              return LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  int crossAxisCount = 3;
                  double aspect = 0.90;

                  if (kIsWeb) {
                    if (w >= 1200) {
                      crossAxisCount = 6;
                      aspect = 1.12;
                    } else if (w >= 980) {
                      crossAxisCount = 5;
                      aspect = 1.06;
                    } else if (w >= 720) {
                      crossAxisCount = 4;
                      aspect = 0.98;
                    }
                  }

                  final grid = GridView.builder(
                    padding: EdgeInsets.fromLTRB(
                      _hPad(context),
                      2,
                      _hPad(context),
                      8 + fabClearance + bottomSafe,
                    ),
                    physics: const AlwaysScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: aspect,
                    ),
                    itemCount: 12,
                    itemBuilder: (context, index) {
                      final month = index + 1;
                      final count = eventosPorMes[month] ?? 0;
                      final nombreMes = _nombreMes(month);
                      final bool tieneEventos = count > 0;
                      final bool esSeleccionado = month == _selectedMonthInYear;

                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          setState(() {
                            _focusedDay = DateTime(year, month, 1);
                            _vista = AgendaView.month;
                            _selectedMonthInYear = month;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: esSeleccionado
                                ? theme.colorScheme.primaryContainer
                                : tieneEventos
                                    ? theme.colorScheme.primaryContainer.withOpacity(0.75)
                                    : theme.colorScheme.surface,
                            border: Border.all(
                              color: esSeleccionado
                                  ? theme.colorScheme.primary
                                  : (tieneEventos ? theme.colorScheme.primary : theme.dividerColor),
                              width: esSeleccionado ? 2.0 : (tieneEventos ? 1.2 : 0.8),
                            ),
                            boxShadow: [
                              BoxShadow(
                                blurRadius: esSeleccionado ? 7 : 4,
                                offset: const Offset(0, 2),
                                color: Colors.black.withOpacity(esSeleccionado ? 0.14 : 0.07),
                              )
                            ],
                          ),
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Builder(
                                builder: (context) {
                                  final efem = efemerideMes(month, theme);
                                  return Tooltip(
                                    message: efem.tooltip,
                                    child: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: efem.color,
                                      child: Icon(efem.icon, size: 18, color: Colors.white),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 10),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  nombreMes,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceVariant.withOpacity(0.55),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  tieneEventos ? '$count noticias' : 'Sin noticias',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: tieneEventos
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface.withOpacity(0.70),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );

                  return _maybeScrollbar(child: grid);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------- Vista Mes ----------
  Widget _buildVistaMonth({required bool showFabCrear}) {
    final theme = Theme.of(context);
    final eventosMes = _eventosDelMes(_focusedDay);
    final wide = _isWebWide(context);

    int cmpFecha(Noticia a, Noticia b) {
      final da = a.fechaCita ?? DateTime(9999);
      final db = b.fechaCita ?? DateTime(9999);
      final c = da.compareTo(db);
      if (c != 0) return c;
      return a.id.compareTo(b.id);
    }

    final pendientes = eventosMes.where((n) => n.pendiente == true).toList()..sort(cmpFecha);
    final cerradas = eventosMes.where((n) => n.pendiente == false).toList()..sort(cmpFecha);
    final eventosMesOrdenados = [...pendientes, ...cerradas];

    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final fabClearance = showFabCrear ? 110.0 : 0.0;

    Widget buildCalendarCard() {
      return _cardShell(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (context, calConstraints) {
            final double rowHeight;

            if (wide) {
              final double headerAndWeekdaysApprox = 100.0;
              const int rows = 6;
              final double computedRowHeight =
                  (calConstraints.maxHeight - headerAndWeekdaysApprox) / rows;

              rowHeight = computedRowHeight.clamp(32.0, 54.0).toDouble();
            } else {
              // En móvil, fijo y compacto para evitar overflow
              rowHeight = 36.0;
            }

            return TableCalendar<Noticia>(
              locale: 'es_MX',
              firstDay: DateTime.utc(2000, 1, 1),
              lastDay: DateTime.utc(2100, 12, 31),
              focusedDay: _focusedDay,
              startingDayOfWeek: StartingDayOfWeek.monday,
              calendarFormat: CalendarFormat.month,
              rowHeight: rowHeight,
              daysOfWeekHeight: wide ? 20 : 16,
              selectedDayPredicate: (day) =>
                  _selectedDay != null && _soloFecha(day) == _soloFecha(_selectedDay!),
              eventLoader: _eventosDeDia,
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = _soloFecha(selectedDay);
                  _focusedDay = focusedDay;
                  _selectedMonthInYear = focusedDay.month;
                  _vista = AgendaView.day;
                });
              },
              onPageChanged: (focusedDay) {
                setState(() {
                  _focusedDay = focusedDay;
                  _selectedMonthInYear = focusedDay.month;
                });
              },
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                cellMargin: EdgeInsets.zero,
                cellPadding: EdgeInsets.zero,
                markersAlignment: Alignment.bottomRight,
                markersMaxCount: 1,
              ),
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: TextStyle(
                  fontSize: wide ? 17 : 16,
                  fontWeight: FontWeight.bold,
                ),
                titleTextFormatter: (date, locale) {
                  final mes = _nombreMes(date.month);
                  return '$mes ${date.year}';
                },
                leftChevronIcon: const Icon(Icons.chevron_left),
                rightChevronIcon: const Icon(Icons.chevron_right),
                headerPadding: const EdgeInsets.symmetric(vertical: 6),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                ),
                weekendStyle: TextStyle(
                  color: theme.colorScheme.error.withOpacity(0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (context, day, focusedDay) => _calDayCell(
                  theme: theme,
                  day: day,
                  wide: wide,
                ),
                todayBuilder: (context, day, focusedDay) => _calDayCell(
                  theme: theme,
                  day: day,
                  wide: wide,
                  isToday: true,
                ),
                selectedBuilder: (context, day, focusedDay) => _calDayCell(
                  theme: theme,
                  day: day,
                  wide: wide,
                  isSelected: true,
                ),
                outsideBuilder: (context, day, focusedDay) => _calDayCell(
                  theme: theme,
                  day: day,
                  wide: wide,
                  isOutside: true,
                ),
                markerBuilder: (context, day, events) {
                  if (events.isEmpty) return const SizedBox.shrink();
                  final count = events.length;

                  return Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 6 : 5,
                        vertical: wide ? 2 : 1,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                            color: Colors.black.withOpacity(0.10),
                          ),
                        ],
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: wide ? 10 : 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      );                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                
    }

    Widget buildListCard() {
      final list = eventosMes.isEmpty
          ? const Center(child: Text('No hay noticias registradas en este mes.'))
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(0, 6, 0, 10 + fabClearance + bottomSafe),
              itemCount: eventosMesOrdenados.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final n = eventosMesOrdenados[index];
                final fecha = n.fechaCita != null ? _formatearFechaCorta(n.fechaCita!) : 'Sin fecha';
                final bool cerrada = (n.pendiente == false);

                return ListTile(
                  dense: true,
                  visualDensity: kIsWeb ? VisualDensity.compact : null,
                  leading: Icon(
                    cerrada ? Icons.check_circle : Icons.schedule,
                    color: cerrada ? theme.colorScheme.secondary : theme.colorScheme.primary,
                  ),
                  title: Text(
                    n.noticia,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Fecha: $fecha',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NoticiaDetallePage(
                          noticia: n,
                          soloLectura: (n.pendiente == false),
                          role: widget.esAdmin ? 'admin' : 'reportero',
                        ),
                      ),
                    );
                    await _cargarNoticias();
                  },
                );
              },
            );

      return _cardShell(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_nombreMes(_focusedDay.month)} ${_focusedDay.year}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: wide ? 15 : 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${eventosMesOrdenados.length} noticias',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _maybeScrollbar(child: list)),
          ],
        ),
      );
    }

    if (wide) {
      return Padding(
        padding: EdgeInsets.fromLTRB(_hPad(context), 0, _hPad(context), 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 6, child: buildCalendarCard()),
            VerticalDivider(
              width: 14,
              thickness: 1,
              color: theme.dividerColor.withOpacity(0.20),
            ),
            Expanded(flex: 5, child: buildListCard()),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const double calendarFactor = 0.55;

        final double totalH = constraints.maxHeight;
        final double calendarH = totalH * calendarFactor;
        final double listH = totalH - calendarH - 10;

        return Column(
          children: [
            SizedBox(
              height: calendarH,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: _hPad(context)),
                child: buildCalendarCard(),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: listH < 0 ? 0 : listH,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: _hPad(context)),
                child: buildListCard(),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------- Vista Día ----------
  Widget _buildVistaDay({required bool showFabCrear}) {
    final dia = _selectedDay ?? _soloFecha(DateTime.now());
    final eventos = _eventosDeDia(dia);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final fabClearance = showFabCrear ? 110.0 : 0.0;
    final wide = _isWebWide(context);
    final canModifyAgenda = showFabCrear && eventos.isNotEmpty;

    final header = _cardShell(
      elevation: 0,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: wide ? 14 : 12),
      color: isDark
          ? theme.colorScheme.surface
          : theme.colorScheme.surfaceVariant.withOpacity(0.35),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: Text(
              '${_nombreMes(dia.month)} ${dia.day}, ${dia.year}',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: wide ? 17 : 16,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (canModifyAgenda)
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!_modoModificarJornada)
                    OutlinedButton.icon(
                      onPressed: _entrarModoModificarJornada,
                      icon: const Icon(Icons.edit_calendar),
                      label: const Text('Modificar'),
                    )
                  else ...[
                    TextButton(
                      onPressed: _savingCambiosAgenda
                          ? null
                          : _cancelarModificacionJornada,
                      child: const Text('Cancelar'),
                    ),
                    FilledButton.icon(
                      onPressed: (!_hayCambiosAgenda || _savingCambiosAgenda)
                          ? null
                          : _guardarCambiosJornada,
                      icon: _savingCambiosAgenda
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: const Text('Guardar cambios'),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );

    const double hourHeight = 88;
    const double timeLabelWidth = 62;
    const double minCardHeight = 92;
    final totalHeight = hourHeight * 24;
    final hourFmt = DateFormat('h a', 'es_MX');

    int eventDurationMinutes(Noticia noticia) => _eventDurationMinutes(noticia);

    Future<void> openDetalle(Noticia noticia) async {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NoticiaDetallePage(
            noticia: noticia,
            soloLectura: (noticia.pendiente == false),
            role: widget.esAdmin ? 'admin' : 'reportero',
          ),
        ),
      );
      await _cargarNoticias();
    }

    final eventosOrdenados = [...eventos]..sort((a, b) {
      final da = _fechaCitaVisible(a);
      final db = _fechaCitaVisible(b);
      final c = da.compareTo(db);
      if (c != 0) return c;
      return a.id.compareTo(b.id);
    });

    final draggingId = _draggingNoticiaId;

    Noticia? draggingNoticia;
    if (draggingId != null) {
      for (final n in eventosOrdenados) {
        if (n.id == draggingId) {
          draggingNoticia = n;
          break;
        }
      }
    }

    final layoutItems = _buildStableDayLayout(
      eventosOrdenados,
      eventDurationMinutes,
    );

    _AgendaDayLayoutItem? draggingLayoutItem;
    if (draggingId != null) {
      for (final item in layoutItems) {
        if (item.noticia.id == draggingId) {
          draggingLayoutItem = item;
          break;
        }
      }
    }

    final agenda = _cardShell(
      padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
      child: eventos.isEmpty
          ? SizedBox(
              height: 260,
              child: Center(
                child: Text(
                  'No hay noticias para este día.',
                  style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.70)),
                ),
              ),
            )
          : SingleChildScrollView(
              padding: EdgeInsets.only(bottom: 16 + fabClearance + bottomSafe),
              physics: _modoModificarJornada
                ? const NeverScrollableScrollPhysics()
                : const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: totalHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: timeLabelWidth,
                      child: Column(
                        children: List.generate(24, (hour) {
                          final hourDate = DateTime(dia.year, dia.month, dia.day, hour);
                          return SizedBox(
                            height: hourHeight,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  hourFmt.format(hourDate).toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.onSurface.withOpacity(0.72),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const double gap = 6;

                          return Stack(
                            key: _agendaGridKey,
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: Column(
                                  children: List.generate(24, (hour) {
                                    return Container(
                                      height: hourHeight,
                                      decoration: BoxDecoration(
                                        border: Border(
                                          top: BorderSide(
                                            color: theme.dividerColor.withOpacity(0.28),
                                          ),
                                        ),
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Container(
                                          margin: const EdgeInsets.only(top: 44),
                                          height: hour == 23 ? 0 : 1,
                                          color: theme.dividerColor.withOpacity(0.12),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                        color: theme.dividerColor.withOpacity(0.30),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              for (final item in layoutItems)
                                () {
                                  final noticia = item.noticia;
                                  final start = _fechaCitaVisible(noticia);
                                  final bool cerrada = noticia.pendiente == false;
                                  final top = (item.startMinutes / 60) * hourHeight;
                                  final height = (((item.endMinutes - item.startMinutes) / 60) *
                                          hourHeight)
                                      .clamp(minCardHeight, totalHeight);
                                  final columns = item.totalColumns > 0 ? item.totalColumns : 1;
                                  final width =
                                      (constraints.maxWidth - ((columns - 1) * gap)) / columns;
                                  final left = (item.column * (width + gap)).toDouble();
                                  final isDraggingThis =
                                      _modoModificarJornada && _draggingNoticiaId == noticia.id;
                                  return AnimatedPositioned(
                                    key: ValueKey('agenda_item_${noticia.id}'),
                                    duration: const Duration(milliseconds: 160),
                                    curve: Curves.easeOutCubic,
                                    top: top,
                                    left: left,
                                    width: width,
                                    height: height,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onVerticalDragStart: _modoModificarJornada
                                            ? (details) => _beginAgendaItemDrag(
                                                  noticia,
                                                  item,
                                                  details,
                                                  hourHeight,
                                                  totalHeight,
                                                )
                                            : null,
                                        onVerticalDragUpdate: _modoModificarJornada
                                            ? (details) => _updateFloatingAgendaDrag(
                                                  noticia,
                                                  details.globalPosition,
                                                  hourHeight,
                                                  totalHeight,
                                                )
                                            : null,
                                        onVerticalDragEnd: _modoModificarJornada
                                            ? (_) => _onAgendaItemDragEnd()
                                            : null,
                                        onVerticalDragCancel: _modoModificarJornada
                                            ? _onAgendaItemDragEnd
                                            : null,
                                        child: isDraggingThis
                                            ? _buildAgendaDropPlaceholder(
                                                theme: theme,
                                                isDark: isDark,
                                                noticia: noticia,
                                                cerrada: cerrada,
                                                horaTexto: _fmtHoraMin(item.startMinutes),
                                              )
                                            : InkWell(
                                                borderRadius: BorderRadius.circular(16),
                                                onTap: _modoModificarJornada ? null : () => openDetalle(noticia),
                                                child: Builder(
                                                  builder: (context) {
                                                    final reporterBg =
                                                        _reporteroBgColor(noticia.reportero, theme, isDark);
                                                    final reporterAccent =
                                                        _reporteroAccentColor(noticia.reportero, theme);
                                                    final reporterText = _readableTextOn(reporterBg);

                                                    final statusText = cerrada ? 'Cerrada' : 'Pendiente';
                                                    final statusFg = cerrada
                                                        ? theme.colorScheme.secondary
                                                        : theme.colorScheme.primary;
                                                    final statusBg = cerrada
                                                        ? theme.colorScheme.secondary.withOpacity(
                                                            isDark ? 0.22 : 0.14,
                                                          )
                                                        : theme.colorScheme.primary.withOpacity(
                                                            isDark ? 0.22 : 0.12,
                                                          );

                                                    return Container(
                                                      padding: const EdgeInsets.all(8),
                                                      decoration: BoxDecoration(
                                                        color: reporterBg,
                                                        borderRadius: BorderRadius.circular(16),
                                                        border: Border.all(
                                                          color: reporterAccent,
                                                          width: 1.2,
                                                        ),
                                                        boxShadow: [
                                                          BoxShadow(
                                                            blurRadius: 8,
                                                            offset: const Offset(0, 3),
                                                            color: Colors.black.withOpacity(
                                                              isDark ? 0.20 : 0.07,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      child: LayoutBuilder(
                                                        builder: (context, cardConstraints) {
                                                          final compact = cardConstraints.maxWidth < 150;

                                                          return DefaultTextStyle(
                                                            style: TextStyle(color: reporterText),
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                if (_modoModificarJornada)
                                                                  Align(
                                                                    alignment: Alignment.topRight,
                                                                    child: Icon(
                                                                      Icons.drag_indicator,
                                                                      size: 16,
                                                                      color: reporterText.withOpacity(0.70),
                                                                    ),
                                                                  ),
                                                                if (_modoModificarJornada)
                                                                  const SizedBox(height: 2),
                                                                Text(
                                                                  noticia.noticia,
                                                                  maxLines: compact ? 2 : 3,
                                                                  overflow: TextOverflow.ellipsis,
                                                                  style: TextStyle(
                                                                    fontWeight: FontWeight.w900,
                                                                    fontSize: compact ? 11.5 : 12.8,
                                                                    height: 1.12,
                                                                    color: reporterText,
                                                                  ),
                                                                ),
                                                                const SizedBox(height: 5),
                                                                Text(
                                                                  noticia.reportero.trim().isEmpty
                                                                      ? 'Sin reportero'
                                                                      : noticia.reportero,
                                                                  maxLines: 1,
                                                                  overflow: TextOverflow.ellipsis,
                                                                  style: TextStyle(
                                                                    fontSize: compact ? 10.2 : 11,
                                                                    fontWeight: FontWeight.w700,
                                                                    color: reporterText.withOpacity(0.90),
                                                                  ),
                                                                ),
                                                                const Spacer(),
                                                                Align(
                                                                  alignment: Alignment.centerLeft,
                                                                  child: Container(
                                                                    padding: EdgeInsets.symmetric(
                                                                      horizontal: compact ? 7 : 8,
                                                                      vertical: compact ? 3 : 4,
                                                                    ),
                                                                    decoration: BoxDecoration(
                                                                      color: statusBg,
                                                                      borderRadius: BorderRadius.circular(999),
                                                                      border: Border.all(
                                                                        color: statusFg.withOpacity(0.25),
                                                                        width: 0.8,
                                                                      ),
                                                                    ),
                                                                    child: Text(
                                                                      statusText,
                                                                      maxLines: 1,
                                                                      overflow: TextOverflow.ellipsis,
                                                                      style: TextStyle(
                                                                        fontSize: compact ? 9.6 : 10.4,
                                                                        fontWeight: FontWeight.w800,
                                                                        color: statusFg,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                      ),
                                    ),
                                  );
                                }(),

                                if (_modoModificarJornada && draggingNoticia != null)
                                () {
                                  final noticia = draggingNoticia!;
                                  final cerrada = noticia.pendiente == false;

                                  final previewFecha = _fechaCitaVisible(noticia);
                                  final previewMinutes = previewFecha.hour * 60 + previewFecha.minute;

                                  final rawHeight = ((_eventDurationMinutes(noticia) / 60.0) * hourHeight);
                                  final height = rawHeight.clamp(minCardHeight, totalHeight.toDouble());

                                  final topMinutes =
                                      _dragPreviewStartMinutes ?? previewMinutes.toDouble();
                                  final rawTop = (topMinutes / 60) * hourHeight;
                                  final top = rawTop.clamp(0.0, totalHeight - height);

                                  final lockedColumns =
                                      (_dragLockedTotalColumns ?? 1).clamp(1, 12).toInt();
                                  final lockedColumn =
                                      (_dragLockedColumn ?? 0).clamp(0, lockedColumns - 1).toInt();

                                  final width =
                                      (constraints.maxWidth - ((lockedColumns - 1) * gap)) / lockedColumns;
                                  final left = (lockedColumn * (width + gap)).toDouble();

                                  final chipTop = (top - 30).clamp(4.0, totalHeight - 30);
                                  final chipLeft = left.clamp(4.0, constraints.maxWidth - 90.0);

                                  return Positioned.fill(
                                    child: Listener(
                                      behavior: HitTestBehavior.translucent,
                                      onPointerMove: (event) => _updateFloatingAgendaDrag(
                                        noticia,
                                        event.position,
                                        hourHeight,
                                        totalHeight,
                                      ),
                                      onPointerUp: (_) => _onAgendaItemDragEnd(),
                                      onPointerCancel: (_) => _onAgendaItemDragEnd(),
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Positioned(
                                            top: top,
                                            left: left,
                                            width: width,
                                            height: height,
                                            child: IgnorePointer(
                                              child: Opacity(
                                                opacity: 0.72,
                                                child: Builder(
                                                  builder: (context) {
                                                    final reporterBg =
                                                        _reporteroBgColor(noticia.reportero, theme, isDark);
                                                    final reporterAccent =
                                                        _reporteroAccentColor(noticia.reportero, theme);
                                                    final reporterText = _readableTextOn(reporterBg);

                                                    final statusText = cerrada ? 'Cerrada' : 'Pendiente';
                                                    final statusFg = cerrada
                                                        ? theme.colorScheme.secondary
                                                        : theme.colorScheme.primary;
                                                    final statusBg = cerrada
                                                        ? theme.colorScheme.secondary.withOpacity(
                                                            isDark ? 0.22 : 0.14,
                                                          )
                                                        : theme.colorScheme.primary.withOpacity(
                                                            isDark ? 0.22 : 0.12,
                                                          );

                                                    return Container(
                                                      padding: const EdgeInsets.all(8),
                                                      decoration: BoxDecoration(
                                                        color: reporterBg,
                                                        borderRadius: BorderRadius.circular(16),
                                                        border: Border.all(
                                                          color: reporterAccent,
                                                          width: 1.6,
                                                        ),
                                                        boxShadow: [
                                                          BoxShadow(
                                                            blurRadius: 12,
                                                            offset: const Offset(0, 4),
                                                            color: Colors.black.withOpacity(
                                                              isDark ? 0.24 : 0.10,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      child: LayoutBuilder(
                                                        builder: (context, cardConstraints) {
                                                          final compact = cardConstraints.maxWidth < 150;

                                                          return DefaultTextStyle(
                                                            style: TextStyle(color: reporterText),
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                Align(
                                                                  alignment: Alignment.topRight,
                                                                  child: Icon(
                                                                    Icons.drag_indicator,
                                                                    size: 16,
                                                                    color: reporterText.withOpacity(0.75),
                                                                  ),
                                                                ),
                                                                const SizedBox(height: 2),
                                                                Text(
                                                                  noticia.noticia,
                                                                  maxLines: compact ? 2 : 3,
                                                                  overflow: TextOverflow.ellipsis,
                                                                  style: TextStyle(
                                                                    fontWeight: FontWeight.w900,
                                                                    fontSize: compact ? 11.5 : 12.8,
                                                                    height: 1.12,
                                                                    color: reporterText,
                                                                  ),
                                                                ),
                                                                const SizedBox(height: 5),
                                                                Text(
                                                                  noticia.reportero.trim().isEmpty
                                                                      ? 'Sin reportero'
                                                                      : noticia.reportero,
                                                                  maxLines: 1,
                                                                  overflow: TextOverflow.ellipsis,
                                                                  style: TextStyle(
                                                                    fontSize: compact ? 10.2 : 11,
                                                                    fontWeight: FontWeight.w700,
                                                                    color: reporterText.withOpacity(0.90),
                                                                  ),
                                                                ),
                                                                const Spacer(),
                                                                Align(
                                                                  alignment: Alignment.centerLeft,
                                                                  child: Container(
                                                                    padding: EdgeInsets.symmetric(
                                                                      horizontal: compact ? 7 : 8,
                                                                      vertical: compact ? 3 : 4,
                                                                    ),
                                                                    decoration: BoxDecoration(
                                                                      color: statusBg,
                                                                      borderRadius: BorderRadius.circular(999),
                                                                      border: Border.all(
                                                                        color: statusFg.withOpacity(0.25),
                                                                        width: 0.8,
                                                                      ),
                                                                    ),
                                                                    child: Text(
                                                                      statusText,
                                                                      maxLines: 1,
                                                                      overflow: TextOverflow.ellipsis,
                                                                      style: TextStyle(
                                                                        fontSize: compact ? 9.6 : 10.4,
                                                                        fontWeight: FontWeight.w800,
                                                                        color: statusFg,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: chipTop,
                                            left: chipLeft,
                                            child: IgnorePointer(
                                              child: Material(
                                                elevation: 4,
                                                color: theme.colorScheme.inverseSurface,
                                                borderRadius: BorderRadius.circular(999),
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                                  child: Text(
                                                    _fmtHoraMin(previewMinutes),
                                                    style: TextStyle(
                                                      color: theme.colorScheme.onInverseSurface,
                                                      fontWeight: FontWeight.w800,
                                                      fontSize: 11.5,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }(),
                                if (draggingNoticia != null && draggingLayoutItem != null)
                                () {
                                  final noticia = draggingNoticia!;
                                  final bool cerrada = noticia.pendiente == false;

                                  final rawHeight =
                                      ((_eventDurationMinutes(noticia) / 60) * hourHeight);
                                  final height = rawHeight.clamp(minCardHeight, totalHeight.toDouble());

                                  final topMinutes =
                                      _dragPreviewStartMinutes ??
                                      (noticia.fechaCita!.hour * 60 + noticia.fechaCita!.minute).toDouble();

                                  final rawTop = (topMinutes / 60) * hourHeight;
                                  final top = rawTop.clamp(0.0, totalHeight - height);

                                  final columns =
                                      draggingLayoutItem!.totalColumns > 0 ? draggingLayoutItem!.totalColumns : 1;
                                  final width =
                                      (constraints.maxWidth - ((columns - 1) * gap)) / columns;
                                  final left = (draggingLayoutItem!.column * (width + gap)).toDouble();

                                  final reporterBg =
                                      _reporteroBgColor(noticia.reportero, theme, isDark);
                                  final reporterAccent =
                                      _reporteroAccentColor(noticia.reportero, theme);
                                  final reporterText = _readableTextOn(reporterBg);

                                  final statusText = cerrada ? 'Cerrada' : 'Pendiente';
                                  final statusFg = cerrada
                                      ? theme.colorScheme.secondary
                                      : theme.colorScheme.primary;
                                  final statusBg = cerrada
                                      ? theme.colorScheme.secondary.withOpacity(isDark ? 0.22 : 0.14)
                                      : theme.colorScheme.primary.withOpacity(isDark ? 0.22 : 0.12);

                                  return Positioned(
                                    top: top,
                                    left: left,
                                    width: width,
                                    height: height,
                                    child: IgnorePointer(
                                      ignoring: true,
                                      child: Opacity(
                                        opacity: 0.74,
                                        child: Material(
                                          color: Colors.transparent,
                                          elevation: 10,
                                          borderRadius: BorderRadius.circular(16),
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: reporterBg,
                                              borderRadius: BorderRadius.circular(16),
                                              border: Border.all(
                                                color: reporterAccent,
                                                width: 1.5,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  blurRadius: 12,
                                                  offset: const Offset(0, 4),
                                                  color: Colors.black.withOpacity(isDark ? 0.26 : 0.12),
                                                ),
                                              ],
                                            ),
                                            child: LayoutBuilder(
                                              builder: (context, cardConstraints) {
                                                final compact = cardConstraints.maxWidth < 150;

                                                return DefaultTextStyle(
                                                  style: TextStyle(color: reporterText),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Align(
                                                        alignment: Alignment.topRight,
                                                        child: Icon(
                                                          Icons.drag_indicator,
                                                          size: 16,
                                                          color: reporterText.withOpacity(0.70),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        noticia.noticia,
                                                        maxLines: compact ? 2 : 3,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.w900,
                                                          fontSize: compact ? 11.5 : 12.8,
                                                          height: 1.12,
                                                          color: reporterText,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 5),
                                                      Text(
                                                        noticia.reportero.trim().isEmpty
                                                            ? 'Sin reportero'
                                                            : noticia.reportero,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          fontSize: compact ? 10.2 : 11,
                                                          fontWeight: FontWeight.w700,
                                                          color: reporterText.withOpacity(0.90),
                                                        ),
                                                      ),
                                                      const Spacer(),
                                                      Wrap(
                                                        spacing: 6,
                                                        runSpacing: 6,
                                                        children: [
                                                          Container(
                                                            padding: EdgeInsets.symmetric(
                                                              horizontal: compact ? 7 : 8,
                                                              vertical: compact ? 3 : 4,
                                                            ),
                                                            decoration: BoxDecoration(
                                                              color: reporterAccent.withOpacity(isDark ? 0.22 : 0.14),
                                                              borderRadius: BorderRadius.circular(999),
                                                            ),
                                                            child: Text(
                                                              _fmtHoraMin(draggingLayoutItem!.startMinutes),
                                                              style: TextStyle(
                                                                fontSize: compact ? 9.6 : 10.4,
                                                                fontWeight: FontWeight.w800,
                                                                color: reporterAccent,
                                                              ),
                                                            ),
                                                          ),
                                                          Container(
                                                            padding: EdgeInsets.symmetric(
                                                              horizontal: compact ? 7 : 8,
                                                              vertical: compact ? 3 : 4,
                                                            ),
                                                            decoration: BoxDecoration(
                                                              color: statusBg,
                                                              borderRadius: BorderRadius.circular(999),
                                                              border: Border.all(
                                                                color: statusFg.withOpacity(0.25),
                                                                width: 0.8,
                                                              ),
                                                            ),
                                                            child: Text(
                                                              statusText,
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: TextStyle(
                                                                fontSize: compact ? 9.6 : 10.4,
                                                                fontWeight: FontWeight.w800,
                                                                color: statusFg,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }(),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );

    if (wide) {
      final side = _daySidePanel(theme: theme, dia: dia, eventos: eventos);

      return Padding(
        padding: EdgeInsets.fromLTRB(_hPad(context), 0, _hPad(context), 10),
        child: Column(
          children: [
            header,
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 8,
                    child: agenda,
                  ),
                  VerticalDivider(
                    width: 14,
                    thickness: 1,
                    color: theme.dividerColor.withOpacity(0.20),
                  ),
                  Expanded(
                    flex: 3,
                    child: _maybeScrollbar(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: side,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(_hPad(context), 0, _hPad(context), 10),
      child: Column(
        children: [
          header,
          const SizedBox(height: 10),
          Expanded(child: agenda),
        ],
      ),
    );
  }
}

class _AgendaPlaceholderPainter extends CustomPainter {
  final Color color;

  _AgendaPlaceholderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    const spacing = 12.0;

    for (double x = -size.height; x < size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AgendaPlaceholderPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}