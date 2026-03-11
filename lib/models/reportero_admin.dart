// lib/models/reportero_admin.dart
class ReporteroAdmin {
  final int id;
  final String nombre;
  final String role;
  final bool puedeCrearNoticias;
  final bool puedeVerGestionNoticias;
  final bool puedeVerEstadisticas;
  final bool puedeVerRastreoGeneral;
  final bool puedeVerEmpleadoMes;
  final bool puedeVerGestion;
  final bool puedeVerClientes;

  const ReporteroAdmin({
    required this.id,
    required this.nombre,
    required this.role,
    this.puedeCrearNoticias = false,
    this.puedeVerGestionNoticias = false,
    this.puedeVerEstadisticas = false,
    this.puedeVerRastreoGeneral = false,
    this.puedeVerEmpleadoMes = false,
    this.puedeVerGestion = false,
    this.puedeVerClientes = false,
  });

  static bool _toBool(dynamic x) {
    if (x == null) return false;
    if (x is bool) return x;
    if (x is num) return x.toInt() == 1;
    final s = x.toString().trim().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes' || s == 'si';
  }

  factory ReporteroAdmin.fromJson(Map<String, dynamic> json) {
    return ReporteroAdmin(
      id: int.parse(json['id'].toString()),
      nombre: (json['nombre'] ?? '').toString(),
      role: (json['role'] ?? 'reportero').toString(),

      puedeCrearNoticias: _toBool(json['puede_crear_noticias']),

      puedeVerGestionNoticias: _toBool(json['puede_ver_gestion_noticias']),
      puedeVerEstadisticas: _toBool(json['puede_ver_estadisticas']),
      puedeVerRastreoGeneral: _toBool(json['puede_ver_rastreo_general']),
      puedeVerEmpleadoMes: _toBool(json['puede_ver_empleado_mes']),
      puedeVerGestion: _toBool(json['puede_ver_gestion']),
      puedeVerClientes: _toBool(json['puede_ver_clientes']),
    );
  }
}
