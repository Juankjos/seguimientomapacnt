//lib/services/api_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/noticia.dart';
import '../models/reportero_admin.dart';

class ReporteroBusqueda {
  final int id;
  final String nombre;

  ReporteroBusqueda({required this.id, required this.nombre});

  factory ReporteroBusqueda.fromJson(Map<String, dynamic> json) {
    return ReporteroBusqueda(
      id: int.parse(json['id'].toString()),
      nombre: json['nombre'] ?? '',
    );
  }
}

class ApiService {

  static const String baseUrl = 'http://167.99.163.209:8080/seguimientomapacnt';
  static const String wsBaseUrl = 'ws://167.99.163.209:3001';
  static String wsToken = '';
  static String _mysqlDateTime(DateTime dt) => DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);

  // 🔹 Login
  static Future<Map<String, dynamic>> login(
      String nombre, String password) async {
    final url = Uri.parse('$baseUrl/login.php');

    final response = await http.post(
      url,
      body: {
        'nombre': nombre,
        'password': password,
      },
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      return data;
    } else {
      throw Exception('Error en la petición de login');
    }
  }

  // 🔹 Mostrar noticias creadas
  static Future<List<Noticia>> getNoticias(int reporteroId) async {
    final url =
        Uri.parse('$baseUrl/get_noticias.php?reportero_id=$reporteroId');

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);

      if (data['success'] == true) {
        final List<dynamic> list = data['data'] ?? [];
        return list.map((e) => Noticia.fromJson(e)).toList();
      } else {
        throw Exception(data['message'] ?? 'Error al obtener noticias');
      }
    } else {
      throw Exception('Error en el servidor (${response.statusCode})');
    }
  }

  // 🔹 Obtener noticias completadas
  static Future<List<Noticia>> getNoticiasAgenda(int reporteroId) async {
    final url = Uri.parse(
      '$baseUrl/get_noticias.php?reportero_id=$reporteroId&incluye_cerradas=1',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);

      if (data['success'] == true) {
        final List<dynamic> list = data['data'] ?? [];
        return list.map((e) => Noticia.fromJson(e)).toList();
      } else {
        throw Exception(data['message'] ?? 'Error al obtener agenda');
      }
    } else {
      throw Exception('Error en el servidor (${response.statusCode})');
    }
  }

  // 🔹 Obtener todas las noticias (modo admin) usando get_noticias.php
  static Future<List<Noticia>> getNoticiasAdmin() async {
    final url = Uri.parse('$baseUrl/get_noticias.php?modo=admin');

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);

      if (data['success'] == true) {
        final List<dynamic> list = data['data'] ?? [];
        return list.map((e) => Noticia.fromJson(e)).toList();
      } else {
        throw Exception(data['message'] ?? 'Error al obtener noticias (admin)');
      }
    } else {
      throw Exception('Error en el servidor (${response.statusCode})');
    }
  }

  // 🔹 Crear noticia (admin)
  static Future<void> crearNoticia({
    required String noticia,
    String? descripcion,
    String? domicilio,
    int? reporteroId,
    DateTime? fechaCita,
  }) async {
    final url = Uri.parse('$baseUrl/crear_noticia.php');

    String? fechaCitaStr;
    if (fechaCita != null) {
      fechaCitaStr = fechaCita.toIso8601String().substring(0, 19).replaceFirst('T', ' ');
    }

    final body = {
      'noticia': noticia,
      'descripcion': descripcion ?? '',
      'domicilio': domicilio ?? '',
      'reportero_id': reporteroId?.toString() ?? '',
      'fecha_cita': fechaCitaStr ?? '',
    };

    final response = await http.post(url, body: body);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      if (data['success'] != true) {
        throw Exception(data['message'] ?? 'Error al crear noticia');
      }
    } else {
      throw Exception('Error en el servidor al crear noticia (${response.statusCode})');
    }
  }

  // 🔹 Borrar noticia (admin)
  static Future<void> deleteNoticiaSinAsignar({required int noticiaId}) async {
    final url = Uri.parse('$baseUrl/delete_noticia_sin_asignar.php');

    final resp = await http.post(url, body: {
      'noticia_id': noticiaId.toString(),
    });

    if (resp.statusCode != 200) {
      throw Exception('Error en servidor (${resp.statusCode}): ${resp.body}');
    }

    final Map<String, dynamic> data = json.decode(resp.body);
    if (data['success'] != true) {
      throw Exception(data['message'] ?? 'No se pudo borrar la noticia');
    }
  }

  // 🔹 Crear reportero
  static Future<ReporteroAdmin> createReportero({
    required String nombre,
    required String password,
    String role = 'reportero',
    bool puedeCrearNoticias = false,
  }) async {
    final url = Uri.parse('$baseUrl/create_reportero.php');

    final resp = await http.post(url, body: {
      'nombre': nombre.trim(),
      'password': password.trim(),
      'role': role.trim(),
      'puede_crear_noticias': puedeCrearNoticias ? '1' : '0',
    });

    if (resp.statusCode != 200) {
      throw Exception('Error en servidor (${resp.statusCode}): ${resp.body}');
    }

    final Map<String, dynamic> data = json.decode(resp.body);
    if (data['success'] != true) {
      throw Exception(data['message'] ?? 'No se pudo crear el reportero');
    }

    return ReporteroAdmin.fromJson(data['data'] as Map<String, dynamic>);
  }

  // 🔹 Actualizar reportero (nombre/password)
  static Future<ReporteroAdmin> updateReporteroAdmin({
    required int reporteroId,
    String? nombre,
    String? password,
    String? role,
    bool? puedeCrearNoticias,
  }) async {
    final url = Uri.parse('$baseUrl/update_perfil.php');

    final body = <String, String>{
      'reportero_id': reporteroId.toString(),
    };

    if (nombre != null && nombre.trim().isNotEmpty) {
      body['nombre'] = nombre.trim();
    }
    if (password != null && password.trim().isNotEmpty) {
      body['password'] = password.trim();
    }
    if (role != null && role.trim().isNotEmpty) {
      body['role'] = role.trim();
    }
    if (puedeCrearNoticias != null) {
      body['puede_crear_noticias'] = puedeCrearNoticias ? '1' : '0';
    }

    final resp = await http.post(url, body: body);

    if (resp.statusCode != 200) {
      throw Exception('Error en servidor (${resp.statusCode}): ${resp.body}');
    }

    final Map<String, dynamic> data = json.decode(resp.body);
    if (data['success'] != true) {
      throw Exception(data['message'] ?? 'No se pudo actualizar');
    }

    return ReporteroAdmin.fromJson(data['data'] as Map<String, dynamic>);
  }

  // 🔹 Listar reporteros para gestión
  static Future<List<ReporteroAdmin>> getReporterosAdmin({String q = ''}) async {
    final url = Uri.parse(
      '$baseUrl/search_reporteros.php?q=${Uri.encodeQueryComponent(q)}',
    );

    final resp = await http.get(url);

    if (resp.statusCode != 200) {
      throw Exception('Error en servidor (${resp.statusCode}): ${resp.body}');
    }

    final Map<String, dynamic> data = json.decode(resp.body);
    if (data['success'] != true) {
      throw Exception(data['message'] ?? 'Error al listar reporteros');
    }

    final List list = (data['data'] as List?) ?? [];
    return list
        .map((e) => ReporteroAdmin.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // 🔹 Borrar reportero
  static Future<void> deleteReportero({required int reporteroId}) async {
    final url = Uri.parse('$baseUrl/delete_reportero.php');

    final resp = await http.post(url, body: {
      'reportero_id': reporteroId.toString(),
    });

    if (resp.statusCode != 200) {
      throw Exception('Error en servidor (${resp.statusCode}): ${resp.body}');
    }

    final Map<String, dynamic> data = json.decode(resp.body);
    if (data['success'] != true) {
      throw Exception(data['message'] ?? 'No se pudo borrar el reportero');
    }
  }

  // 🔹 Actualizar perfil
  static Future<Map<String, dynamic>> updatePerfil({
    required int reporteroId,
    String? nombre,
    String? password,
    String? role, 
  }) async {
    final url = Uri.parse('$baseUrl/update_perfil.php');

    final body = <String, String>{
      'reportero_id': reporteroId.toString(),
    };

    if (nombre != null && nombre.trim().isNotEmpty) {
      body['nombre'] = nombre.trim();
    }
    if (password != null && password.trim().isNotEmpty) {
      body['password'] = password.trim();
    }
    if (role != null && role.trim().isNotEmpty) body['role'] = role.trim();

    final response = await http.post(url, body: body);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      if (data['success'] == true) return data;
      throw Exception(data['message'] ?? 'No se pudo actualizar el perfil');
    } else {
      throw Exception('Error en el servidor (${response.statusCode})');
    }
  }

  // 🔹 Noticias disponibles (sin reportero asignado / Nuevas)
  static Future<List<Noticia>> getNoticiasDisponibles() async {
    final url = Uri.parse('$baseUrl/get_noticias_disponibles.php');

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);

      if (data['success'] == true) {
        final List<dynamic> list = data['data'] ?? [];
        return list.map((e) => Noticia.fromJson(e)).toList();
      } else {
        throw Exception(data['message'] ?? 'Error al obtener noticias disponibles');
      }
    } else {
      throw Exception('Error en el servidor (${response.statusCode})');
    }
  }

  // 🔹 Asignar reportero a una noticia
  static Future<void> tomarNoticia({
    required int reporteroId,
    required int noticiaId,
  }) async {
    final url = Uri.parse('$baseUrl/tomar_noticia.php');

    final response = await http.post(
      url,
      body: {
        'reportero_id': reporteroId.toString(),
        'noticia_id': noticiaId.toString(),
      },
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      if (data['success'] != true) {
        throw Exception(data['message'] ?? 'No se pudo tomar la noticia');
      }
    } else {
      throw Exception('Error en el servidor (${response.statusCode})');
    }
  }

  // 🔹 Noticias de un reportero (incluye cerradas opcional)
  static Future<List<Noticia>> getNoticiasPorReportero({
    required int reporteroId,
    bool incluyeCerradas = true,
  }) async {
    final url = Uri.parse(
      '$baseUrl/get_noticias.php?reportero_id=$reporteroId&incluye_cerradas=${incluyeCerradas ? 1 : 0}',
    );

    final resp = await http.get(url);
    if (resp.statusCode != 200) {
      throw Exception('Error en servidor (${resp.statusCode}): ${resp.body}');
    }

    final Map<String, dynamic> data = json.decode(resp.body);
    if (data['success'] != true) {
      throw Exception(data['message'] ?? 'Error al obtener noticias');
    }

    final List list = (data['data'] as List?) ?? [];
    return list.map((e) => Noticia.fromJson(e as Map<String, dynamic>)).toList();
  }

  // 🔹 Reasignar / desasignar noticias (admin)
  static Future<void> reasignarNoticias({
    required List<int> noticiaIds,
    int? nuevoReporteroId,
  }) async {
    final url = Uri.parse('$baseUrl/reassign_noticias.php');

    final resp = await http.post(url, body: {
      'noticia_ids': json.encode(noticiaIds),
      'nuevo_reportero_id': (nuevoReporteroId ?? '').toString(),
    });

    if (resp.statusCode != 200) {
      throw Exception('Error en servidor (${resp.statusCode}): ${resp.body}');
    }

    final Map<String, dynamic> data = json.decode(resp.body);
    if (data['success'] != true) {
      throw Exception(data['message'] ?? 'No se pudo reasignar');
    }
  }

  // 🔹 Buscar reportero a una noticia
  static Future<List<ReporteroBusqueda>> buscarReporteros(String query) async {
    final url = Uri.parse('$baseUrl/search_reporteros.php?q=${Uri.encodeQueryComponent(query)}');

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      if (data['success'] == true) {
        final List<dynamic> list = data['data'] ?? [];
        return list
            .map((e) => ReporteroBusqueda.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception(data['message'] ?? 'Error al buscar reporteros');
      }
    } else {
      throw Exception('Error en el servidor al buscar reporteros (${response.statusCode})');
    }
  }
  // 🔹 Al llegar al destino, guardar lat y long de llegada
  static Future<void> registrarLlegadaNoticia({
    required int noticiaId,
    required double latitud,
    required double longitud,
  }) async {
    final url = Uri.parse('$baseUrl/update_llegada_noticia.php');

    final ahora = DateTime.now();
    final horaLlegadaStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(ahora);

    final response = await http.post(
      url,
      body: {
        'noticia_id': noticiaId.toString(),
        'latitud': latitud.toString(),
        'longitud': longitud.toString(),
        'hora_llegada': horaLlegadaStr,
      },
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      if (data['success'] != true) {
        throw Exception(data['message'] ?? 'Error al registrar llegada');
      }
    } else {
      throw Exception('Error en el servidor al registrar llegada (${response.statusCode})');
    }
  }

  // 🔹 Eliminar visualmente las noticias, se conservan en DB
  static Future<void> eliminarNoticiaDePendientes(int noticiaId) async {
    final url = Uri.parse('$baseUrl/update_pendiente_noticia.php');

    final response = await http.post(
      url,
      body: {
        'noticia_id': noticiaId.toString(),
      },
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      if (data['success'] != true) {
        throw Exception(data['message'] ?? 'Error al eliminar pendiente');
      }
    } else {
      throw Exception(
        'Error en el servidor al eliminar pendiente (${response.statusCode})',
      );
    }
  }

  // 🔹 Actualizar campos de noticia
  static Future<Noticia> actualizarNoticia({
    required int noticiaId,
    required String role,
    String? titulo,
    String? descripcion,
    DateTime? fechaCita,
  }) async {
    final url = Uri.parse('$baseUrl/update_noticia.php');

    String? fechaCitaStr;
    if (fechaCita != null) {
      fechaCitaStr = fechaCita.toIso8601String().substring(0, 19).replaceFirst('T', ' ');
    }

    final body = <String, String>{
      'noticia_id': noticiaId.toString(),
      'role': role,
      'ultima_mod': _mysqlDateTime(DateTime.now()),
    };

    if (titulo != null) body['noticia'] = titulo;
    if (descripcion != null) body['descripcion'] = descripcion;
    if (fechaCita != null) body['fecha_cita'] = fechaCitaStr!;

    final response = await http.post(url, body: body);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) {
        return Noticia.fromJson(data['data']);
      }
      throw Exception(data['message'] ?? 'Error al actualizar noticia');
    } else {
      throw Exception('Error en el servidor (${response.statusCode})');
    }
  }

  // 🔹 Cambiar ubicación de una noticia
  static Future<void> actualizarUbicacionNoticia({
    required int noticiaId,
    required double latitud,
    required double longitud,
    String? domicilio,
  }) async {
    final url = Uri.parse('$baseUrl/actualizar_ubicacion_noticia.php');

    final body = {
      'noticia_id': noticiaId.toString(),
      'latitud': latitud.toString(),
      'longitud': longitud.toString(),
      'ultima_mod': _mysqlDateTime(DateTime.now()),
    };

    if (domicilio != null && domicilio.isNotEmpty) {
      body['domicilio'] = domicilio;
    }

    final response = await http.post(url, body: body);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      if (data['success'] != true) {
        throw Exception(data['message'] ?? 'No se pudo actualizar la ubicación');
      }
    } else {
      throw Exception('Error en el servidor (${response.statusCode})');
    }
  }
}
