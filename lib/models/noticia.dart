// lib/models/noticia.dart
class Noticia {
  final int id;
  final String noticia;
  final String tipoDeNota;
  final String? descripcion;
  final String? ubicacionEnMapa;
  final String? cliente;
  final int? clienteId;
  final String? clienteWhatsapp;
  final String? domicilio;  
  final int? reporteroId;
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
  final bool rutaIniciada;
  final DateTime? rutaIniciadaAt;
  final int? tiempoEnNota;
  final int limiteTiempoMinutos;

  final DateTime? ultimaMod;

  Noticia({
    required this.id,
    required this.noticia,
    this.tipoDeNota = 'Nota',
    required this.reportero,
    this.descripcion,
    this.cliente,
    this.clienteId,
    this.clienteWhatsapp,
    this.domicilio,
    this.ubicacionEnMapa,
    this.reporteroId,
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
    this.rutaIniciada = false,
    this.rutaIniciadaAt,
    this.ultimaMod,
    this.tiempoEnNota,
    this.limiteTiempoMinutos = 60,
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

    int? parseNullableInt(dynamic v) {
      if (v == null || v.toString().isEmpty) return null;
      return int.tryParse(v.toString());
    }

    bool parseBool0(dynamic v) {
      if (v == null) return false;
      final s = v.toString().trim().toLowerCase();
      return s == '1' || s == 'true';
    }

    String parseTipo(dynamic v) {
      final s = (v ?? '').toString().trim();
      if (s == 'Entrevista') return 'Entrevista';
      return 'Nota';
    }

    return Noticia(
      id: int.parse(json['id'].toString()),
      noticia: json['noticia'] ?? '',
      tipoDeNota: parseTipo(json['tipo_de_nota']),
      descripcion: json['descripcion'],
      cliente: json['cliente'],
      clienteId: json['cliente_id'] == null ? null : int.tryParse(json['cliente_id'].toString()),
      clienteWhatsapp: json['cliente_whatsapp']?.toString(),
      domicilio: json['domicilio'],
      ubicacionEnMapa: json['ubicacion_en_mapa']?.toString(),
      reporteroId: parseNullableInt(json['reportero_id']),
      reportero: json['reportero'] ?? '',
      fechaCita: parseDate(json['fecha_cita']),
      fechaCitaAnterior: parseDateTime(json['fecha_cita_anterior']),
      fechaCitaCambios: parseInt(json['fecha_cita_cambios']),
      fechaPago: parseDate(json['fecha_pago']),
      latitud: parseDouble(json['latitud']),
      longitud: parseDouble(json['longitud']),
      horaLlegada: parseDateTime(json['hora_llegada']),
      llegadaLatitud: parseDouble(json['llegada_latitud']),
      llegadaLongitud: parseDouble(json['llegada_longitud']),
      pendiente: parseBool(json['pendiente']),
      ultimaMod: parseDateTime(json['ultima_mod']), 
      rutaIniciada: parseBool0(json['ruta_iniciada']),
      rutaIniciadaAt: parseDateTime(json['ruta_iniciada_at']),
      tiempoEnNota: parseNullableInt(json['tiempo_en_nota']),
      limiteTiempoMinutos: (() { final v = json['limite_tiempo_minutos']; 
        final n = int.tryParse(v?.toString() ?? '');
        return (n != null && n >= 60) ? n : 60;
    })(),
    );
  }

  Noticia copyWith({
    int? clienteId,
    String? cliente,
    String? clienteWhatsapp,
    String? domicilio,
    String? ubicacionEnMapa,
    double? latitud,
    double? longitud,
    DateTime? horaLlegada,
    double? llegadaLatitud,
    double? llegadaLongitud,
    int? tiempoEnNota,
    int? limiteTiempoMinutos,
    DateTime? ultimaMod,
  }) {
    return Noticia(
      id: id,
      noticia: noticia,
      tipoDeNota: tipoDeNota,
      reportero: reportero,
      descripcion: descripcion,
      cliente: cliente,
      clienteId: clienteId ?? this.clienteId,
      clienteWhatsapp: clienteWhatsapp ?? this.clienteWhatsapp,
      domicilio: domicilio ?? this.domicilio,
      ubicacionEnMapa: ubicacionEnMapa ?? this.ubicacionEnMapa,
      reporteroId: reporteroId,
      fechaCita: fechaCita,
      fechaCitaAnterior: fechaCitaAnterior,
      fechaCitaCambios: fechaCitaCambios,
      fechaPago: fechaPago,
      latitud: latitud ?? this.latitud,
      longitud: longitud ?? this.longitud,
      horaLlegada: horaLlegada ?? this.horaLlegada,
      llegadaLatitud: llegadaLatitud ?? this.llegadaLatitud,
      llegadaLongitud: llegadaLongitud ?? this.llegadaLongitud,
      pendiente: pendiente,
      rutaIniciada: rutaIniciada,
      rutaIniciadaAt: rutaIniciadaAt,
      ultimaMod: ultimaMod ?? this.ultimaMod,
      tiempoEnNota: tiempoEnNota ?? this.tiempoEnNota,
      limiteTiempoMinutos: limiteTiempoMinutos ?? this.limiteTiempoMinutos,
    );
  }
}
