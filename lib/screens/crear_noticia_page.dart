import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  // Asignar reportero
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

  @override
  void dispose() {
    _noticiaCtrl.dispose();
    _descCtrl.dispose();
    _domicilioCtrl.dispose();
    _buscarReporteroCtrl.dispose();
    super.dispose();
  }

  Future<void> _seleccionarFecha() async {
    final hoy = DateTime.now();
    final inicial = _fechaSeleccionada ?? hoy;

    final picked = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(hoy.year - 1),
      lastDate: DateTime(hoy.year + 2),
      locale: const Locale('es', 'MX'),
    );

    if (picked != null) {
      setState(() {
        _fechaSeleccionada = picked;
      });
    }
  }

  Future<void> _seleccionarHora() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _horaSeleccionada ?? TimeOfDay.now(),
    );

    if (picked != null) {
      setState(() {
        _horaSeleccionada = picked;
      });
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
      setState(() {
        _resultadosReporteros = [];
      });
      return;
    }

    setState(() {
      _buscandoReporteros = true;
    });

    try {
      final resultados = await ApiService.buscarReporteros(query);
      setState(() {
        _resultadosReporteros = resultados;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al buscar reporteros: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _buscandoReporteros = false;
        });
      }
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _guardando = true;
    });

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
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final fechaCita = _combinarFechaHora();
    final String textoFechaCita = fechaCita != null
        ? _fmtFechaHora.format(fechaCita)
        : 'Sin fecha/hora asignada';

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
                  if (v == null || v.trim().isEmpty) {
                    return 'El título es obligatorio';
                  }
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

              // -------- Asignar reportero (opcional) --------
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Reportero asignado:',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    _reporteroNombreSeleccionado ?? 'Ninguno',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.person_search),
                    label: const Text('Asignar reportero'),
                    onPressed: () {
                      setState(() {
                        _mostrarBuscadorReportero = !_mostrarBuscadorReportero;
                      });
                    },
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
                  onChanged: (value) {
                    _buscarReporteros(value);
                  },
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

              // -------- Fecha y hora de cita --------
              Text(
                'Fecha y hora de cita:',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                textoFechaCita,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('Seleccionar fecha'),
                    onPressed: _seleccionarFecha,
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.access_time),
                    label: const Text('Seleccionar hora'),
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
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
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
