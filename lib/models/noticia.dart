class Noticia {
  final int id;
  final String noticia;
  final String? descripcion;
  final String? cliente;
  final String? domicilio;  
  final String reportero;
  final DateTime? fechaCita;
  final DateTime? fechaCitaAnterior;
  final int fechaCitaCambios;
  final DateTime? fechaPago;
  final double? latitud;
  final double? longitud;

  final DateTime? horaLlegada;
  final double? llegadaLatitud;
  final double? llegadaLongitud;
  final bool pendiente;

  final DateTime? ultimaMod;

  Noticia({
    required this.id,
    required this.noticia,
    required this.reportero,
    this.descripcion,
    this.cliente,
    this.domicilio,
    this.fechaCita,
    this.fechaCitaAnterior,
    required this.fechaCitaCambios,
    this.fechaPago,
    this.latitud,
    this.longitud,
    this.horaLlegada,
    this.llegadaLatitud,
    this.llegadaLongitud,
    this.pendiente = true,
    this.ultimaMod,
  });

  factory Noticia.fromJson(Map<String, dynamic> json) {
    double? parseDouble(dynamic v) {
      if (v == null || v == '') return null;
      return double.tryParse(v.toString());
    }

    DateTime? parseDate(dynamic v) {
      if (v == null || v == '') return null;
      return DateTime.tryParse(v.toString());
    }

    bool parseBool(dynamic v) {
      if (v == null) return true;
      final s = v.toString();
      return s == '1' || s.toLowerCase() == 'true';
    }

    DateTime? parseDateTime(dynamic v) {
      if (v == null || v == '') return null;
      final s = v.toString().replaceFirst(' ', 'T');
      return DateTime.tryParse(s);
    }

    int parseInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;


    return Noticia(
      id: int.parse(json['id'].toString()),
      noticia: json['noticia'] ?? '',
      descripcion: json['descripcion'],
      cliente: json['cliente'],
      domicilio: json['domicilio'],
      reportero: json['reportero'] ?? '',
      fechaCita: parseDate(json['fecha_cita']),
      fechaCitaAnterior: parseDateTime(json['fecha_cita_anterior']),
      fechaCitaCambios: parseInt(json['fecha_cita_cambios']),
      fechaPago: parseDate(json['fecha_pago']),
      latitud: parseDouble(json['latitud']),
      longitud: parseDouble(json['longitud']),
      horaLlegada: parseDate(json['hora_llegada']),
      llegadaLatitud: parseDouble(json['llegada_latitud']),
      llegadaLongitud: parseDouble(json['llegada_longitud']),
      pendiente: parseBool(json['pendiente']),
      ultimaMod: parseDate(json['ultima_mod']), 
    );
  }
}
