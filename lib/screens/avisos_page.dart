// lib/screens/avisos_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/aviso.dart';
import '../services/api_service.dart';

class AvisosPage extends StatefulWidget {
  const AvisosPage({super.key});

  @override
  State<AvisosPage> createState() => _AvisosPageState();
}

class _AvisosPageState extends State<AvisosPage> {
  bool _loading = true;
  String? _error;
  List<Aviso> _avisos = const [];

  final _fmt = DateFormat('dd/MM/yyyy');

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

      setState(() => _avisos = activos);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _mostrarDetalle(Aviso a) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(a.titulo),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.descripcion),
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
                        a.descripcion,
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
