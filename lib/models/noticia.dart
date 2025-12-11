class Noticia {
  final int id;
  final String noticia;
  final String? descripcion;
  final String? cliente;
  final String? domicilio;
  final String reportero;
  final DateTime? fechaCita;
  final DateTime? fechaPago;
  final double? latitud;
  final double? longitud;

  Noticia({
    required this.id,
    required this.noticia,
    required this.reportero,
    this.descripcion,
    this.cliente,
    this.domicilio,
    this.fechaCita,
    this.fechaPago,
    this.latitud,
    this.longitud,
  });

  factory Noticia.fromJson(Map<String, dynamic> json) {
    double? _parseDouble(dynamic v) {
      if (v == null || v == '') return null;
      return double.tryParse(v.toString());
    }

    DateTime? _parseDate(dynamic v) {
      if (v == null || v == '') return null;
      return DateTime.tryParse(v.toString());
    }

    return Noticia(
      id: int.parse(json['id'].toString()),
      noticia: json['noticia'] ?? '',
      descripcion: json['descripcion'],
      cliente: json['cliente'],
      domicilio: json['domicilio'],
      reportero: json['reportero'] ?? '',
      fechaCita: _parseDate(json['fecha_cita']),
      fechaPago: _parseDate(json['fecha_pago']),
      latitud: _parseDouble(json['latitud']),
      longitud: _parseDouble(json['longitud']),
    );
  }
}
