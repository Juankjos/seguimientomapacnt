class AdminNotificacion {
  final int id;
  final String tipo;
  final int noticiaId;
  final int? reporteroId;
  final String mensaje;
  final DateTime? createdAt;
  final bool leida;

  AdminNotificacion({
    required this.id,
    required this.tipo,
    required this.noticiaId,
    required this.reporteroId,
    required this.mensaje,
    required this.createdAt,
    required this.leida,
  });

  factory AdminNotificacion.fromJson(Map<String, dynamic> json) {
    return AdminNotificacion(
      id: int.parse(json['id'].toString()),
      tipo: (json['tipo'] ?? '').toString(),
      noticiaId: int.parse(json['noticia_id'].toString()),
      reporteroId: json['reportero_id'] == null
          ? null
          : int.tryParse(json['reportero_id'].toString()),
      mensaje: (json['mensaje'] ?? '').toString(),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(
              json['created_at'].toString().replaceFirst(' ', 'T'),
            ),
      leida: json['leida'].toString() == '1' || json['leida'] == true,
    );
  }
}

class AdminNotificacionFeed {
  final int unreadCount;
  final List<AdminNotificacion> items;

  AdminNotificacionFeed({
    required this.unreadCount,
    required this.items,
  });
}