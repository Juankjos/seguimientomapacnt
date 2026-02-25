// lib/screens/cliente_detalle_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/cliente.dart';
import '../services/api_service.dart';

String _formatPhoneDigits(String digits) {
  if (digits.isEmpty) return '';

  // 3-3-4 para <= 10 (ej. 378 711 4606)
  if (digits.length <= 3) return digits;
  if (digits.length <= 6) {
    return '${digits.substring(0, 3)} ${digits.substring(3)}';
  }
  if (digits.length <= 10) {
    return '${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6)}';
  }

  // Si excede 10, conserva 3-3 y luego agrupa de 3 en 3
  final buffer = StringBuffer()
    ..write(digits.substring(0, 3))
    ..write(' ')
    ..write(digits.substring(3, 6));

  var i = 6;
  while (i < digits.length) {
    final end = (i + 3 <= digits.length) ? i + 3 : digits.length;
    buffer
      ..write(' ')
      ..write(digits.substring(i, end));
    i = end;
  }
  return buffer.toString();
}

int _offsetForDigitIndex(String formatted, int digitIndex) {
  if (digitIndex <= 0) return 0;
  var digitsSeen = 0;
  for (var i = 0; i < formatted.length; i++) {
    final ch = formatted[i];
    if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) {
      digitsSeen++;
      if (digitsSeen == digitIndex) return i + 1;
    }
  }
  return formatted.length;
}

class PhoneSpacingFormatter extends TextInputFormatter {
  PhoneSpacingFormatter({this.maxDigits = 15});
  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final rawDigits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final digits = rawDigits.length > maxDigits
        ? rawDigits.substring(0, maxDigits)
        : rawDigits;

    final formatted = _formatPhoneDigits(digits);

    // Cuántos dígitos había antes del cursor
    final end = newValue.selection.end.clamp(0, newValue.text.length);
    final digitsBeforeCursor =
        newValue.text.substring(0, end).replaceAll(RegExp(r'\D'), '').length;

    final newCursor = _offsetForDigitIndex(formatted, digitsBeforeCursor);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newCursor),
      composing: TextRange.empty,
    );
  }
}

class ClienteDetallePage extends StatefulWidget {
  final Cliente cliente;

  const ClienteDetallePage({super.key, required this.cliente});

  @override
  State<ClienteDetallePage> createState() => _ClienteDetallePageState();
}

class _ClienteDetallePageState extends State<ClienteDetallePage> {
  late Cliente _cliente;

  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _domCtrl = TextEditingController();

  bool _cargando = false;
  bool _guardando = false;
  String? _error;

  // ===== Ladas (solo América) =====
  // Puedes agregar más sin problema.
  static const _ladasAmerica = <({String label, String code})>[
    (label: 'México', code: '+52'),
    (label: 'Estados Unidos', code: '+1'),
    (label: 'Canadá', code: '+1'),
    (label: 'Guatemala', code: '+502'),
    (label: 'Belice', code: '+501'),
    (label: 'Honduras', code: '+504'),
    (label: 'El Salvador', code: '+503'),
    (label: 'Nicaragua', code: '+505'),
    (label: 'Costa Rica', code: '+506'),
    (label: 'Panamá', code: '+507'),
    (label: 'Cuba', code: '+53'),
    (label: 'República Dominicana', code: '+1'),
    (label: 'Puerto Rico', code: '+1'),
    (label: 'Colombia', code: '+57'),
    (label: 'Venezuela', code: '+58'),
    (label: 'Ecuador', code: '+593'),
    (label: 'Perú', code: '+51'),
    (label: 'Bolivia', code: '+591'),
    (label: 'Chile', code: '+56'),
    (label: 'Argentina', code: '+54'),
    (label: 'Uruguay', code: '+598'),
    (label: 'Paraguay', code: '+595'),
    (label: 'Brasil', code: '+55'),
  ];

  String _lada = '+52'; // default MX

  @override
  void initState() {
    super.initState();
    _cliente = widget.cliente;
    _hidratarFormDesdeCliente(_cliente);
    _refrescar(); // opcional
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telCtrl.dispose();
    _domCtrl.dispose();
    super.dispose();
  }

  ({String lada, String digits}) _parseWhatsapp(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) return (lada: '+52', digits: '');
    final codes = _ladasAmerica.map((e) => e.code).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    if (cleaned.startsWith('+')) {
      for (final code in codes) {
        if (cleaned.startsWith(code)) {
          final digits = cleaned.substring(code.length).replaceAll(RegExp(r'\D'), '');
          return (lada: code, digits: digits);
        }
      }
      return (lada: '+52', digits: cleaned.replaceAll(RegExp(r'\D'), ''));
    }
    return (lada: '+52', digits: cleaned.replaceAll(RegExp(r'\D'), ''));
  }

  void _hidratarFormDesdeCliente(Cliente c) {
    _nombreCtrl.text = c.nombre;

    final raw = (c.whatsapp ?? '');
    final parsed = _parseWhatsapp(raw);

    _lada = parsed.lada;
    _telCtrl.text = _formatPhoneDigits(parsed.digits);

    _domCtrl.text = (c.domicilio ?? '');
  }

  Future<void> _refrescar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final fresh = await ApiService.getClienteDetalle(clienteId: _cliente.id);
      if (!mounted) return;

      setState(() {
        _cliente = fresh;
        _cargando = false;
      });

      // Solo rehidratar si NO está guardando/para no pisar lo que el usuario teclea
      if (!_guardando) _hidratarFormDesdeCliente(fresh);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  Future<void> _copiar(String txt) async {
    await Clipboard.setData(ClipboardData(text: txt));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copiado')),
    );
  }

  String? _validarNombre(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'El nombre es requerido';
    if (s.length < 2) return 'Nombre demasiado corto';
    return null;
  }

  String? _validarTelefono(String? v) {
    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;

    // Reglas simples (ajústalas si quieres):
    if (digits.length < 7) return 'Teléfono muy corto';
    if (digits.length > 15) return 'Teléfono muy largo';
    return null;
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    if (!_formKey.currentState!.validate()) return;

    final nombre = _nombreCtrl.text.trim();
    final telDigits = _telCtrl.text.replaceAll(RegExp(r'\D'), '');
    final whatsapp = telDigits.isEmpty ? null : '$_lada$telDigits';
    final domicilio = _domCtrl.text.trim().isEmpty ? null : _domCtrl.text.trim();

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      final updated = await ApiService.updateCliente(
        id: _cliente.id,
        nombre: nombre,
        whatsapp: whatsapp,
        domicilio: domicilio,
      );

      if (!mounted) return;

      setState(() {
        _cliente = updated;
        _guardando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente actualizado')),
      );

      // Actualiza inputs a lo que guardó el server
      _hidratarFormDesdeCliente(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawWhatsapp = (_cliente.whatsapp ?? '').trim();
    final domicilioDisplay = (_cliente.domicilio ?? '').trim();

    final parsed = _parseWhatsapp(rawWhatsapp);
    final whatsappPretty = rawWhatsapp.isEmpty
        ? '—'
        : '${parsed.lada} ${_formatPhoneDigits(parsed.digits)}';

    return Scaffold(
      appBar: AppBar(
        title: Text(_cliente.nombre),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            onPressed: (_cargando || _guardando) ? null : _refrescar,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Guardar',
            onPressed: (_cargando || _guardando) ? null : _guardar,
            icon: _guardando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
          ),
        ],
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
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                    children: [
                      TextFormField(
                        controller: _nombreCtrl,
                        enabled: !_guardando,
                        decoration: const InputDecoration(
                          labelText: 'Nombre',
                          border: OutlineInputBorder(),
                        ),
                        validator: _validarNombre,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: DropdownButtonFormField<String>(
                              value: _lada,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Lada',
                                border: OutlineInputBorder(),
                              ),
                              items: _ladasAmerica
                                  .map((x) => DropdownMenuItem(
                                        value: x.code,
                                        child: Text('${x.label} (${x.code})'),
                                      ))
                                  .toList(),
                              onChanged: _guardando ? null : (v) {
                                setState(() => _lada = v ?? '+52');
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 6,
                            child: TextFormField(
                              controller: _telCtrl,
                              enabled: !_guardando,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                PhoneSpacingFormatter(maxDigits: 15),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'WhatsApp (número)',
                                border: OutlineInputBorder(),
                                hintText: 'Ej: 3331234567',
                              ),
                              validator: _validarTelefono,
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _domCtrl,
                        enabled: !_guardando,
                        decoration: const InputDecoration(
                          labelText: 'Domicilio',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                        textInputAction: TextInputAction.newline,
                      ),

                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: (_guardando) ? null : _guardar,
                        icon: _guardando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save),
                        label: Text(_guardando ? 'Guardando…' : 'Guardar cambios'),
                      ),

                      const SizedBox(height: 18),
                      const Divider(),

                      // Sección "actual" (solo para ver/copy rápido)
                      ListTile(
                        title: const Text('WhatsApp Actual',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(whatsappPretty),
                        trailing: rawWhatsapp.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Copiar',
                                icon: const Icon(Icons.copy),
                                onPressed: () => _copiar('${parsed.lada}${parsed.digits}'),
                              ),
                      ),
                      ListTile(
                        title: const Text('Domicilio Actual',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(domicilioDisplay.isEmpty ? '—' : domicilioDisplay),
                        trailing: domicilioDisplay.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Copiar',
                                icon: const Icon(Icons.copy),
                                onPressed: () => _copiar(domicilioDisplay),
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }
}