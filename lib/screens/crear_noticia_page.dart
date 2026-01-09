// lib/screens/crear_noticia_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/cupertino.dart';

import '../services/api_service.dart';

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
  int? _reporteroIdSeleccionado;
  String? _reporteroNombreSeleccionado;
  List<ReporteroBusqueda> _resultadosReporteros = [];
  bool _buscandoReporteros = false;
  bool _mostrarBuscadorReportero = false;

  DateTime? _fechaSeleccionada;
  TimeOfDay? _horaSeleccionada;

  bool _guardando = false;

  final DateFormat _fmtFechaHora = DateFormat('dd/MM/yyyy HH:mm');

  DateTime _soloFecha(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<TimeOfDay?> _showAmPmCarouselTimePicker(
    BuildContext context, {
    required TimeOfDay initialTime,
    int minuteInterval = 1,
  }) async {
    DateTime toDateTime(TimeOfDay t) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, t.hour, t.minute);
    }

    TimeOfDay fromDateTime(DateTime dt) => TimeOfDay(hour: dt.hour, minute: dt.minute);

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
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
                    use24hFormat: false,
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

  @override
  void dispose() {
    _noticiaCtrl.dispose();
    _descCtrl.dispose();
    _domicilioCtrl.dispose();
    _buscarReporteroCtrl.dispose();
    super.dispose();
  }

  Future<void> _seleccionarFecha() async {
    final hoy = _soloFecha(DateTime.now());

    final inicial = (_fechaSeleccionada != null && !_soloFecha(_fechaSeleccionada!).isBefore(hoy))
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
    final picked = await _showAmPmCarouselTimePicker(
      context,
      initialTime: _horaSeleccionada ?? TimeOfDay.now(),
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

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final hoy = _soloFecha(DateTime.now());
    if (_fechaSeleccionada != null && _soloFecha(_fechaSeleccionada!).isBefore(hoy)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No puedes crear noticias en fechas pasadas.')),
      );
      return;
    }

    setState(() => _guardando = true);

    try {
      final fechaCita = _combinarFechaHora();

      await ApiService.crearNoticia(
        noticia: _noticiaCtrl.text.trim(),
        descripcion: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        domicilio: _domicilioCtrl.text.trim().isEmpty ? null : _domicilioCtrl.text.trim(),
        reporteroId: _reporteroIdSeleccionado,
        fechaCita: fechaCita,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final fechaCita = _combinarFechaHora();
    final String textoFechaCita =
        fechaCita != null ? _fmtFechaHora.format(fechaCita) : 'Sin fecha/hora asignada';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear noticia'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                decoration: const InputDecoration(
                  labelText: 'Domicilio (opcional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Reportero asignado:', style: theme.textTheme.bodyMedium),
                  Text(
                    _reporteroNombreSeleccionado ?? 'Ninguno',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.person_search),
                    label: const Text('Asignar reportero'),
                    onPressed: () => setState(() => _mostrarBuscadorReportero = !_mostrarBuscadorReportero),
                  ),
                  const SizedBox(width: 8),
                  if (_reporteroIdSeleccionado != null)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _reporteroIdSeleccionado = null;
                          _reporteroNombreSeleccionado = null;
                        });
                      },
                      child: const Text('Quitar asignación'),
                    ),
                ],
              ),

              if (_mostrarBuscadorReportero) ...[
                const SizedBox(height: 8),
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
                  onChanged: _buscarReporteros,
                ),
                const SizedBox(height: 8),
                if (_buscandoReporteros)
                  const Center(child: CircularProgressIndicator())
                else if (_resultadosReporteros.isEmpty)
                  const Text('Sin resultados')
                else
                  SizedBox(
                    height: 180,
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
              ],

              const SizedBox(height: 16),

              Text('Fecha y hora de cita:', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(
                textoFechaCita,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('Fecha Cita'),
                    onPressed: _seleccionarFecha,
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.access_time),
                    label: const Text('Hora Cita'),
                    onPressed: _seleccionarHora,
                  ),
                ],
              ),

              const SizedBox(height: 24),

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
        ),
      ),
    );
  }
}
