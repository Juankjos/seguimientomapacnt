// lib/models/aviso.dart
class Aviso {
  final int id;
  final String titulo;
  final String descripcion;
  final DateTime vigencia;

  Aviso({
    required this.id,
    required this.titulo,
    required this.descripcion,
    required this.vigencia,
  });

  factory Aviso.fromJson(Map<String, dynamic> json) {
    final id = int.parse(json['id'].toString());
    final titulo = (json['titulo'] ?? '').toString();
    final descripcion = (json['descripcion'] ?? '').toString();

    // backend manda "YYYY-MM-DD HH:MM:SS"
    final raw = (json['vigencia'] ?? '').toString().trim();
    final norm = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    final dt = DateTime.tryParse(norm) ?? DateTime.now();

    return Aviso(
      id: id,
      titulo: titulo,
      descripcion: descripcion,
      vigencia: dt,
    );
  }
}
