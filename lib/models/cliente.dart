// lib/models/cliente.dart
class Cliente {
  final int id;
  final String nombre;
  final String? whatsapp;
  final String? domicilio;

  const Cliente({
    required this.id,
    required this.nombre,
    this.whatsapp,
    this.domicilio,
  });

  factory Cliente.fromJson(Map<String, dynamic> json) {
    return Cliente(
      id: int.parse(json['id'].toString()),
      nombre: (json['nombre'] ?? '').toString(),
      whatsapp: (json['whatsapp']?.toString().trim().isEmpty ?? true)
          ? null
          : json['whatsapp'].toString(),
      domicilio: (json['domicilio']?.toString().trim().isEmpty ?? true)
          ? null
          : json['domicilio'].toString(),
    );
  }

  Cliente copyWith({
    String? nombre,
    String? whatsapp,
    String? domicilio,
  }) {
    return Cliente(
      id: id,
      nombre: nombre ?? this.nombre,
      whatsapp: whatsapp ?? this.whatsapp,
      domicilio: domicilio ?? this.domicilio,
    );
  }
}