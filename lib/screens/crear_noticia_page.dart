// lib/screens/crear_noticia_page.dart
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart'; 

import '../models/cliente.dart';
import '../services/api_service.dart';

const double _kWebMaxContentWidth = 1100;
const double _kWebWideBreakpoint = 980;

bool _isWebWide(BuildContext context) =>
    kIsWeb && MediaQuery.of(context).size.width >= _kWebWideBreakpoint;

double _hPad(BuildContext context) => _isWebWide(context) ? 20 : 16;

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

ShapeBorder _softShape(ThemeData theme) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: theme.dividerColor.withOpacity(0.70),
        width: 0.9,
      ),
    );

class CrearNoticiaPage extends StatefulWidget {
  const CrearNoticiaPage({super.key});

  @override
  State<CrearNoticiaPage> createState() => _CrearNoticiaPageState();
}

class _CrearNoticiaPageState extends State<CrearNoticiaPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _noticiaCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _domicilioCtrl = TextEditingController();

  final TextEditingController _buscarReporteroCtrl = TextEditingController();
  int _limiteTiempoMin = 60;

  static const List<int> _limitesMin = [60, 120, 180, 240, 300];

  final TextEditingController _buscarClienteCtrl = TextEditingController();

  int? _clienteIdSeleccionado;
  String? _clienteNombreSeleccionado;

  List<Cliente> _resultadosClientes = [];
  bool _buscandoClientes = false;
  bool _mostrarBuscadorCliente = false;

  Cliente? _clienteSeleccionado;
  bool _usarDomicilioCliente = false;
  bool _cargandoDomicilioCliente = false;
  String get _domicilioCliente => (_clienteSeleccionado?.domicilio ?? '').trim();
  bool get _clienteTieneDomicilio => _domicilioCliente.isNotEmpty;

  String _labelLimite(int min) {
    final h = (min ~/ 60);
    return h == 1 ? '1 HORA' : '$h HORAS';
  }

  int? _reporteroIdSeleccionado;
  String? _reporteroNombreSeleccionado;
  String? _fechaError;
  String _tipoDeNota = 'Nota';
  List<ReporteroBusqueda> _resultadosReporteros = [];
  bool _buscandoReporteros = false;
  bool _mostrarBuscadorReportero = false;

  DateTime? _fechaSeleccionada;
  TimeOfDay? _horaSeleccionada;

  bool _guardando = false;

  final DateFormat _fmtFechaHora = DateFormat('dd/MM/yyyy hh:mm a', 'es_MX');

  DateTime _soloFecha(DateTime d) => DateTime(d.year, d.month, d.day);

  String _fmtFechaHora12hAmPm(DateTime dt) {
    final date = DateFormat('dd/MM/yyyy', 'es_MX').format(dt);
    final hour12 = (dt.hour % 12 == 0) ? 12 : (dt.hour % 12);
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$date ${hour12.toString().padLeft(2, '0')}:$minute $ampm';
  }

  Future<TimeOfDay?> _showAmPmCarouselTimePicker(
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

        final sheet = SafeArea(
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
                        onPressed: () => Navigator.pop(ctx, fromDateTime(selected)),
                        child: const Text('Aceptar'),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 220,
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    use24hFormat: false, // ✅ carrusel AM/PM
                    minuteInterval: minuteInterval,
                    initialDateTime: selected,
                    onDateTimeChanged: (dt) => selected = dt,
                  ),
                ),
              ],
            ),
          ),
        );

        if (!kIsWeb) return sheet;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: sheet,
          ),
        );
      },
    );
  }

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

        final sheet = StatefulBuilder(
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
            const double sheetRadius = 18;
            const double boxRadius = 14;

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: Material(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(sheetRadius), 
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
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
                          child: Center(
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
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(boxRadius),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(boxRadius),
                                        borderSide: BorderSide(color: theme.colorScheme.primary),
                                      ),
                                      errorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(boxRadius),
                                        borderSide: BorderSide(color: theme.colorScheme.error),
                                      ),
                                      focusedErrorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(boxRadius),
                                        borderSide: BorderSide(color: theme.colorScheme.error),
                                      ),
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
                                  width: boxSize,
                                  height: boxSize,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(boxRadius),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        border: Border.all(color: theme.dividerColor),
                                        borderRadius: BorderRadius.circular(boxRadius),
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
                                ),
                              ],
                            ),
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
              ),
            );
          },
        );

        if (!kIsWeb) return sheet;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: sheet,
          ),
        );
      },
    );
  }

  Future<void> _seleccionarCliente(Cliente c) async {
    setState(() {
      _clienteSeleccionado = c;
      _clienteIdSeleccionado = c.id;
      _clienteNombreSeleccionado = c.nombre;
      _mostrarBuscadorCliente = false;
      _cargandoDomicilioCliente = true;
    });

    try {
      final detalle = await ApiService.getClienteDetalle(clienteId: c.id);
      if (!mounted) return;
      setState(() {
        _clienteSeleccionado = detalle;
        _cargandoDomicilioCliente = false;
      });
      if (_usarDomicilioCliente) {
        final dom = (detalle.domicilio ?? '').trim();
        setState(() {
          if (dom.isNotEmpty) {
            _domicilioCtrl.text = dom;
          } else {
            _domicilioCtrl.clear();
            _usarDomicilioCliente = false;
          }
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargandoDomicilioCliente = false);
      if (_usarDomicilioCliente && _clienteTieneDomicilio) {
        _domicilioCtrl.text = _domicilioCliente;
      }
    }
  }

  @override
  void dispose() {
    _noticiaCtrl.dispose();
    _descCtrl.dispose();
    _domicilioCtrl.dispose();
    _buscarReporteroCtrl.dispose();
    _buscarClienteCtrl.dispose();
    super.dispose();
  }

  Future<void> _seleccionarFecha() async {
    final hoy = _soloFecha(DateTime.now());

    final inicial =
        (_fechaSeleccionada != null && !_soloFecha(_fechaSeleccionada!).isBefore(hoy))
            ? _fechaSeleccionada!
            : hoy;

    final picked = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: hoy,
      lastDate: DateTime(hoy.year + 2, 12, 31),
      locale: const Locale('es', 'MX'),
    );

    if (picked != null) {
      setState(() => _fechaSeleccionada = picked);
    }
  }

  Future<void> _seleccionarHora() async {
    final initial = _horaSeleccionada ?? TimeOfDay.now();

    final picked = _usarHoraPorTexto(context)
        ? await _showTextTimePicker(
            context,
            initialTime: initial,
            minuteInterval: 1,
          )
        : await _showAmPmCarouselTimePicker(
            context,
            initialTime: initial,
            minuteInterval: 1,
          );

    if (picked != null) {
      setState(() => _horaSeleccionada = picked);
    }
  }

  DateTime? _combinarFechaHora() {
    if (_fechaSeleccionada == null) return null;
    final fecha = _fechaSeleccionada!;
    final hora = _horaSeleccionada ?? const TimeOfDay(hour: 0, minute: 0);

    return DateTime(
      fecha.year,
      fecha.month,
      fecha.day,
      hora.hour,
      hora.minute,
    );
  }

  Future<void> _buscarReporteros(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _resultadosReporteros = []);
      return;
    }

    setState(() => _buscandoReporteros = true);

    try {
      final resultados = await ApiService.buscarReporteros(query);
      if (!mounted) return;
      setState(() => _resultadosReporteros = resultados);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al buscar reporteros: $e')),
      );
    } finally {
      if (mounted) setState(() => _buscandoReporteros = false);
    }
  }

  Future<void> _buscarClientes(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _resultadosClientes = []);
      return;
    }

    setState(() => _buscandoClientes = true);

    try {
      final resultados = await ApiService.getClientes(q: query.trim());
      if (!mounted) return;
      setState(() => _resultadosClientes = resultados);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al buscar clientes: $e')),
      );
    } finally {
      if (mounted) setState(() => _buscandoClientes = false);
    }
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

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _fechaError = null);
    if (_fechaSeleccionada == null) {
      setState(() => _fechaError = 'Debes seleccionar una fecha para la cita.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una fecha para crear la noticia.')),
      );
      return;
    }

    final hoy = _soloFecha(DateTime.now());
    if (_fechaSeleccionada != null && _soloFecha(_fechaSeleccionada!).isBefore(hoy)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No puedes crear noticias en fechas pasadas.')),
      );
      return;
    }

    final fechaCita = _combinarFechaHora();

    if (_tipoDeNota == 'Entrevista' &&
        fechaCita != null &&
        _reporteroIdSeleccionado != null) {

      final choque = await ApiService.buscarChoqueCitaEntrevista(
        reporteroId: _reporteroIdSeleccionado!,
        fechaCita: fechaCita,
      );

      if (choque != null) {
        final extra = (choque.fechaCita != null)
            ? 'Posible conflicto con: "${choque.noticia}" (${_fmtFechaHora.format(choque.fechaCita!)})'
            : 'Posible conflicto con: "${choque.noticia}"';

        final continuar = await _confirmarChoqueHorario(extra: extra);
        if (!continuar) return;
      }
    }

    setState(() => _guardando = true);

    try {
      final limiteMin = _limiteTiempoMin;

      await ApiService.crearNoticia(
        noticia: _noticiaCtrl.text.trim(),
        tipoDeNota: _tipoDeNota,
        descripcion: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        domicilio: _domicilioCtrl.text.trim().isEmpty ? null : _domicilioCtrl.text.trim(),
        reporteroId: _reporteroIdSeleccionado,
        clienteId: _clienteIdSeleccionado,
        fechaCita: fechaCita,
        limiteTiempoMinutos: limiteMin,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Noticia creada correctamente')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al crear noticia: $e')),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ===================== UI helpers =====================

  Widget _card(ThemeData theme, Widget child) {
    return Card(
      elevation: kIsWeb ? 0.6 : 2,
      shape: _softShape(theme),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }

  // ===================== Build =====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = _isWebWide(context);

    final fechaCita = _combinarFechaHora();
    final String textoFechaCita =
        fechaCita != null ? _fmtFechaHora12hAmPm(fechaCita) : 'Sin fecha/hora asignada';

    final leftCard = _card(
      theme,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.article_outlined),
              const SizedBox(width: 8),
              Text(
                'Datos de la noticia',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _noticiaCtrl,
            decoration: const InputDecoration(
              labelText: 'Título de la noticia *',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'El título es obligatorio';
              return null;
            },
          ),

          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            value: _tipoDeNota,
            decoration: const InputDecoration(
              labelText: 'Tipo de noticia',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'Nota', child: Text('Nota')),
              DropdownMenuItem(value: 'Entrevista', child: Text('Entrevista')),
            ],
            onChanged: (v) => setState(() => _tipoDeNota = v ?? 'Nota'),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              const Icon(Icons.person_outline),
              const SizedBox(width: 8),
              Text(
                'Cliente (opcional)',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Cliente:', style: theme.textTheme.bodyMedium),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _clienteNombreSeleccionado ?? 'Ninguno',
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.person_search),
                label: Text(_mostrarBuscadorCliente ? 'Ocultar buscador' : 'Asignar cliente'),
                onPressed: () => setState(() {
                  _mostrarBuscadorCliente = !_mostrarBuscadorCliente;
                }),
              ),
              if (_clienteIdSeleccionado != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.person_off),
                  label: const Text('Quitar cliente'),
                  onPressed: () {
                    setState(() {
                      _clienteIdSeleccionado = null;
                      _clienteNombreSeleccionado = null;
                      _clienteSeleccionado = null;
                      _mostrarBuscadorCliente = false;

                      if (_usarDomicilioCliente) {
                        _usarDomicilioCliente = false;
                        _domicilioCtrl.clear();
                      }
                    });
                  },
                ),
            ],
          ),

          if (_mostrarBuscadorCliente) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _buscarClienteCtrl,
              decoration: InputDecoration(
                labelText: 'Buscar cliente por nombre',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _buscarClienteCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _buscarClienteCtrl.clear();
                            _resultadosClientes = [];
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (v) {
                setState(() {});
                _buscarClientes(v);
              },
            ),
            const SizedBox(height: 10),
            if (_buscandoClientes)
              const Center(child: CircularProgressIndicator())
            else if (_resultadosClientes.isEmpty)
              const Text('Sin resultados')
            else
              SizedBox(
                height: wide ? 260 : 180,
                child: _maybeScrollbar(
                  child: ListView.builder(
                    itemCount: _resultadosClientes.length,
                    itemBuilder: (context, index) {
                      final c = _resultadosClientes[index];
                      return ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(c.nombre),
                        subtitle: (c.domicilio ?? '').trim().isEmpty
                            ? null
                            : Text(
                                (c.domicilio ?? '').trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: () => _seleccionarCliente(c),
                      );
                    },
                  ),
                ),
              ),
          ],

          if (_clienteIdSeleccionado != null) ...[
            const SizedBox(height: 12),

            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('¿Agregar domicilio del cliente a la noticia?'),
              subtitle: Text(
                _cargandoDomicilioCliente
                    ? 'Cargando domicilio...'
                    : 'Domicilio: ${_domicilioCliente.isEmpty ? '—' : _domicilioCliente}',
              ),
              value: _usarDomicilioCliente,
              onChanged: (_guardando || _cargandoDomicilioCliente || !_clienteTieneDomicilio)
                  ? null
                  : (v) {
                      setState(() {
                        _usarDomicilioCliente = v;
                        if (v) {
                          _domicilioCtrl.text = _domicilioCliente;
                        } else {
                          _domicilioCtrl.clear();
                        }
                      });
                    },
            ),
          ],

          const SizedBox(height: 12),
          TextFormField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: 'Descripción (opcional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _domicilioCtrl,
            readOnly: _usarDomicilioCliente,
            enabled: !_guardando,
            decoration: const InputDecoration(
              labelText: 'Domicilio (opcional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
        ],
      ),
    );

    final rightCard = _card(
      theme,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_search),
              const SizedBox(width: 8),
              Text(
                'Asignación y cita',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Reportero asignado:', style: theme.textTheme.bodyMedium),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _reporteroNombreSeleccionado ?? 'Ninguno',
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.person_search),
                label: Text(_mostrarBuscadorReportero ? 'Ocultar buscador' : 'Asignar reportero'),
                onPressed: () => setState(() {
                  _mostrarBuscadorReportero = !_mostrarBuscadorReportero;
                }),
              ),
              if (_reporteroIdSeleccionado != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.person_off),
                  label: const Text('Quitar asignación'),
                  onPressed: () {
                    setState(() {
                      _reporteroIdSeleccionado = null;
                      _reporteroNombreSeleccionado = null;
                    });
                  },
                ),
            ],
          ),

          if (_mostrarBuscadorReportero) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _buscarReporteroCtrl,
              decoration: InputDecoration(
                labelText: 'Buscar reportero por nombre',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _buscarReporteroCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _buscarReporteroCtrl.clear();
                            _resultadosReporteros = [];
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (v) {
                setState(() {});
                _buscarReporteros(v);
              },
            ),
            const SizedBox(height: 10),
            if (_buscandoReporteros)
              const Center(child: CircularProgressIndicator())
            else if (_resultadosReporteros.isEmpty)
              const Text('Sin resultados')
            else
              SizedBox(
                height: wide ? 260 : 180,
                child: _maybeScrollbar(
                  child: ListView.builder(
                    itemCount: _resultadosReporteros.length,
                    itemBuilder: (context, index) {
                      final r = _resultadosReporteros[index];
                      return ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(r.nombre),
                        onTap: () {
                          setState(() {
                            _reporteroIdSeleccionado = r.id;
                            _reporteroNombreSeleccionado = r.nombre;
                            _mostrarBuscadorReportero = false;
                          });
                        },
                      );
                    },
                  ),
                ),
              ),
          ],

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          Text('Fecha y hora de cita:', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            textoFechaCita,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),

          if (_fechaError != null) ...[
            const SizedBox(height: 6),
            Text(
              _fechaError!,
              style: TextStyle(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: const Text('Fecha Cita'),
                onPressed: _seleccionarFecha,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.access_time),
                label: const Text('Hora Cita'),
                onPressed: _seleccionarHora,
              ),
              if (_fechaSeleccionada != null || _horaSeleccionada != null)
                TextButton.icon(
                  icon: const Icon(Icons.clear),
                  label: const Text('Limpiar'),
                  onPressed: () => setState(() {
                    _fechaSeleccionada = null;
                    _horaSeleccionada = null;
                  }),
                ),
            ],
          ),

          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: _limiteTiempoMin,
            decoration: const InputDecoration(
              labelText: 'Límite de tiempo *',
              helperText: 'Selecciona de 1 a 5 horas.',
              border: OutlineInputBorder(),
            ),
            items: _limitesMin
                .map((m) => DropdownMenuItem<int>(
                      value: m,
                      child: Text(_labelLimite(m)),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _limiteTiempoMin = v ?? 60),
            validator: (v) => (v == null) ? 'Selecciona un límite' : null,
          ),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: _guardando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(_guardando ? 'Guardando...' : 'Guardar noticia'),
              onPressed: _guardando ? null : _guardar,
            ),
          ),
        ],
      ),
    );

    final formContent = Form(
      key: _formKey,
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: leftCard),
                const SizedBox(width: 12),
                Expanded(flex: 5, child: rightCard),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leftCard,
                const SizedBox(height: 12),
                rightCard,
              ],
            ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear noticia'),
      ),
      body: _wrapWebWidth(
        _maybeScrollbar(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(_hPad(context)),
            child: formContent,
          ),
        ),
      ),
    );
  }
}
