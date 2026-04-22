// lib/screens/cliente_detalle_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/cliente.dart';
import '../models/noticia.dart';
import '../services/api_service.dart';
import 'noticia_detalle_page.dart';

String _formatPhoneDigits(String digits) {
  if (digits.isEmpty) return '';

  if (digits.length <= 3) return digits;
  if (digits.length <= 6) {
    return '${digits.substring(0, 3)} ${digits.substring(3)}';
  }
  if (digits.length <= 10) {
    return '${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6)}';
  }

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
class _AddressForm {
  final String calle;
  final String numeroExterior;
  final String numeroInterior;
  final String colonia;
  final String ciudad;
  final String municipio;
  final String estado;
  final String codigoPostal;
  final String referencias;

  const _AddressForm({
    this.calle = '',
    this.numeroExterior = '',
    this.numeroInterior = '',
    this.colonia = '',
    this.ciudad = '',
    this.municipio = '',
    this.estado = '',
    this.codigoPostal = '',
    this.referencias = '',
  });

  bool get isEmpty =>
      calle.trim().isEmpty &&
      numeroExterior.trim().isEmpty &&
      numeroInterior.trim().isEmpty &&
      colonia.trim().isEmpty &&
      ciudad.trim().isEmpty &&
      municipio.trim().isEmpty &&
      estado.trim().isEmpty &&
      codigoPostal.trim().isEmpty &&
      referencias.trim().isEmpty;

  _AddressForm copyWith({
    String? calle,
    String? numeroExterior,
    String? numeroInterior,
    String? colonia,
    String? ciudad,
    String? municipio,
    String? estado,
    String? codigoPostal,
    String? referencias,
  }) {
    return _AddressForm(
      calle: calle ?? this.calle,
      numeroExterior: numeroExterior ?? this.numeroExterior,
      numeroInterior: numeroInterior ?? this.numeroInterior,
      colonia: colonia ?? this.colonia,
      ciudad: ciudad ?? this.ciudad,
      municipio: municipio ?? this.municipio,
      estado: estado ?? this.estado,
      codigoPostal: codigoPostal ?? this.codigoPostal,
      referencias: referencias ?? this.referencias,
    );
  }

  bool equals(_AddressForm other) {
    return calle.trim() == other.calle.trim() &&
        numeroExterior.trim() == other.numeroExterior.trim() &&
        numeroInterior.trim() == other.numeroInterior.trim() &&
        colonia.trim() == other.colonia.trim() &&
        ciudad.trim() == other.ciudad.trim() &&
        municipio.trim() == other.municipio.trim() &&
        estado.trim() == other.estado.trim() &&
        codigoPostal.trim() == other.codigoPostal.trim() &&
        referencias.trim() == other.referencias.trim();
  }

  String toStorageString() {
    final parts = <String>[
      'Calle: ${calle.trim()}',
      if (numeroExterior.trim().isNotEmpty) 'Num. ext: ${numeroExterior.trim()}',
      if (numeroInterior.trim().isNotEmpty) 'Num. int: ${numeroInterior.trim()}',
      'Colonia: ${colonia.trim()}',
      'Ciudad: ${ciudad.trim()}',
      'Municipio: ${municipio.trim()}',
      'Estado: ${estado.trim()}',
      'CP: ${codigoPostal.trim()}',
      if (referencias.trim().isNotEmpty) 'Referencias: ${referencias.trim()}',
    ];

    return parts.join(', ');
  }

  String toPreviewString() => toStorageString();
}

const _emptyAddress = _AddressForm();
const _addressSlots = <int>[1, 2, 3];

String _extractField(String text, String label, List<String> nextLabels) {
  final escapedLabel = RegExp.escape(label);
  final nextPart = nextLabels.isNotEmpty
      ? nextLabels.map(RegExp.escape).join('|')
      : '';

  final pattern = nextLabels.isNotEmpty
      ? '$escapedLabel\\s*(.*?)(?=,\\s*(?:$nextPart)|\$)'
      : '$escapedLabel\\s*(.*?)\$';

  final regex = RegExp(pattern);
  return regex.firstMatch(text)?.group(1)?.trim() ?? '';
}

_AddressForm _parseDomicilio(String? domicilio) {
  final text = (domicilio ?? '').trim();
  if (text.isEmpty) return _emptyAddress;

  return _AddressForm(
    calle: _extractField(text, 'Calle:', ['Num. ext:', 'Num. int:', 'Colonia:']),
    numeroExterior: _extractField(text, 'Num. ext:', ['Num. int:', 'Colonia:']),
    numeroInterior: _extractField(text, 'Num. int:', ['Colonia:']),
    colonia: _extractField(text, 'Colonia:', ['Ciudad:']),
    ciudad: _extractField(text, 'Ciudad:', ['Municipio:']),
    municipio: _extractField(text, 'Municipio:', ['Estado:']),
    estado: _extractField(text, 'Estado:', ['CP:']),
    codigoPostal: _extractField(text, 'CP:', ['Referencias:']),
    referencias: _extractField(text, 'Referencias:', []),
  );
}

class _ClienteDetallePageState extends State<ClienteDetallePage> {
  late Cliente _cliente;

  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _apellidosCtrl = TextEditingController();
  final _empresaCtrl = TextEditingController();

  static const double _kDesktopBreakpoint = 1100;
  static const double _kMaxContentWidth = 1450;

  int? _editingAddressSlot;

  late Map<int, _AddressForm> _addresses;
  late Map<int, _AddressForm> _originalAddresses;

  bool _cargando = false;
  bool _guardando = false;
  String? _error;

  List<Noticia> _noticiasCliente = [];
  bool _cargandoNoticias = false;
  String? _errorNoticias;

  String _filtroNoticias = 'agendadas';

  @override
  void initState() {
    super.initState();
    _cliente = widget.cliente;
    _addresses = {
      1: _parseDomicilio(_cliente.domicilio1),
      2: _parseDomicilio(_cliente.domicilio2),
      3: _parseDomicilio(_cliente.domicilio3),
    };
    _originalAddresses = Map<int, _AddressForm>.from(_addresses);

    _hidratarFormDesdeCliente(_cliente);
    _cargarNoticiasCliente();
    _refrescar();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telCtrl.dispose();
    _correoCtrl.dispose();
    _apellidosCtrl.dispose();
    _empresaCtrl.dispose();
    super.dispose();
  }

  void _syncAddressesFromCliente(Cliente c) {
    final parsed = {
      1: _parseDomicilio(c.domicilio1),
      2: _parseDomicilio(c.domicilio2),
      3: _parseDomicilio(c.domicilio3),
    };

    _addresses = parsed;
    _originalAddresses = Map<int, _AddressForm>.from(parsed);
  }

  List<String> _domiciliosDe(Cliente c) {
    final values = <String>[
      (c.domicilio1 ?? '').trim(),
      (c.domicilio2 ?? '').trim(),
      (c.domicilio3 ?? '').trim(),
    ];
    return values.where((e) => e.isNotEmpty).toList();
  }

  void _hidratarFormDesdeCliente(Cliente c) {
    _nombreCtrl.text = c.nombre;
    _apellidosCtrl.text = (c.apellidos ?? '').trim();
    _empresaCtrl.text = (c.empresa ?? '').trim();

    final rawTelefono = (c.telefono ?? '').replaceAll(RegExp(r'\D'), '');
    _telCtrl.text = _formatPhoneDigits(rawTelefono);

    _correoCtrl.text = (c.email ?? '').trim();
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
        _syncAddressesFromCliente(fresh);
        _cargando = false;
      });

      if (!_guardando) {
        _hidratarFormDesdeCliente(fresh);
      }
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
    if (digits.length < 7) return 'Teléfono muy corto';
    if (digits.length > 15) return 'Teléfono muy largo';
    return null;
  }

  String? _validarCorreo(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'El correo es requerido';
    final ok = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s);
    return ok ? null : 'Correo inválido';
  }

  String? _validarAddress(_AddressForm a) {
    if (a.calle.trim().isEmpty ||
        a.colonia.trim().isEmpty ||
        a.ciudad.trim().isEmpty ||
        a.municipio.trim().isEmpty ||
        a.estado.trim().isEmpty ||
        a.codigoPostal.trim().isEmpty) {
      return 'Completa todos los campos obligatorios del domicilio';
    }

    if (a.numeroExterior.trim().isEmpty && a.numeroInterior.trim().isEmpty) {
      return 'Captura número exterior o número interior';
    }

    if (!RegExp(r'^\d{5}$').hasMatch(a.codigoPostal.trim())) {
      return 'El código postal debe tener 5 dígitos';
    }

    return null;
  }

  Future<void> _guardarPerfil() async {
    if (_guardando) return;
    if (!_formKey.currentState!.validate()) return;

    final nombre = _nombreCtrl.text.trim();
    final apellidos = _apellidosCtrl.text.trim().isEmpty ? null : _apellidosCtrl.text.trim();
    final empresa = _empresaCtrl.text.trim().isEmpty ? null : _empresaCtrl.text.trim();
    final email = _correoCtrl.text.trim();

    final telDigits = _telCtrl.text.replaceAll(RegExp(r'\D'), '');
    final telefono = telDigits.isEmpty ? null : telDigits;

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      final updated = await ApiService.updateCliente(
        id: _cliente.id,
        nombre: nombre,
        apellidos: apellidos,
        telefono: telefono,
        email: email,
        empresa: empresa,
        domicilio1: _addresses[1]!.isEmpty ? null : _addresses[1]!.toStorageString(),
        domicilio2: _addresses[2]!.isEmpty ? null : _addresses[2]!.toStorageString(),
        domicilio3: _addresses[3]!.isEmpty ? null : _addresses[3]!.toStorageString(),
      );

      if (!mounted) return;

      setState(() {
        _cliente = updated;
        _syncAddressesFromCliente(updated);
        _guardando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente actualizado')),
      );

      _hidratarFormDesdeCliente(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _guardarDomicilio(int slot) async {
    final address = _addresses[slot]!;
    final validation = _validarAddress(address);

    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      final telDigits = _telCtrl.text.replaceAll(RegExp(r'\D'), '');
      final telefono = telDigits.isEmpty ? null : telDigits;

      final updated = await ApiService.updateCliente(
        id: _cliente.id,
        nombre: _nombreCtrl.text.trim(),
        apellidos: _apellidosCtrl.text.trim().isEmpty ? null : _apellidosCtrl.text.trim(),
        telefono: telefono,
        email: _correoCtrl.text.trim(),
        empresa: _empresaCtrl.text.trim().isEmpty ? null : _empresaCtrl.text.trim(),
        domicilio1: _addresses[1]!.isEmpty ? null : _addresses[1]!.toStorageString(),
        domicilio2: _addresses[2]!.isEmpty ? null : _addresses[2]!.toStorageString(),
        domicilio3: _addresses[3]!.isEmpty ? null : _addresses[3]!.toStorageString(),
      );

      if (!mounted) return;

      setState(() {
        _cliente = updated;
        _syncAddressesFromCliente(updated);
        _editingAddressSlot = null;
        _guardando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Domicilio $slot guardado')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _eliminarDomicilio(int slot) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminar domicilio $slot'),
        content: const Text('Esta acción eliminará el domicilio actual.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() {
      _addresses[slot] = _emptyAddress;
      _guardando = true;
      _error = null;
    });

    try {
      final telDigits = _telCtrl.text.replaceAll(RegExp(r'\D'), '');
      final telefono = telDigits.isEmpty ? null : telDigits;

      final updated = await ApiService.updateCliente(
        id: _cliente.id,
        nombre: _nombreCtrl.text.trim(),
        apellidos: _apellidosCtrl.text.trim().isEmpty ? null : _apellidosCtrl.text.trim(),
        telefono: telefono,
        email: _correoCtrl.text.trim(),
        empresa: _empresaCtrl.text.trim().isEmpty ? null : _empresaCtrl.text.trim(),
        domicilio1: _addresses[1]!.isEmpty ? null : _addresses[1]!.toStorageString(),
        domicilio2: _addresses[2]!.isEmpty ? null : _addresses[2]!.toStorageString(),
        domicilio3: _addresses[3]!.isEmpty ? null : _addresses[3]!.toStorageString(),
      );

      if (!mounted) return;

      setState(() {
        _cliente = updated;
        _syncAddressesFromCliente(updated);
        _editingAddressSlot = null;
        _guardando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Domicilio $slot eliminado')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = e.toString();
      });
    }
  }

  void _cancelarDomicilio(int slot) {
    setState(() {
      _addresses[slot] = _originalAddresses[slot]!;
      _editingAddressSlot = null;
      _error = null;
    });
  }

  void _agregarDomicilio() {
    final next = _addressSlots.firstWhere(
      (slot) => _originalAddresses[slot]!.isEmpty,
      orElse: () => 0,
    );

    if (next == 0) return;

    setState(() {
      _addresses[next] = _emptyAddress;
      _editingAddressSlot = next;
      _error = null;
    });
  }

  Future<void> _cargarNoticiasCliente() async {
    setState(() {
      _cargandoNoticias = true;
      _errorNoticias = null;
    });

    try {
      final list = await ApiService.getNoticiasPorCliente(
        clienteClienteId: _cliente.id,
      );
      if (!mounted) return;

      setState(() {
        _noticiasCliente = list;
        _cargandoNoticias = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorNoticias = e.toString();
        _cargandoNoticias = false;
      });
    }
  }

  Future<void> _eliminarCliente() async {
    if (_guardando || _cargando) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: Text(
          'Vas a eliminar a "${_cliente.nombre}".\n\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      await ApiService.deleteCliente(clienteId: _cliente.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente eliminado')),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = e.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar: $e')),
      );
    }
  }

  Widget _buildPanelCard({
    required BuildContext context,
    required String title,
    String? subtitle,
    Widget? trailing,
    required Widget child,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _infoChip(
    BuildContext context, {
    required IconData icon,
    required String text,
    VoidCallback? onCopy,
  }) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.65),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onCopy != null) ...[
            const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onCopy,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.copy,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResumenClienteHeader(BuildContext context) {
    final rawTelefono = (_cliente.telefono ?? '').replaceAll(RegExp(r'\D'), '');
    final correoDisplay = (_cliente.email ?? '').trim();
    final domicilios = _domiciliosDe(_cliente);

    final telefonoPretty = rawTelefono.isEmpty
        ? 'Sin teléfono'
        : _formatPhoneDigits(rawTelefono);

    final theme = Theme.of(context);

    return Card(
      elevation: 1.2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                _cliente.nombreCompleto.isNotEmpty
                    ? _cliente.nombreCompleto[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _cliente.nombreCompleto,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _infoChip(
                        context,
                        icon: Icons.phone_outlined,
                        text: telefonoPretty,
                        onCopy: rawTelefono.isEmpty ? null : () => _copiar(rawTelefono),
                      ),
                      _infoChip(
                        context,
                        icon: Icons.email_outlined,
                        text: correoDisplay.isEmpty ? 'Sin correo' : correoDisplay,
                        onCopy: correoDisplay.isEmpty ? null : () => _copiar(correoDisplay),
                      ),
                      if ((_cliente.username ?? '').trim().isNotEmpty)
                        _infoChip(
                          context,
                          icon: Icons.alternate_email,
                          text: _cliente.username!,
                          onCopy: () => _copiar(_cliente.username!),
                        ),
                      _infoChip(
                        context,
                        icon: _cliente.activo
                            ? Icons.check_circle_outline
                            : Icons.cancel_outlined,
                        text: _cliente.activo ? 'Activo' : 'Inactivo',
                      ),
                      if ((_cliente.empresa ?? '').trim().isNotEmpty)
                        _infoChip(
                          context,
                          icon: Icons.business_outlined,
                          text: _cliente.empresa!,
                          onCopy: () => _copiar(_cliente.empresa!),
                        ),
                      if (domicilios.isEmpty)
                        _infoChip(
                          context,
                          icon: Icons.location_on_outlined,
                          text: 'Sin domicilios',
                        ),
                      ...domicilios.asMap().entries.map(
                        (entry) => _infoChip(
                          context,
                          icon: Icons.location_on_outlined,
                          text: 'Domicilio ${entry.key + 1}',
                          onCopy: () => _copiar(entry.value),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerZone(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.red.withOpacity(0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.red.withOpacity(0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Eliminar Cliente',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Esta acción no se puede deshacer.',
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                side: const BorderSide(
                  color: Colors.white,
                  width: 1.5,
                ),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: (_guardando || _cargando) ? null : _eliminarCliente,
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              label: const Text('Eliminar cliente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDomiciliosSection(BuildContext context) {
    final theme = Theme.of(context);
    final addressCount =
        _addressSlots.where((slot) => !_originalAddresses[slot]!.isEmpty).length;
    final canAddAddress = addressCount < 3 && _editingAddressSlot == null;

    return _buildPanelCard(
      context: context,
      title: 'Domicilios',
      subtitle: 'Administra hasta 3 domicilios por cliente.',
      trailing: canAddAddress
          ? OutlinedButton(
              onPressed: _agregarDomicilio,
              child: const Text('Agregar domicilio'),
            )
          : null,
      child: Column(
        children: _addressSlots.map((slot) {
          final exists = !_originalAddresses[slot]!.isEmpty;
          final isEditing = _editingAddressSlot == slot;
          final address = _addresses[slot]!;

          if (!exists && !isEditing) {
            return const SizedBox.shrink();
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Domicilio $slot',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (!isEditing) ...[
                            const SizedBox(height: 6),
                            Text(
                              _originalAddresses[slot]!.toPreviewString(),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!isEditing)
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _editingAddressSlot = slot;
                            _error = null;
                          });
                        },
                        child: const Text('Editar'),
                      ),
                  ],
                ),
                if (isEditing) ...[
                  const SizedBox(height: 14),
                  _buildAddressEditor(slot),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _guardando ? null : () => _cancelarDomicilio(slot),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (exists)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _guardando ? null : () => _eliminarDomicilio(slot),
                            child: const Text('Eliminar'),
                          ),
                        ),
                      if (exists) const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _guardando ? null : () => _guardarDomicilio(slot),
                          child: Text(_guardando ? 'Guardando...' : 'Guardar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        }).toList()
          ..addAll(
            addressCount == 0 && _editingAddressSlot == null
                ? [
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'No hay domicilios registrados.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  ]
                : [],
          ),
      ),
    );
  }

  Widget _buildAddressEditor(int slot) {
    void setField(String field, String value) {
      setState(() {
        final current = _addresses[slot]!;

        switch (field) {
          case 'calle':
            _addresses[slot] = current.copyWith(calle: value);
            break;
          case 'numeroExterior':
            _addresses[slot] = current.copyWith(numeroExterior: value);
            break;
          case 'numeroInterior':
            _addresses[slot] = current.copyWith(numeroInterior: value);
            break;
          case 'colonia':
            _addresses[slot] = current.copyWith(colonia: value);
            break;
          case 'ciudad':
            _addresses[slot] = current.copyWith(ciudad: value);
            break;
          case 'municipio':
            _addresses[slot] = current.copyWith(municipio: value);
            break;
          case 'estado':
            _addresses[slot] = current.copyWith(estado: value);
            break;
          case 'codigoPostal':
            _addresses[slot] = current.copyWith(codigoPostal: value);
            break;
          case 'referencias':
            _addresses[slot] = current.copyWith(referencias: value);
            break;
        }
      });
    }

    final address = _addresses[slot]!;

    return Column(
      children: [
        TextFormField(
          initialValue: address.calle,
          decoration: const InputDecoration(
            labelText: 'Calle',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setField('calle', v),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: address.numeroExterior,
                decoration: const InputDecoration(
                  labelText: 'Número exterior',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setField('numeroExterior', v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: address.numeroInterior,
                decoration: const InputDecoration(
                  labelText: 'Número interior',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setField('numeroInterior', v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: address.colonia,
          decoration: const InputDecoration(
            labelText: 'Colonia',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setField('colonia', v),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: address.ciudad,
                decoration: const InputDecoration(
                  labelText: 'Ciudad',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setField('ciudad', v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: address.municipio,
                decoration: const InputDecoration(
                  labelText: 'Municipio',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setField('municipio', v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: address.estado,
                decoration: const InputDecoration(
                  labelText: 'Estado',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setField('estado', v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: address.codigoPostal,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                decoration: const InputDecoration(
                  labelText: 'Código postal',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setField('codigoPostal', v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: address.referencias,
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Referencias',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setField('referencias', v),
        ),
      ],
    );
  }

  Widget _buildDatosClienteSection(BuildContext context) {
    return _buildPanelCard(
      context: context,
      title: 'Editar cliente',
      subtitle: 'Actualiza la información principal del cliente.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nombreCtrl,
            enabled: !_guardando,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              border: OutlineInputBorder(),
            ),
            validator: _validarNombre,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _apellidosCtrl,
            enabled: !_guardando,
            decoration: const InputDecoration(
              labelText: 'Apellidos',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _empresaCtrl,
            enabled: !_guardando,
            decoration: const InputDecoration(
              labelText: 'Empresa',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _telCtrl,
            enabled: !_guardando,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              PhoneSpacingFormatter(maxDigits: 15),
            ],
            decoration: const InputDecoration(
              labelText: 'Teléfono',
              border: OutlineInputBorder(),
              hintText: '333 123 4567',
            ),
            validator: _validarTelefono,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _correoCtrl,
            enabled: !_guardando,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Correo',
              border: OutlineInputBorder(),
            ),
            validator: _validarCorreo,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _guardando ? null : _guardarPerfil,
            icon: _guardando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(_guardando ? 'Guardando…' : 'Guardar cambios'),
          ),
          const SizedBox(height: 20),
          _buildDangerZone(context),
        ],
      ),
    );
  }

  Widget _buildNoticiasList(List<Noticia> items) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(left: 8, top: 8, bottom: 8),
        child: Text('Sin registros'),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final n = items[i];
        final fecha = n.fechaCita;
        final fechaTxt = (fecha != null)
            ? DateFormat('dd/MM/yyyy hh:mm a', 'es_MX').format(fecha)
            : 'Sin fecha';

        final rep = n.reportero.trim().isEmpty
            ? 'Sin reportero'
            : n.reportero.trim();

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.article_outlined),
          title: Text(n.noticia),
          subtitle: Text('$fechaTxt • $rep'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NoticiaDetallePage(
                  noticia: n,
                  role: 'admin',
                  soloLectura: true,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNoticiasClienteSection(BuildContext context) {
    final agendadas = _noticiasCliente.where((n) => n.pendiente).toList();
    final terminadas = _noticiasCliente.where((n) => !n.pendiente).toList();

    final visibles = _filtroNoticias == 'agendadas' ? agendadas : terminadas;

    return _buildPanelCard(
      context: context,
      title: 'Noticias del cliente',
      subtitle: 'Consulta el historial y las noticias activas asociadas.',
      trailing: IconButton(
        tooltip: 'Actualizar noticias',
        icon: const Icon(Icons.refresh),
        onPressed: _cargandoNoticias ? null : _cargarNoticiasCliente,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            segments: [
              ButtonSegment<String>(
                value: 'agendadas',
                label: Text('Agendadas (${agendadas.length})'),
                icon: const Icon(Icons.schedule),
              ),
              ButtonSegment<String>(
                value: 'terminadas',
                label: Text('Terminadas (${terminadas.length})'),
                icon: const Icon(Icons.check_circle_outline),
              ),
            ],
            selected: {_filtroNoticias},
            onSelectionChanged: (value) {
              setState(() => _filtroNoticias = value.first);
            },
          ),
          const SizedBox(height: 16),
          if (_cargandoNoticias)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorNoticias != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _errorNoticias!,
                style: const TextStyle(color: Colors.red),
              ),
            )
          else
            _buildNoticiasList(visibles),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            onPressed: (_cargando || _guardando) ? null : _guardarPerfil,
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
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth >= _kDesktopBreakpoint;

                    final content = Column(
                      children: [
                        _buildResumenClienteHeader(context),
                        const SizedBox(height: 16),
                        isDesktop
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Column(
                                    children: [
                                      _buildDatosClienteSection(context),
                                      const SizedBox(height: 16),
                                      _buildDomiciliosSection(context),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 6,
                                  child: _buildNoticiasClienteSection(context),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                _buildDatosClienteSection(context),
                                const SizedBox(height: 16),
                                _buildDomiciliosSection(context),
                                const SizedBox(height: 16),
                                _buildNoticiasClienteSection(context),
                              ],
                            ),
                      ],
                    );

                    return Form(
                      key: _formKey,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                            child: content,
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}