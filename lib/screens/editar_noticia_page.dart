// lib/screens/editar_noticia_page.dart
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../models/noticia.dart';
import '../services/api_service.dart';

const double _kWebMaxContentWidth = 1200;
const double _kWebWideBreakpoint = 980;

bool _isWebWide(BuildContext context) =>
    kIsWeb && MediaQuery.of(context).size.width >= _kWebWideBreakpoint;

bool _usarHoraPorTexto(BuildContext context) {
  if (kIsWeb) return true;

  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;
}

class _HHmmTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final clamped = digits.length > 4 ? digits.substring(0, 4) : digits;

    String out;
    if (clamped.length <= 2) {
      out = clamped;
    } else if (clamped.length == 3) {
      out = '${clamped.substring(0, 1)}:${clamped.substring(1, 3)}';
    } else {
      out = '${clamped.substring(0, 2)}:${clamped.substring(2, 4)}';
    }

    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}

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

Widget _maybeScrollbar({required Widget child}) {
  if (!kIsWeb) return child;
  return Scrollbar(thumbVisibility: true, interactive: true, child: child);
}

double _hPad(BuildContext context) => _isWebWide(context) ? 20 : 16;

ShapeBorder _softShape(ThemeData theme) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: theme.dividerColor.withOpacity(0.70),
        width: 0.9,
      ),
    );

class EditarNoticiaPage extends StatefulWidget {
  final Noticia noticia;
  final String role;

  const EditarNoticiaPage({
    super.key,
    required this.noticia,
    required this.role,
  });

  @override
  State<EditarNoticiaPage> createState() => _EditarNoticiaPageState();
}

class _EditarNoticiaPageState extends State<EditarNoticiaPage> {
  late final TextEditingController _tituloCtrl;
  late final TextEditingController _descCtrl;

  DateTime? _fechaCita;
  bool _guardando = false;
  String? _error;
  String _tipoDeNota = 'Nota';

  bool get _esAdmin => widget.role == 'admin';
  bool get _yaTieneHoraLlegada => widget.noticia.horaLlegada != null;
  bool get _puedeEditarTipoDeNota =>
      (widget.role == 'admin' || widget.role == 'reportero');

  bool get _descActualVacia {
    final d = widget.noticia.descripcion;
    return d == null || d.trim().isEmpty;
  }

  bool get _puedeEditarDescripcion {
    if (_esAdmin) return true;
    return _descActualVacia;
  }

  bool get _puedeEditarTitulo => _esAdmin;

  bool get _puedeEditarFecha {
    if (_yaTieneHoraLlegada) return false;
    if (_esAdmin) return true;
    return (widget.noticia.fechaCitaCambios < 2);
  }

  String _fmtFechaHora(DateTime dt) {
    return DateFormat("d 'de' MMMM 'de' y, hh:mm a", 'es_MX').format(dt);
  }

  // ===================== TIME PICKERS =====================

  Future<TimeOfDay?> _showTextTimePicker(
    BuildContext context, {
    required TimeOfDay initialTime,
    int minuteInterval = 1,
  }) async {
    bool isPm = initialTime.hour >= 12;
    int hour12 = initialTime.hour % 12;
    if (hour12 == 0) hour12 = 12;

    final ctrl = TextEditingController(
      text:
          '${hour12.toString().padLeft(2, '0')}:${initialTime.minute.toString().padLeft(2, '0')}',
    );

    String? errorText;

    TimeOfDay? parse12hTo24h(String t, bool isPm) {
      final parts = t.split(':');
      if (parts.length != 2) return null;

      final h12 = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);

      if (h12 == null || m == null) return null;

      if (h12 < 1 || h12 > 12) return null;

      if (m < 0 || m > 59) return null;

      if (minuteInterval > 1 && (m % minuteInterval != 0)) return null;

      int h24;
      if (isPm) {
        h24 = (h12 == 12) ? 12 : (h12 + 12);
      } else {
        h24 = (h12 == 12) ? 0 : h12;
      }

      return TimeOfDay(hour: h24, minute: m);
    }

    final ampmCtrl = FixedExtentScrollController(initialItem: isPm ? 1 : 0);

    return showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            void tryAccept() {
              final t = parse12hTo24h(ctrl.text, isPm);
              if (t == null) {
                setModalState(() => errorText =
                    'Hora inválida. Usa formato hh:mm (1–12 : 00–59) y selecciona AM/PM.');
                return;
              }
              Navigator.pop(ctx, t);
            }
            const double boxSize = 124; 
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(18)),
                  ),
                  padding: const EdgeInsets.only(top: 10, bottom: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, null),
                              child: const Text('Cancelar'),
                            ),
                            const Spacer(),
                            Text(
                              'Seleccionar hora',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: tryAccept,
                              child: const Text('Aceptar'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: boxSize,
                              height: boxSize,
                              child: TextField(
                                controller: ctrl,
                                autofocus: true,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => tryAccept(),
                                expands: true, 
                                maxLines: null,
                                minLines: null,
                                inputFormatters: [
                                  _HHmmTextInputFormatter(),
                                  LengthLimitingTextInputFormatter(5),
                                ],
                                textAlign: TextAlign.center,
                                textAlignVertical: TextAlignVertical.center,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Hora (12h)',
                                  hintText: '9:30',
                                  errorText: errorText,
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                ),
                                onChanged: (_) {
                                  if (errorText != null) {
                                    setModalState(() => errorText = null);
                                  }
                                },
                              ),
                            ),

                            const SizedBox(width: 14),

                            SizedBox(
                              width: boxSize * 0.80,
                              height: boxSize,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(color: theme.dividerColor),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: CupertinoPicker(
                                  scrollController: ampmCtrl,
                                  itemExtent: 36,
                                  magnification: 1.08,
                                  useMagnifier: true,
                                  onSelectedItemChanged: (i) {
                                    setModalState(() {
                                      isPm = (i == 1);
                                      if (errorText != null) errorText = null;
                                    });
                                  },
                                  children: const [
                                    Center(child: Text('AM')),
                                    Center(child: Text('PM')),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Tip: escribe, por ejemplo, 930 → 9:30 ó 0930 → 9:30',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }


  Future<TimeOfDay?> _showCarouselTimePicker(
    BuildContext context, {
    required TimeOfDay initialTime,
    int minuteInterval = 1,
  }) async {
    DateTime toDateTime(TimeOfDay t) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, t.hour, t.minute);
    }

    TimeOfDay fromDateTime(DateTime dt) =>
        TimeOfDay(hour: dt.hour, minute: dt.minute);

    DateTime selected = toDateTime(initialTime);

    return showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);

        return SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            padding: const EdgeInsets.only(top: 10, bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, null),
                        child: const Text('Cancelar'),
                      ),
                      const Spacer(),
                      Text(
                        'Seleccionar hora',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(ctx, fromDateTime(selected)),
                        child: const Text('Aceptar'),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 220,
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    use24hFormat: true,
                    minuteInterval: minuteInterval,
                    initialDateTime: selected,
                    onDateTimeChanged: (dt) => selected = dt,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===================== LIFECYCLE =====================

  @override
  void initState() {
    super.initState();
    _tituloCtrl = TextEditingController(text: widget.noticia.noticia);
    _descCtrl = TextEditingController(text: widget.noticia.descripcion ?? '');
    _fechaCita = widget.noticia.fechaCita;
    _tipoDeNota = widget.noticia.tipoDeNota;
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // ===================== LOGIC =====================

  Future<void> _seleccionarFechaHora() async {
    if (!_puedeEditarFecha) return;

    final now = DateTime.now();
    final initial = _fechaCita ?? now;

    final pickedDate = await showDatePicker(
      context: context,
      locale: const Locale('es', 'MX'),
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'Seleccionar fecha',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );

    if (pickedDate == null) return;

    final pickedTime = _usarHoraPorTexto(context)
        ? await _showTextTimePicker(
            context,
            initialTime: TimeOfDay.fromDateTime(initial),
            minuteInterval: 1,
          )
        : await _showCarouselTimePicker(
            context,
            initialTime: TimeOfDay.fromDateTime(initial),
            minuteInterval: 1,
          );

    if (pickedTime == null) return;

    final nueva = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() => _fechaCita = nueva);
  }

  Future<bool> _confirmarChoqueHorario({String? extra}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Advertencia'),
        content: Text(
          'Existe una nota que podría interferir con tu horario, ¿Continuar de todos modos?'
          '${extra != null ? '\n\n$extra' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  bool _huboCambioFecha() {
    final old = widget.noticia.fechaCita;
    final cur = _fechaCita;
    return (old?.toIso8601String() ?? '') != (cur?.toIso8601String() ?? '');
  }

  Future<void> _guardar() async {
    if (_guardando) return;

    setState(() => _error = null);

    final titulo = _tituloCtrl.text.trim();
    final desc = _descCtrl.text.trim();

    if (_esAdmin && titulo.isEmpty) {
      setState(() => _error = 'El título no puede estar vacío.');
      return;
    }

    if (_puedeEditarDescripcion && desc.isEmpty) {
      setState(() => _error = 'La descripción no puede estar vacía.');
      return;
    }

    if (_yaTieneHoraLlegada && _huboCambioFecha()) {
      setState(() => _error =
          'No se puede cambiar la fecha de cita: ya se registró la hora de llegada.');
      return;
    }

    if (!_esAdmin && !_puedeEditarFecha && _huboCambioFecha()) {
      setState(() =>
          _error = 'Límite alcanzado: ya no puedes cambiar la fecha de cita.');
      return;
    }

    final String? tituloSend = _puedeEditarTitulo ? titulo : null;
    final String? descSend = _puedeEditarDescripcion ? desc : null;
    final DateTime? fechaSend = _puedeEditarFecha ? _fechaCita : null;

    final String? tipoSend = _puedeEditarTipoDeNota
        ? (_tipoDeNota != widget.noticia.tipoDeNota ? _tipoDeNota : null)
        : null;

    final nadaQueGuardar = (tituloSend == null) &&
        (descSend == null) &&
        (fechaSend == null) &&
        (tipoSend == null);

    if (nadaQueGuardar) {
      setState(() => _error = 'No tienes cambios para guardar.');
      return;
    }

    final int? reporteroId = widget.noticia.reporteroId;
    final DateTime? fechaFinal =
        _puedeEditarFecha ? _fechaCita : widget.noticia.fechaCita;
    final String tipoFinal = _tipoDeNota;

    if (tipoFinal == 'Entrevista' && fechaFinal != null && reporteroId != null) {
      final choque = await ApiService.buscarChoqueCitaEntrevista(
        reporteroId: reporteroId,
        fechaCita: fechaFinal,
        excludeNoticiaId: widget.noticia.id,
      );

      if (choque != null) {
        final extra = (choque.fechaCita != null)
            ? 'Posible conflicto con: "${choque.noticia}" (${_fmtFechaHora(choque.fechaCita!)})'
            : 'Posible conflicto con: "${choque.noticia}"';

        final continuar = await _confirmarChoqueHorario(extra: extra);
        if (!continuar) return;
      }
    }

    setState(() => _guardando = true);

    try {
      final updated = await ApiService.actualizarNoticia(
        noticiaId: widget.noticia.id,
        role: widget.role,
        titulo: tituloSend,
        descripcion: descSend,
        fechaCita: fechaSend,
        tipoDeNota: tipoSend,
      );

      if (!mounted) return;
      Navigator.pop(context, updated);
    } catch (e) {
      setState(() => _error = 'Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ===================== UI bits =====================

  Widget _chip(ThemeData theme, String text, {Color? bg, Color? fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg ?? theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: fg ?? theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _buildResumenPanel(BuildContext context) {
    final theme = Theme.of(context);

    final anterior = widget.noticia.fechaCitaAnterior;
    final actual = widget.noticia.fechaCita;
    final mostrarAnterior = anterior != null &&
        actual != null &&
        anterior.toIso8601String() != actual.toIso8601String();

    final cambios = widget.noticia.fechaCitaCambios;

    final fechaTxt =
        _fechaCita != null ? _fmtFechaHora(_fechaCita!) : 'Sin fecha de cita';

    final chips = <Widget>[
      _chip(
        theme,
        _puedeEditarTitulo ? 'Título editable' : 'Título bloqueado',
        bg: _puedeEditarTitulo
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceVariant.withOpacity(0.6),
      ),
      _chip(
        theme,
        _puedeEditarDescripcion ? 'Descripción editable' : 'Descripción bloqueada',
        bg: _puedeEditarDescripcion
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceVariant.withOpacity(0.6),
      ),
      _chip(
        theme,
        _puedeEditarFecha ? 'Fecha editable' : 'Fecha bloqueada',
        bg: _puedeEditarFecha
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceVariant.withOpacity(0.6),
      ),
      if (!_esAdmin) _chip(theme, 'Cambios fecha: $cambios/2'),
      if (_yaTieneHoraLlegada)
        _chip(
          theme,
          'Llegada registrada',
          bg: theme.colorScheme.errorContainer,
          fg: theme.colorScheme.onErrorContainer,
        ),
    ];

    return Card(
      elevation: 0.6,
      shape: _softShape(theme),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline),
                const SizedBox(width: 8),
                Text(
                  'Información Rápida',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
            const SizedBox(height: 12),
            Divider(color: theme.dividerColor.withOpacity(0.8), height: 1),
            const SizedBox(height: 12),

            Text(
              'Fecha de cita Actual',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              fechaTxt,
              style: const TextStyle(
                color: Color.fromARGB(255, 26, 120, 202),
                fontWeight: FontWeight.w700,
              ),
            ),
            if (mostrarAnterior) ...[
              const SizedBox(height: 10),
              Text(
                'Fecha de cita Anterior',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                _fmtFechaHora(anterior),
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
              ),
            ],

            const SizedBox(height: 12),
            Divider(color: theme.dividerColor.withOpacity(0.8), height: 1),
            const SizedBox(height: 12),

            Text(
              'Reglas rápidas',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              _esAdmin
                  ? '• Puedes editar título, descripción y fecha.\n'
                  : '• Solo se puede capturar descripción una vez (Si se encuentra vacía).\n'
                    '• Fecha de cita: máximo 2 cambios.\n',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormCard(BuildContext context) {
    final theme = Theme.of(context);

    final anterior = widget.noticia.fechaCitaAnterior;
    final actual = widget.noticia.fechaCita;
    final bool mostrarAnterior = anterior != null &&
        actual != null &&
        anterior.toIso8601String() != actual.toIso8601String();

    final cambios = widget.noticia.fechaCitaCambios;

    return Card(
      elevation: kIsWeb ? 0.6 : 2,
      shape: _softShape(theme),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---------- Rol ----------
            Row(
              children: [
                Icon(_esAdmin ? Icons.admin_panel_settings : Icons.person),
                const SizedBox(width: 8),
                Text(
                  _esAdmin ? 'Modo Admin' : 'Modo Reportero',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _tipoDeNota,
              decoration: InputDecoration(
                labelText: 'Tipo de noticia',
                helperText: _puedeEditarTipoDeNota
                    ? 'Puedes cambiar el tipo.'
                    : 'Solo Admin puede cambiar el tipo.',
                border: const OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Nota', child: Text('Nota')),
                DropdownMenuItem(value: 'Entrevista', child: Text('Entrevista')),
              ],
              onChanged: _puedeEditarTipoDeNota
                  ? (v) => setState(() => _tipoDeNota = v ?? 'Nota')
                  : null,
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _tituloCtrl,
              enabled: _puedeEditarTitulo,
              decoration: InputDecoration(
                labelText: 'Título',
                helperText: _puedeEditarTitulo
                    ? 'Puedes editar el título.'
                    : 'Solo Admin puede editar el título.',
                border: const OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: _descCtrl,
              enabled: _puedeEditarDescripcion,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: 'Descripción',
                helperText: _esAdmin
                    ? 'Puedes editar la descripción.'
                    : (_puedeEditarDescripcion
                        ? 'Puedes capturar la descripción (una sola vez).'
                        : 'La descripción ya fue capturada y no se puede modificar.'),
                border: const OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fecha de cita',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _fechaCita != null
                        ? _fmtFechaHora(_fechaCita!)
                        : 'Sin fecha de cita',
                    style: theme.textTheme.bodyMedium,
                  ),

                  if (mostrarAnterior) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Fecha de cita anterior: ${_fmtFechaHora(anterior)}',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],

                  if (_yaTieneHoraLlegada) ...[
                    const SizedBox(height: 6),
                    Text(
                      'La fecha de cita ya no puede modificarse porque se registró la hora de llegada.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],

                  if (!_esAdmin) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Cambios de fecha usados: $cambios/2',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _puedeEditarFecha
                            ? theme.colorScheme.primary
                            : theme.colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_month),
                      label: Text(
                        _puedeEditarFecha
                            ? 'Seleccionar fecha y hora'
                            : (_yaTieneHoraLlegada
                                ? 'Bloqueado: ya hay hora de llegada'
                                : 'Límite alcanzado (2 cambios)'),
                      ),
                      onPressed: _puedeEditarFecha ? _seleccionarFechaHora : null,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
            ],

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_guardando ? 'Guardando...' : 'Guardar cambios'),
                onPressed: _guardando ? null : _guardar,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = _isWebWide(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar noticia'),
      ),
      body: _wrapWebWidth(
        wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 7,
                    child: _maybeScrollbar(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(_hPad(context), 12, 10, 12),
                        child: _buildFormCard(context),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: _maybeScrollbar(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(10, 12, _hPad(context), 12),
                        child: _buildResumenPanel(context),
                      ),
                    ),
                  ),
                ],
              )
            : _maybeScrollbar(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(_hPad(context)),
                  child: Column(
                    children: [
                      _buildFormCard(context),
                      const SizedBox(height: 12),
                      _buildResumenPanel(context),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
