class ReporteroAdmin {
  final int id;
  final String nombre;

  ReporteroAdmin({
    required this.id,
    required this.nombre,
  });

  factory ReporteroAdmin.fromJson(Map<String, dynamic> json) {
    return ReporteroAdmin(
      id: int.parse(json['id'].toString()),
      nombre: (json['nombre'] ?? '').toString(),
    );
  }
}
