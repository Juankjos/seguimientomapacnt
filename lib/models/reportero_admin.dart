class ReporteroAdmin {
  final int id;
  final String nombre;
  final String? role;

  ReporteroAdmin({
    required this.id,
    required this.nombre,
    this.role
  });

  factory ReporteroAdmin.fromJson(Map<String, dynamic> json) {
    return ReporteroAdmin(
      id: int.parse(json['id'].toString()),
      nombre: (json['nombre'] ?? '').toString(),
      role: json['role']?.toString() ?? 'reportero',
    );
  }
}
