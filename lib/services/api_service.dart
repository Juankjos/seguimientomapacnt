//lib/services/api_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/admin_notificacion.dart';
import '../models/noticia.dart';
import '../models/reportero_admin.dart';
import '../models/aviso.dart';
import '../models/cliente.dart';

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

class ApiHttpException implements Exception {
  final int statusCode;
  final String message;
  final String? code;
  final Map<String, dynamic>? data;
  final String? raw;

  ApiHttpException({
    required this.statusCode,
    required this.message,
    this.code,
    this.data,
    this.raw,
  });

  @override
  String toString() => 'ApiHttpException($statusCode, code=$code, message=$message)';
}

class ApiService {

  static const String baseUrl = 'https://nube.tvctepa.com/CNT';
  static const String wsBaseUrl = 'ws://192.168.2.68:3001'; //'ws://45.238.188.51:2246';
  static String wsToken = '';
  static String _mysqlDateTime(DateTime dt) => DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
  static bool _toBool(dynamic x) {
    if (x == null) return false;
    if (x is bool) return x;
    if (x is num) return x.toInt() == 1;
    final s = x.toString().trim().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes' || s == 'si';
  }
  static ApiHttpException _parseApiError(http.Response resp) {
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map) {
        final msg = (decoded['message'] ?? 'Error en servidor').toString();
        final code = decoded['code']?.toString();
        final data = decoded['data'];
        return ApiHttpException(
          statusCode: resp.statusCode,
          message: msg,
          code: code,
          data: data is Map ? data.map((k, v) => MapEntry(k.toString(), v)) : null,
          raw: resp.body,
        );
      }
    } catch (_) {}

    return ApiHttpException(
      statusCode: resp.statusCode,
      message: 'Error en servidor (${resp.statusCode})',
      raw: resp.body,
    );
  }

  // 🔹 Ayuda con Headers para Login
  static Map<String, String> _authHeaders() {
    if (wsToken.trim().isEmpty) {
      throw Exception('No autorizado (ws_token vacío)');
    }
    return {'Authorization': 'Bearer $wsToken'};
  }

  // 🔹 Ayuda con tokens en peticiones
  static Map<String, String> _withToken(Map<String, String> body) {
    if (wsToken.trim().isEmpty) {
      throw Exception('No autorizado (ws_token vacío)');
    }
    return {...body, 'ws_token': wsToken};
  }

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
      if (data['success'] == true) {
        ApiService.wsToken = (data['ws_token'] ?? '').toString();
      }
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

  // 🔹 Noticias por cliente (historial en ventana de clientes)
  static Future<List<Noticia>> getNoticiasPorCliente({required int clienteId}) async {
    if (clienteId <= 0) throw Exception('clienteId inválido: $clienteId');

    final uri = Uri.parse('$baseUrl/get_noticias_por_cliente.php')
        .replace(queryParameters: {'cliente_id': clienteId.toString()});

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Error en servidor (${res.statusCode}): ${res.body}');
    }

    final data = json.decode(res.body);
    if (data is Map && data['success'] == true) {
      final list = (data['data'] as List?) ?? [];
      return list
          .whereType<Map>()
          .map((m) => Noticia.fromJson(m.map((k, v) => MapEntry(k.toString(), v))))
          .toList();
    }

    throw Exception((data is Map ? data['message'] : null) ?? 'No se pudieron cargar noticias del cliente');
  }

  // 🔹 Crear noticia (admin)
  static Future<void> crearNoticia({
    required String noticia,
    String? descripcion,
    String? domicilio,
    int? reporteroId,
    int? clienteId,
    required String tipoDeNota,
    DateTime? fechaCita,
    int limiteTiempoMinutos = 60,
  }) async {
    final url = Uri.parse('$baseUrl/crear_noticia.php');

    String? fechaCitaStr;
    if (fechaCita != null) {
      fechaCitaStr = fechaCita.toIso8601String().substring(0, 19).replaceFirst('T', ' ');
    }
    if (wsToken.trim().isEmpty) {
      throw Exception('No autorizado (ws_token vacío)');
    }

    final body = {
      'ws_token': wsToken,
      'noticia': noticia,
      'tipo_de_nota': tipoDeNota, 
      'descripcion': descripcion ?? '',
      'domicilio': domicilio ?? '',
      'reportero_id': reporteroId?.toString() ?? '',
      'cliente_id': clienteId?.toString() ?? '',
      'fecha_cita': fechaCitaStr ?? '',
      'limite_tiempo_minutos': limiteTiempoMinutos.toString(),
    };

    final response = await http.post(
      url,
      body: body,
      headers: {'Authorization': 'Bearer $wsToken'},
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      if (data['success'] != true) {
        throw Exception(data['message'] ?? 'Error al crear noticia');
      }
      return;
    } else {
      throw _parseApiError(response);
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
    bool? puedeVerGestionNoticias,
    bool? puedeVerEstadisticas,
    bool? puedeVerRastreoGeneral,
    bool? puedeVerEmpleadoMes,
    bool? puedeVerGestion,
    bool? puedeVerClientes,
    bool? puedeVerTomarNoticias,
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
    if (puedeVerGestionNoticias != null) body['puede_ver_gestion_noticias'] = puedeVerGestionNoticias ? '1' : '0';
    if (puedeVerEstadisticas != null) body['puede_ver_estadisticas'] = puedeVerEstadisticas ? '1' : '0';
    if (puedeVerRastreoGeneral != null) body['puede_ver_rastreo_general'] = puedeVerRastreoGeneral ? '1' : '0';
    if (puedeVerEmpleadoMes != null) body['puede_ver_empleado_mes'] = puedeVerEmpleadoMes ? '1' : '0';
    if (puedeVerGestion != null) body['puede_ver_gestion'] = puedeVerGestion ? '1' : '0';
    if (puedeVerClientes != null) body['puede_ver_clientes'] = puedeVerClientes ? '1' : '0';
    if (puedeVerTomarNoticias != null) body['puede_ver_tomar_noticias'] = puedeVerTomarNoticias ? '1' : '0';

    final resp = await http.post(
      url,
      body: _withToken(body),
      headers: _authHeaders(),
    );

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

    final response = await http.post(
      url,
      body: _withToken(body),
      headers: _authHeaders(),
    );

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

    final resp = await http.post(
      url,
      body: _withToken({
        'reportero_id': reporteroId.toString(),
        'noticia_id': noticiaId.toString(),
      }),
      headers: _authHeaders(),
    );

    if (resp.statusCode != 200) {
      throw _parseApiError(resp);
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is Map && decoded['success'] == true) return;

    final msg = (decoded is Map ? decoded['message'] : null) ?? 'No se pudo asignar la noticia';
    throw ApiHttpException(
      statusCode: 200,
      message: msg.toString(),
      code: decoded is Map ? decoded['code']?.toString() : null,
      data: (decoded is Map && decoded['data'] is Map)
          ? (decoded['data'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : null,
      raw: resp.body,
    );
  }

  // 🔹 Toma los permisos de crear noticias en usuarios
  static Future<Map<String, dynamic>> getPerfil() async {
    final uri = Uri.parse('$baseUrl/get_perfil.php');
    final resp = await http.post(uri, body: {'ws_token': wsToken});

    if (resp.statusCode != 200) {
      throw Exception('Error en servidor (${resp.statusCode}): ${resp.body}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) throw Exception('Respuesta inválida');
    if (decoded['success'] != true) {
      throw Exception(decoded['message']?.toString() ?? 'No autorizado');
    }

    final data = decoded['data'];
    if (data is! Map) throw Exception('Respuesta inválida');
    return data.map((k, v) => MapEntry(k.toString(), v));
  }

  // 🔹 Toma los permisos de crear noticias en usuarios (Pero en bool)
  static Future<bool> getPermisoCrearNoticias() async {
    final p = await getPerfil();
    return _toBool(p['puede_crear_noticias']);
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

    final resp = await http.post(
      url,
      body: _withToken({
        'noticia_ids': json.encode(noticiaIds),
        'nuevo_reportero_id': (nuevoReporteroId ?? '').toString(),
      }),
      headers: _authHeaders(),
    );

    if (resp.statusCode != 200) {
      throw _parseApiError(resp);
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is Map && decoded['success'] == true) return;

    final msg = (decoded is Map ? decoded['message'] : null) ?? 'No se pudo reasignar';
    throw ApiHttpException(
      statusCode: 200,
      message: msg.toString(),
      code: decoded is Map ? decoded['code']?.toString() : null,
      data: (decoded is Map && decoded['data'] is Map)
          ? (decoded['data'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : null,
      raw: resp.body,
    );
  }

  // 🔹 Buscar reportero a una noticia
  static Future<List<ReporteroBusqueda>> buscarReporteros(String query) async {
    final uri = Uri.parse('$baseUrl/search_reporteros.php').replace(
      queryParameters: {
        'q': query,
        'role': 'reportero',
      },
    );

    final response = await http.get(uri);

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

  // 🔹 Marcar si la ruta ya había sido iniciada
  static Future<Noticia> marcarRutaIniciada({
    required int noticiaId,
    required String role,
  }) async {
    final url = Uri.parse('$baseUrl/update_noticia.php');

    final response = await http.post(url,body: _withToken({
      'noticia_id': noticiaId.toString(),
      'role': role,
      'ruta_iniciada': '1',
      'ultima_mod': _mysqlDateTime(DateTime.now()),
      }),
      headers: _authHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Error en servidor (${response.statusCode})');
    }

    final data = json.decode(response.body);
    if (data['success'] == true) {
      return Noticia.fromJson(data['data']);
    }
    throw Exception(data['message'] ?? 'No se pudo marcar ruta iniciada');
  }

  // 🔹 Al llegar al destino, guardar lat y long de llegada
  static Future<void> registrarLlegadaNoticia({
    required int noticiaId,
    required double latitud,
    required double longitud,
  }) async {
    final url = Uri.parse('$baseUrl/update_llegada_noticia.php');

    if (wsToken.trim().isEmpty) {
      throw Exception('No autorizado (ws_token vacío)');
    }

    final ahora = DateTime.now();
    final horaLlegadaStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(ahora);

    final resp = await http.post(
      url,
      body: _withToken({
        'noticia_id': noticiaId.toString(),
        'latitud': latitud.toString(),
        'longitud': longitud.toString(),
        'hora_llegada': horaLlegadaStr,
      }),
      headers: _authHeaders(),
    );

    if (resp.statusCode != 200) {
      throw Exception('Error en servidor (${resp.statusCode}): ${resp.body}');
    }

    final data = json.decode(resp.body);
    if (data is Map && data['success'] == true) return;

    throw Exception((data is Map ? data['message'] : null) ?? 'Error al registrar llegada');
  }

  // 🔹 Eliminar visualmente las noticias, se conservan en DB
  static Future<void> eliminarNoticiaDePendientes(int noticiaId) async {
    final url = Uri.parse('$baseUrl/update_pendiente_noticia.php');

    final resp = await http.post(
      url,
      body: _withToken({
        'noticia_id': noticiaId.toString(),
      }),
      headers: _authHeaders(),
    );

    if (resp.statusCode == 200) {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map && decoded['success'] == true) return;

      final msg = (decoded is Map ? decoded['message'] : null) ?? 'Error al eliminar pendiente';
      throw ApiHttpException(
        statusCode: 200,
        message: msg.toString(),
        code: decoded is Map ? decoded['code']?.toString() : null,
        data: (decoded is Map && decoded['data'] is Map)
            ? (decoded['data'] as Map).map((k, v) => MapEntry(k.toString(), v))
            : null,
        raw: resp.body,
      );
    }

    throw _parseApiError(resp);
  }

  // 🔹 Revisar colision de noticia si es Entrevista
  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  static Future<Noticia?> buscarChoqueCitaEntrevista({
    required int reporteroId,
    required DateTime fechaCita,
    int? excludeNoticiaId,
  }) async {
    final list = await getNoticiasPorReportero(
      reporteroId: reporteroId,
      incluyeCerradas: false,
    );

    for (final n in list) {
      if (excludeNoticiaId != null && n.id == excludeNoticiaId) continue;

      final fc = n.fechaCita;
      if (fc == null) continue;

      if (!_sameDay(fc, fechaCita)) continue;

      final diffMin = fc.difference(fechaCita).inMinutes.abs();
      if (diffMin <= 60) {
        return n; // Rango de una hora
      }
    }
    return null;
  }

  // 🔹 Revisar colision de noticia de reasignación en la lista de reporteros
  static Noticia? _buscarChoqueEnLista({
    required List<Noticia> existentes,
    required DateTime fechaCita,
    Set<int> excludeIds = const {},
  }) {
    for (final n in existentes) {
      if (excludeIds.contains(n.id)) continue;
      final fc = n.fechaCita;
      if (fc == null) continue;
      if (!_sameDay(fc, fechaCita)) continue;

      final diffMin = fc.difference(fechaCita).inMinutes.abs();
      if (diffMin <= 60) return n;
    }
    return null;
  }

  // 🔹 Revisar colision de noticia al reasignar reportero
  static Future<Map<int, Noticia>> buscarChoquesParaReasignacion({
    required int reporteroId,
    required List<Noticia> noticiasAAsignar,
  }) async {
    final existentes = await getNoticiasPorReportero(
      reporteroId: reporteroId,
      incluyeCerradas: false,
    );

    final excludeIds = noticiasAAsignar.map((e) => e.id).toSet();
    final Map<int, Noticia> choques = {};

    for (final n in noticiasAAsignar) {
      if (n.tipoDeNota != 'Entrevista') continue;
      final fc = n.fechaCita;
      if (fc == null) continue;

      final choque = _buscarChoqueEnLista(
        existentes: existentes,
        fechaCita: fc,
        excludeIds: excludeIds,
      );

      if (choque != null) {
        choques[n.id] = choque;
      }
    }

    return choques;
  }

  // 🔹 Actualizar campos de noticia
  static Future<Noticia> actualizarNoticia({
    required int noticiaId,
    required String role,
    String? titulo,
    String? descripcion,
    DateTime? fechaCita,
    String? tipoDeNota,
    int? limiteTiempoMinutos,

    bool setCliente = false,
    int? clienteId,
    bool setDomicilio = false,
    String? domicilio,
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

    if (setCliente) body['cliente_id'] = clienteId?.toString() ?? '';
    if (setDomicilio) body['domicilio'] = (domicilio ?? '');
    if (titulo != null) body['noticia'] = titulo;
    if (descripcion != null) body['descripcion'] = descripcion;
    if (fechaCita != null) body['fecha_cita'] = fechaCitaStr!;
    if (tipoDeNota != null) body['tipo_de_nota'] = tipoDeNota;
    if (limiteTiempoMinutos != null) { body['limite_tiempo_minutos'] = limiteTiempoMinutos.toString(); }

    if (wsToken.trim().isEmpty) {
      throw Exception('No autorizado (ws_token vacío)');
    }

    final response = await http.post(
      url,
      body: {
        ...body,
        'ws_token': wsToken,
      },
      headers: {'Authorization': 'Bearer $wsToken'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) {
        return Noticia.fromJson(data['data']);
      }
      throw Exception(data['message'] ?? 'Error al actualizar noticia');
    } else { 
      throw _parseApiError(response);
    }
  }

  // 🔹 Guardar tiempo transcurrido en la nota
  static Future<Noticia> guardarTiempoEnNota({
    required int noticiaId,
    required String role,
    required int segundos,
  }) async {
    final url = Uri.parse('$baseUrl/update_noticia.php');

    if (wsToken.trim().isEmpty) {
      throw Exception('No autorizado (ws_token vacío)');
    }

    final response = await http.post(
      url,
      body: _withToken({
        'noticia_id': noticiaId.toString(),
        'role': role,
        'tiempo_en_nota': segundos.toString(),
        'ultima_mod': _mysqlDateTime(DateTime.now()),
      }),
      headers: _authHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Error en servidor (${response.statusCode}): ${response.body}');
    }
    final data = json.decode(response.body);
    if (data is Map && data['success'] == true) {
      return Noticia.fromJson(data['data']);
    }
    throw Exception((data is Map ? data['message'] : null) ?? 'No se pudo guardar tiempo_en_nota');
  }

  // 🔹 Cambiar ubicación de una noticia
  static Future<void> actualizarUbicacionNoticia({
    required int noticiaId,
    required double latitud,
    required double longitud,
    String? ubicacionEnMapa,
  }) async {
    final url = Uri.parse('$baseUrl/actualizar_ubicacion_noticia.php');

    final body = {
      'noticia_id': noticiaId.toString(),
      'latitud': latitud.toString(),
      'longitud': longitud.toString(),
      'ultima_mod': _mysqlDateTime(DateTime.now()),
    };

    if (ubicacionEnMapa != null && ubicacionEnMapa.trim().isNotEmpty) {
      body['ubicacion_en_mapa'] = ubicacionEnMapa.trim();
    }

    final response = await http.post(url, body: _withToken({
        'noticia_id': noticiaId.toString(),
        'latitud': latitud.toString(),
        'longitud': longitud.toString(),
        'ultima_mod': _mysqlDateTime(DateTime.now()),
        if (ubicacionEnMapa != null && ubicacionEnMapa.trim().isNotEmpty)
          'ubicacion_en_mapa': ubicacionEnMapa.trim(),
      }),
    headers: _authHeaders(),);

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      if (data['success'] != true) {
        throw Exception(data['message'] ?? 'No se pudo actualizar la ubicación');
      }
    } else {
      throw Exception('Error en el servidor (${response.statusCode})');
    }
  }

  // 🔹 Traer empleados destacados con noticias extras
  static Future<Map<String, dynamic>> getEmpleadoDestacado({
    required int anio,
    required int mes,
  }) async {
    final url = Uri.parse('$baseUrl/get_empleado_destacado.php?anio=$anio&mes=$mes');

    final resp = await http.get(url);

    if (resp.statusCode != 200) {
      throw Exception('Error en servidor (${resp.statusCode}): ${resp.body}');
    }

    final Map<String, dynamic> data = json.decode(resp.body);
    if (data['success'] != true) {
      throw Exception(data['message'] ?? 'Error al obtener empleado destacado');
    }

    return data;
  }

  // 🔹 Mínimo de noticias para cada mes
  static Future<void> setMinimoEmpleadoDestacado({
    required int anio,
    required int mes,
    required int minimo,
    required String role,
    int? updatedBy,
  }) async {
    final url = Uri.parse('$baseUrl/set_minimo_empleado_destacado.php');

    final body = <String, String>{
      'anio': anio.toString(),
      'mes': mes.toString(),
      'minimo': minimo.toString(),
      'role': role,
    };

    if (updatedBy != null) {
      body['updated_by'] = updatedBy.toString();
    }

    final resp = await http.post(url, body: body);

    if (resp.statusCode != 200) {
      throw Exception('Error en servidor (${resp.statusCode}): ${resp.body}');
    }

    final Map<String, dynamic> data = json.decode(resp.body);
    if (data['success'] != true) {
      throw Exception(data['message'] ?? 'No se pudo actualizar el mínimo');
    }
  }

  // 🔹 Crear Avisos (Volatil)
  static Future<void> crearAviso({
    required String titulo,
    required String descripcion,
    required DateTime vigenciaDia,
  }) async {
    final url = Uri.parse('$baseUrl/create_aviso.php');

    if (wsToken.trim().isEmpty) {
      throw Exception('No autorizado (ws_token vacío)');
    }

    final y = vigenciaDia.year.toString().padLeft(4, '0');
    final m = vigenciaDia.month.toString().padLeft(2, '0');
    final d = vigenciaDia.day.toString().padLeft(2, '0');
    final vigStr = '$y-$m-$d';

    final resp = await http.post(url, body: {
      'ws_token': wsToken,
      'titulo': titulo.trim(),
      'descripcion': descripcion.trim(),
      'vigencia': vigStr,
    });

    if (resp.statusCode != 200) {
      throw Exception('Error en servidor (${resp.statusCode}): ${resp.body}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) throw Exception('Respuesta inválida');

    if (decoded['success'] != true) {
      throw Exception(decoded['message']?.toString() ?? 'No se pudo crear aviso');
    }
  }

  // 🔹 Ver Avisos
  static Future<List<Aviso>> getAvisos() async {
    if (wsToken.trim().isEmpty) {
      throw Exception('No autorizado (ws_token vacío)');
    }

    final url = Uri.parse('$baseUrl/get_avisos.php?ws_token=${Uri.encodeQueryComponent(wsToken)}');
    final resp = await http.get(url);

    if (resp.statusCode != 200) {
      throw Exception('Error en servidor (${resp.statusCode}): ${resp.body}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) throw Exception('Respuesta inválida');

    if (decoded['success'] != true) {
      throw Exception(decoded['message']?.toString() ?? 'No se pudieron obtener avisos');
    }

    final List list = (decoded['data'] as List?) ?? [];
    return list.map((e) => Aviso.fromJson(e as Map<String, dynamic>)).toList();
  }

  // 🔹 Ver eventos en botón de notificación
  static Future<AdminNotificacionFeed> getAdminNotificaciones({
    int limit = 20,
  }) async {
    final url = Uri.parse('$baseUrl/get_admin_notificaciones.php');

    final resp = await http.post(
      url,
      body: _withToken({'limit': '$limit'}),
      headers: _authHeaders(),
    );

    if (resp.statusCode != 200) {
      throw Exception('Error en servidor (${resp.statusCode}): ${resp.body}');
    }

    final data = json.decode(resp.body);
    if (data is! Map || data['success'] != true) {
      throw Exception((data is Map ? data['message'] : null) ?? 'No se pudieron obtener notificaciones');
    }

    final unread = int.tryParse(data['unread_count'].toString()) ?? 0;
    final list = (data['data'] as List?) ?? [];

    return AdminNotificacionFeed(
      unreadCount: unread,
      items: list
          .whereType<Map>()
          .map((e) => AdminNotificacion.fromJson(
                e.map((k, v) => MapEntry(k.toString(), v)),
              ))
          .toList(),
    );
  }

  // 🔹 Marcar eventos en botón de notificación
  static Future<void> marcarAdminNotificacionLeida(int notificacionId) async {
    final url = Uri.parse('$baseUrl/mark_admin_notificacion_read.php');

    final resp = await http.post(
      url,
      body: _withToken({'notificacion_id': '$notificacionId'}),
      headers: _authHeaders(),
    );

    if (resp.statusCode != 200) {
      throw Exception('Error en servidor (${resp.statusCode}): ${resp.body}');
    }

    final data = json.decode(resp.body);
    if (data is! Map || data['success'] != true) {
      throw Exception((data is Map ? data['message'] : null) ?? 'No se pudo marcar leída');
    }
  }

  // 🔹 Buscar cliente
  static Future<List<Cliente>> getClientes({String q = ''}) async {
    final uri = Uri.parse('$baseUrl/search_clientes.php')
        .replace(queryParameters: {'q': q});

    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception('Error en servidor (${res.statusCode}): ${res.body}');
    }

    final data = json.decode(res.body);
    if (data is Map && data['success'] == true) {
      final list = (data['data'] as List?) ?? [];
      return list
          .whereType<Map>()
          .map((m) => Cliente.fromJson(m.map((k, v) => MapEntry(k.toString(), v))))
          .toList();
    }

    throw Exception((data is Map ? data['message'] : null) ?? 'No se pudieron cargar clientes');
  }

  // 🔹 Buscar detalle de cliente
  static Future<Cliente> getClienteDetalle({required int clienteId}) async {
    if (clienteId <= 0) {
      throw Exception('clienteId inválido: $clienteId');
    }
    final uri = Uri.parse('$baseUrl/get_cliente.php')
        .replace(queryParameters: {'id': clienteId.toString()});
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Error en servidor (${res.statusCode}): ${res.body}');
    }
    final data = json.decode(res.body);
    if (data is Map && data['success'] == true) {
      return Cliente.fromJson(
        (data['data'] as Map).map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    throw Exception((data is Map ? data['message'] : null) ?? 'No se pudo cargar cliente');
  }

  // 🔹 Crear cliente
  static Future<Cliente> createCliente({
    required String nombre,
    String? whatsapp,
    String? domicilio,
    String? correo,
    required String password,
  }) async {
    final url = Uri.parse('$baseUrl/create_cliente.php');

    final res = await http.post(url, body: {
      'nombre': nombre,
      'whatsapp': (whatsapp ?? '').trim(),
      'domicilio': (domicilio ?? '').trim(),
      'correo': (correo ?? '').trim(),
      'password': password,
    });

    if (res.statusCode != 200) {
      throw Exception('Error en servidor (${res.statusCode}): ${res.body}');
    }

    final data = json.decode(res.body);
    if (data is Map && data['success'] == true) {
      return Cliente.fromJson(
        (data['data'] as Map).map((k, v) => MapEntry(k.toString(), v)),
      );
    }

    throw Exception((data is Map ? data['message'] : null) ?? 'No se pudo crear cliente');
  }

  // 🔹 Actualizar cliente
  static Future<Cliente> updateCliente({
    required int id,
    required String nombre,
    String? whatsapp,
    String? domicilio,
    String? correo,
  }) async {
    final url = Uri.parse('$baseUrl/update_cliente.php');

    final res = await http.post(url, body: {
      'id': id.toString(),
      'nombre': nombre.trim(),
      'whatsapp': (whatsapp ?? '').trim(),
      'domicilio': (domicilio ?? '').trim(),
      'correo': (correo ?? '').trim(),
    });

    if (res.statusCode != 200) {
      throw Exception('Error en servidor (${res.statusCode}): ${res.body}');
    }

    final data = json.decode(res.body);
    if (data is Map && data['success'] == true) {
      return Cliente.fromJson(
        (data['data'] as Map).map((k, v) => MapEntry(k.toString(), v)),
      );
    }

    throw Exception((data is Map ? data['message'] : null) ?? 'No se pudo actualizar cliente');
  }

}
