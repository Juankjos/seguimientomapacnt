import 'package:flutter/material.dart';

import '../models/noticia.dart';
import '../services/api_service.dart';

class TomarNoticiasPage extends StatefulWidget {
  final int reporteroId;
  final String reporteroNombre;

  const TomarNoticiasPage({
    super.key,
    required this.reporteroId,
    required this.reporteroNombre,
  });

  @override
  State<TomarNoticiasPage> createState() => _TomarNoticiasPageState();
}

class _TomarNoticiasPageState extends State<TomarNoticiasPage> {
  bool _loading = false;
  String? _error;
  List<Noticia> _noticias = [];

  @override
  void initState() {
    super.initState();
    _cargarNoticias();
  }

  Future<void> _cargarNoticias() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await ApiService.getNoticiasDisponibles();
      setState(() {
        _noticias = list;
      });
    } catch (e) {
      setState(() {
        _error = 'Error al cargar noticias: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _confirmarTomar(Noticia noticia) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tomar noticia'),
        content: Text(
          '¿Seguro que deseas tomar la noticia:\n\n"${noticia.noticia}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await _tomarNoticia(noticia);
    }
  }

  Future<void> _tomarNoticia(Noticia noticia) async {
    try {
      await ApiService.tomarNoticia(
        reporteroId: widget.reporteroId,
        noticiaId: noticia.id,
      );

      setState(() {
        _noticias.removeWhere((n) => n.id == noticia.id);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Has tomado la noticia "${noticia.noticia}".'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo tomar la noticia: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tomar noticias'),
      ),
      body: RefreshIndicator(
        onRefresh: _cargarNoticias,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 40),
          Center(child: Text(_error!)),
        ],
      );
    }

    if (_noticias.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 40),
          Center(child: Text('No hay noticias disponibles para tomar.')),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _noticias.length,
      itemBuilder: (context, index) {
        final n = _noticias[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            title: Text(
              n.noticia,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (n.descripcion != null &&
                    n.descripcion!.trim().isNotEmpty)
                  Text(n.descripcion!),
                if (n.cliente != null &&
                    n.cliente!.trim().isNotEmpty)
                  Text('Cliente: ${n.cliente}'),
              ],
            ),
            trailing: const Icon(Icons.add_circle_outline),
            onTap: () => _confirmarTomar(n),
          ),
        );
      },
    );
  }
}
