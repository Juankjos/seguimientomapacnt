// lib/models/reportero_admin.dart
class ReporteroAdmin {
  final int id;
  final String nombre;
  final String role;
  final bool puedeCrearNoticias;

  ReporteroAdmin({
    required this.id,
    required this.nombre,
    required this.role,
    this.puedeCrearNoticias = false,
  });

  factory ReporteroAdmin.fromJson(Map<String, dynamic> json) {
    final v = json['puede_crear_noticias'];

    bool toBool(dynamic x) {
      if (x == null) return false;
      if (x is bool) return x;
      if (x is num) return x.toInt() == 1;
      final s = x.toString().trim().toLowerCase();
      return s == '1' || s == 'true' || s == 'yes' || s == 'si';
    }

    return ReporteroAdmin(
      id: int.parse(json['id'].toString()),
      nombre: (json['nombre'] ?? '').toString(),
      role: (json['role'] ?? 'reportero').toString(),
      puedeCrearNoticias: toBool(v),
    );
  }
}
