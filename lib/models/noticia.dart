class Noticia {
  final int id;
  final String noticia;
  final String? cliente;      // opcional
  final String domicilio;
  final String reportero;
  final DateTime fechaCita;
  final DateTime? fechaPago;  // opcional
  final double? latitud;
  final double? longitud;

  Noticia({
    required this.id,
    required this.noticia,
    required this.domicilio,
    required this.reportero,
    required this.fechaCita,
    this.cliente,
    this.fechaPago,
    this.latitud,
    this.longitud,
  });

  factory Noticia.fromJson(Map<String, dynamic> json) {
    double? _parseDouble(dynamic v) {
      if (v == null || v == '') return null;
      return double.tryParse(v.toString());
    }

    return Noticia(
      id: int.parse(json['id'].toString()),
      noticia: json['noticia'] ?? '',
      cliente: json['cliente'],
      domicilio: json['domicilio'] ?? '',
      reportero: json['reportero'] ?? '',
      fechaCita: DateTime.parse(json['fecha_cita']),
      fechaPago: json['fecha_pago'] != null && json['fecha_pago'] != ''
          ? DateTime.parse(json['fecha_pago'])
          : null,
      latitud: _parseDouble(json['latitud']),
      longitud: _parseDouble(json['longitud']),
    );
  }
}
