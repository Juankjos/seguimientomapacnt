//lib/services/api_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/noticia.dart';

class ApiService {
  // 📌 Para el emulador Android, usa 10.0.2.2 en lugar de localhost
  static const String baseUrl = 'http://localhost/seguimientomapacnt';

  // Para dispositivo físico en la misma red, usa la IP de tu PC:
  // static const String baseUrl = 'http://TU_IP_LOCAL/seguimientomapacnt_api';

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

    // 🔹 Noticias disponibles (sin reportero asignado)
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

  // 🔹 Tomar noticia: asignar reportero a una noticia
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
