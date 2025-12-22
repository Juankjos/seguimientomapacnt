import 'package:flutter/material.dart';

import '../models/noticia.dart';
import '../models/reportero_admin.dart';
import '../services/api_service.dart';
import 'reportero_noticias_page.dart';

class GestionNoticiasPage extends StatefulWidget {
  const GestionNoticiasPage({super.key});

  @override
  State<GestionNoticiasPage> createState() => _GestionNoticiasPageState();
}

class _GestionNoticiasPageState extends State<GestionNoticiasPage> {
  final _searchCtrl = TextEditingController();

  bool _cargando = true;
  String? _error;

  List<ReporteroAdmin> _reporteros = [];
  Map<int, int> _conteo = {}; // reporteroId -> #noticias

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _colorFromId(int id) {
    final colors = <Color>[
      Colors.blue, Colors.green, Colors.orange, Colors.purple,
      Colors.teal, Colors.indigo, Colors.red, Colors.brown,
    ];
    return colors[id % colors.length];
  }

  Widget _avatarDefault({required int id, required String nombre, double radius = 36}) {
    final letter = nombre.trim().isNotEmpty ? nombre.trim()[0].toUpperCase() : '?';
    final c = _colorFromId(id);
    return CircleAvatar(
      radius: radius,
      backgroundColor: c.withOpacity(0.18),
      child: Text(
        letter,
        style: TextStyle(fontSize: radius * 0.65, fontWeight: FontWeight.w800, color: c),
      ),
    );
  }

  Future<void> _cargar({String q = ''}) async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final reps = await ApiService.getReporterosAdmin(q: q);

      // Una sola llamada para contar por reportero:
      final List<Noticia> todas = await ApiService.getNoticiasAdmin();

      final Map<int, int> conteo = {};
      for (final n in todas) {
        final rid = n.reporteroId;
        if (rid == null) continue;
        conteo[rid] = (conteo[rid] ?? 0) + 1;
      }

      setState(() {
        _reporteros = reps;
        _conteo = conteo;
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  Future<void> _abrir(ReporteroAdmin r) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReporteroNoticiasPage(reportero: r),
      ),
    );

    // Al volver, refrescamos por si hubo reasignación
    await _cargar(q: _searchCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión Noticias'),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            onPressed: () => _cargar(q: _searchCtrl.text.trim()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar reportero…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _cargar(q: '');
                          setState(() {});
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) => _cargar(q: v.trim()),
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _cargar(q: _searchCtrl.text.trim()),
                        child: GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.82,
                          ),
                          itemCount: _reporteros.length,
                          itemBuilder: (context, i) {
                            final r = _reporteros[i];
                            final count = _conteo[r.id] ?? 0;

                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _abrir(r),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: Theme.of(context).colorScheme.surface,
                                  boxShadow: [
                                    BoxShadow(
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                      color: Colors.black.withOpacity(0.08),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _avatarDefault(id: r.id, nombre: r.nombre, radius: 36),
                                    const SizedBox(height: 8),
                                    Text(
                                      r.nombre,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(999),
                                        color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                                      ),
                                      child: Text(
                                        '$count noticias',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Theme.of(context).colorScheme.primary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
