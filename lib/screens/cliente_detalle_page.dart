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

class _ClienteDetallePageState extends State<ClienteDetallePage> {
  late Cliente _cliente;

  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _domCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();

  static const double _kDesktopBreakpoint = 1100;
  static const double _kMaxContentWidth = 1450;

  bool _cargando = false;
  bool _guardando = false;
  String? _error;

  List<Noticia> _noticiasCliente = [];
  bool _cargandoNoticias = false;
  String? _errorNoticias;

  String _filtroNoticias = 'agendadas';
  String _lada = '+52';

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

  @override
  void initState() {
    super.initState();
    _cliente = widget.cliente;
    _hidratarFormDesdeCliente(_cliente);
    _cargarNoticiasCliente();
    _refrescar();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telCtrl.dispose();
    _domCtrl.dispose();
    _correoCtrl.dispose();
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
    _correoCtrl.text = (c.correo ?? '');
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

  Future<void> _guardar() async {
    if (_guardando) return;
    if (!_formKey.currentState!.validate()) return;

    final nombre = _nombreCtrl.text.trim();
    final telDigits = _telCtrl.text.replaceAll(RegExp(r'\D'), '');
    final whatsapp = telDigits.isEmpty ? null : '$_lada$telDigits';
    final domicilio = _domCtrl.text.trim().isEmpty ? null : _domCtrl.text.trim();
    final correo = _correoCtrl.text.trim();

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
        correo: correo,
      );

      if (!mounted) return;

      setState(() {
        _cliente = updated;
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

  Future<void> _cargarNoticiasCliente() async {
    setState(() {
      _cargandoNoticias = true;
      _errorNoticias = null;
    });

    try {
      final list = await ApiService.getNoticiasPorCliente(clienteId: _cliente.id);
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
    final rawWhatsapp = (_cliente.whatsapp ?? '').trim();
    final domicilioDisplay = (_cliente.domicilio ?? '').trim();
    final correoDisplay = (_cliente.correo ?? '').trim();

    final parsed = _parseWhatsapp(rawWhatsapp);
    final whatsappPretty = rawWhatsapp.isEmpty
        ? 'Sin WhatsApp'
        : '${parsed.lada} ${_formatPhoneDigits(parsed.digits)}';

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
                _cliente.nombre.isNotEmpty ? _cliente.nombre[0].toUpperCase() : '?',
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
                    _cliente.nombre,
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
                        text: whatsappPretty,
                        onCopy: rawWhatsapp.isEmpty
                            ? null
                            : () => _copiar('${parsed.lada}${parsed.digits}'),
                      ),
                      _infoChip(
                        context,
                        icon: Icons.email_outlined,
                        text: correoDisplay.isEmpty ? 'Sin correo' : correoDisplay,
                        onCopy: correoDisplay.isEmpty ? null : () => _copiar(correoDisplay),
                      ),
                      _infoChip(
                        context,
                        icon: Icons.location_on_outlined,
                        text: domicilioDisplay.isEmpty ? 'Sin domicilio' : domicilioDisplay,
                        onCopy: domicilioDisplay.isEmpty ? null : () => _copiar(domicilioDisplay),
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
                  onChanged: _guardando
                      ? null
                      : (v) {
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
            controller: _correoCtrl,
            enabled: !_guardando,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Correo',
              border: OutlineInputBorder(),
              hintText: 'ejemplo@gmail.com',
            ),
            validator: _validarCorreo,
            textInputAction: TextInputAction.next,
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

          const SizedBox(height: 16),
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
        final rep = (n.reportero ?? '').trim().isEmpty
            ? 'Sin reportero'
            : n.reportero!.trim();

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
    final agendadas = _noticiasCliente
        .where((n) => (n.pendiente ?? true) == true)
        .toList();

    final terminadas = _noticiasCliente
        .where((n) => (n.pendiente ?? true) == false)
        .toList();

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
                                    child: _buildDatosClienteSection(context),
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