class Noticia {
  final int id;
  final String noticia;
  final String tipoDeNota;

  final int? peticionId;

  final String? descripcion;
  final String? ubicacionEnMapa;

  final String? cliente;

  // Compatibilidad + esquema nuevo
  final int? clienteId; 
  final int? clienteClienteId;
  final int? usuarioClienteId;

  final String? clienteTelefono;
  final String? clienteWhatsapp;
  final String? clienteEmail;

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

  const Noticia({
    required this.id,
    required this.noticia,
    this.tipoDeNota = 'Noticia',
    required this.reportero,
    this.peticionId,
    this.descripcion,
    this.cliente,
    this.clienteId,
    this.clienteClienteId,
    this.usuarioClienteId,
    this.clienteTelefono,
    this.clienteWhatsapp,
    this.clienteEmail,
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
      if (v == null || v.toString().trim().isEmpty) return null;
      return double.tryParse(v.toString());
    }

    int? parseNullableInt(dynamic v) {
      if (v == null || v.toString().trim().isEmpty) return null;
      return int.tryParse(v.toString());
    }

    int parseInt(dynamic v, {int fallback = 0}) {
      return int.tryParse(v?.toString() ?? '') ?? fallback;
    }

    DateTime? parseDateTime(dynamic v) {
      if (v == null || v.toString().trim().isEmpty) return null;
      final s = v.toString().trim().replaceFirst(' ', 'T');
      return DateTime.tryParse(s);
    }

    bool parseBool(dynamic v, {bool fallback = false}) {
      if (v == null) return fallback;
      final s = v.toString().trim().toLowerCase();
      return s == '1' || s == 'true';
    }

    String parseTipo(dynamic v) {
      final s = (v ?? '').toString().trim();
      switch (s) {
        case 'Entrevista':
          return 'Entrevista';
        case 'Reportaje':
          return 'Reportaje';
        case 'Noticia':
          return 'Noticia';
        case 'Nota': // compatibilidad con respuestas viejas
          return 'Noticia';
        default:
          return 'Noticia';
      }
    }

    final int? clienteClienteId =
        parseNullableInt(json['cliente_cliente_id'] ?? json['cliente_id']);

    final String? clienteTelefono =
        (json['cliente_telefono'] ?? json['cliente_whatsapp'])?.toString();

    return Noticia(
      id: parseInt(json['id']),
      noticia: (json['noticia'] ?? '').toString(),
      tipoDeNota: parseTipo(json['tipo_de_nota']),
      peticionId: parseNullableInt(json['peticion_id']),
      descripcion: json['descripcion']?.toString(),
      cliente: json['cliente']?.toString(),
      clienteId: clienteClienteId,
      clienteClienteId: clienteClienteId,
      usuarioClienteId: parseNullableInt(json['usuario_cliente_id']),
      clienteTelefono: clienteTelefono,
      clienteWhatsapp: clienteTelefono,
      clienteEmail: json['cliente_email']?.toString(),
      domicilio: json['domicilio']?.toString(),
      ubicacionEnMapa: json['ubicacion_en_mapa']?.toString(),
      reporteroId: parseNullableInt(json['reportero_id']),
      reportero: (json['reportero'] ?? '').toString(),
      fechaCita: parseDateTime(json['fecha_cita']),
      fechaCitaAnterior: parseDateTime(json['fecha_cita_anterior']),
      fechaCitaCambios: parseInt(json['fecha_cita_cambios']),
      fechaPago: parseDateTime(json['fecha_pago']),
      latitud: parseDouble(json['latitud']),
      longitud: parseDouble(json['longitud']),
      horaLlegada: parseDateTime(json['hora_llegada']),
      llegadaLatitud: parseDouble(json['llegada_latitud']),
      llegadaLongitud: parseDouble(json['llegada_longitud']),
      pendiente: parseBool(json['pendiente'], fallback: true),
      rutaIniciada: parseBool(json['ruta_iniciada']),
      rutaIniciadaAt: parseDateTime(json['ruta_iniciada_at']),
      ultimaMod: parseDateTime(json['ultima_mod']),
      tiempoEnNota: parseNullableInt(json['tiempo_en_nota']),
      limiteTiempoMinutos: (() {
        final n = parseInt(json['limite_tiempo_minutos'], fallback: 60);
        return n < 60 ? 60 : n;
      })(),
    );
  }

  Noticia copyWith({
    String? noticia,
    String? tipoDeNota,
    String? descripcion,
    String? cliente,
    int? clienteId,
    int? clienteClienteId,
    int? usuarioClienteId,
    String? clienteTelefono,
    String? clienteWhatsapp,
    String? clienteEmail,
    String? domicilio,
    String? ubicacionEnMapa,
    DateTime? fechaCita,
    DateTime? fechaCitaAnterior,
    int? fechaCitaCambios,
    DateTime? fechaPago,
    double? latitud,
    double? longitud,
    DateTime? horaLlegada,
    double? llegadaLatitud,
    double? llegadaLongitud,
    bool? pendiente,
    bool? rutaIniciada,
    DateTime? rutaIniciadaAt,
    int? tiempoEnNota,
    int? limiteTiempoMinutos,
    DateTime? ultimaMod,
  }) {
    return Noticia(
      id: id,
      noticia: noticia ?? this.noticia,
      tipoDeNota: tipoDeNota ?? this.tipoDeNota,
      reportero: reportero,
      peticionId: peticionId,
      descripcion: descripcion ?? this.descripcion,
      cliente: cliente ?? this.cliente,
      clienteId: clienteId ?? this.clienteId,
      clienteClienteId: clienteClienteId ?? this.clienteClienteId,
      usuarioClienteId: usuarioClienteId ?? this.usuarioClienteId,
      clienteTelefono: clienteTelefono ?? this.clienteTelefono,
      clienteWhatsapp: clienteWhatsapp ?? this.clienteWhatsapp,
      clienteEmail: clienteEmail ?? this.clienteEmail,
      domicilio: domicilio ?? this.domicilio,
      ubicacionEnMapa: ubicacionEnMapa ?? this.ubicacionEnMapa,
      reporteroId: reporteroId,
      fechaCita: fechaCita ?? this.fechaCita,
      fechaCitaAnterior: fechaCitaAnterior ?? this.fechaCitaAnterior,
      fechaCitaCambios: fechaCitaCambios ?? this.fechaCitaCambios,
      fechaPago: fechaPago ?? this.fechaPago,
      latitud: latitud ?? this.latitud,
      longitud: longitud ?? this.longitud,
      horaLlegada: horaLlegada ?? this.horaLlegada,
      llegadaLatitud: llegadaLatitud ?? this.llegadaLatitud,
      llegadaLongitud: llegadaLongitud ?? this.llegadaLongitud,
      pendiente: pendiente ?? this.pendiente,
      rutaIniciada: rutaIniciada ?? this.rutaIniciada,
      rutaIniciadaAt: rutaIniciadaAt ?? this.rutaIniciadaAt,
      ultimaMod: ultimaMod ?? this.ultimaMod,
      tiempoEnNota: tiempoEnNota ?? this.tiempoEnNota,
      limiteTiempoMinutos: limiteTiempoMinutos ?? this.limiteTiempoMinutos,
    );
  }
}
