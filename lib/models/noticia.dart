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

  final DateTime? horaLlegada;
  final double? llegadaLatitud;
  final double? llegadaLongitud;
  final bool pendiente;

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
    this.horaLlegada,
    this.llegadaLatitud,
    this.llegadaLongitud,
    this.pendiente = true,
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

    bool _parseBool(dynamic v) {
      if (v == null) return true;
      final s = v.toString();
      return s == '1' || s.toLowerCase() == 'true';
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
      horaLlegada: _parseDate(json['hora_llegada']),
      llegadaLatitud: _parseDouble(json['llegada_latitud']),
      llegadaLongitud: _parseDouble(json['llegada_longitud']),
      pendiente: _parseBool(json['pendiente']),
    );
  }
}
