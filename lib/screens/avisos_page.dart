// lib/screens/avisos_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'dart:convert';
import '../models/aviso.dart';
import '../services/api_service.dart';

class AvisosPage extends StatefulWidget {
  const AvisosPage({
    super.key,
    this.openAvisoId,
  });

  /// Si viene desde notificación, este ID se usa para abrir el modal automáticamente.
  final int? openAvisoId;

  @override
  State<AvisosPage> createState() => _AvisosPageState();
}
class _AvisoRichView extends StatefulWidget {
  const _AvisoRichView({
    required this.doc,
    this.height = 260,
  });

  final quill.Document doc;
  final double height;

  @override
  State<_AvisoRichView> createState() => _AvisoRichViewState();
}

class _AvisoRichViewState extends State<_AvisoRichView> {
  late final quill.QuillController _c;
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _c = quill.QuillController(
      document: widget.doc,
      selection: const TextSelection.collapsed(offset: 0),
    )..readOnly = true;
  }

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.maxFinite,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: quill.QuillEditor.basic(
            controller: _c,
            focusNode: _focus,
            scrollController: _scroll,
            config: const quill.QuillEditorConfig(
              expands: true,
              padding: EdgeInsets.zero,
              autoFocus: false,
              showCursor: false,
            ),
          ),
        ),
      ),
    );
  }
}

class _AvisosPageState extends State<AvisosPage> {
  bool _loading = true;
  String? _error;
  List<Aviso> _avisos = const [];

  final _fmt = DateFormat('dd/MM/yyyy');

  bool _autoOpened = false;

  quill.Document? _tryParseDeltaDoc(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return quill.Document.fromJson(decoded);
      }
    } catch (_) {
    }
    return null;
  }

  String _plainPreviewFromDescripcion(String raw) {
    final doc = _tryParseDeltaDoc(raw);
    final text = (doc == null) ? raw : doc.toPlainText();

    return text
        .replaceAll('\r', '')
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await ApiService.getAvisos();

      // refuerzo local: filtrar expirados por si acaso
      final now = DateTime.now();
      final activos = list.where((a) => a.vigencia.isAfter(now)).toList();

      if (mounted) setState(() => _avisos = activos);

      final targetId = widget.openAvisoId;
      if (!_autoOpened && targetId != null) {
        _autoOpened = true;

        Aviso? found;
        for (final a in activos) {
          if (a.id == targetId) {
            found = a;
            break;
          }
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          if (found != null) {
            _mostrarDetalle(found!);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'El aviso #$targetId ya no está disponible (pudo haber vencido).',
                ),
              ),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _mostrarDetalle(Aviso a) {
    final doc = _tryParseDeltaDoc(a.descripcion);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(a.titulo),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (doc == null)
                Text(a.descripcion)
              else
                _AvisoRichView(doc: doc),

              const SizedBox(height: 14),
              Text(
                'Vigente hasta: ${_fmt.format(a.vigencia.toLocal())}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    } else if (_avisos.isEmpty) {
      body = Center(
        child: Text(
          'No hay avisos vigentes.',
          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7)),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _cargar,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: _avisos.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final a = _avisos[i];
            final vig = _fmt.format(a.vigencia.toLocal());
            final preview = _plainPreviewFromDescripcion(a.descripcion);

            return Card(
              elevation: 1.6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _mostrarDetalle(a),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.titulo,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      
                      Text(
                        preview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.82),
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.event, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Vigente hasta: $vig',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Avisos'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _cargar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          )
        ],
      ),
      body: body,
    );
  }
}
