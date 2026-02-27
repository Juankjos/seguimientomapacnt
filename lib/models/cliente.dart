// lib/models/cliente.dart
class Cliente {
  final int id;
  final String nombre;
  final String? whatsapp;
  final String? domicilio;
  final String? correo;

  const Cliente({
    required this.id,
    required this.nombre,
    this.whatsapp,
    this.domicilio,
    this.correo,
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
      correo: (json['correo']?.toString().trim().isEmpty ?? true)
          ? null
          : json['correo'].toString(),
    );
  }

  Cliente copyWith({
    String? nombre,
    String? whatsapp,
    String? domicilio,
    String? correo,
  }) {
    return Cliente(
      id: id,
      nombre: nombre ?? this.nombre,
      whatsapp: whatsapp ?? this.whatsapp,
      domicilio: domicilio ?? this.domicilio,
      correo: correo ?? this.correo,
    );
  }
}