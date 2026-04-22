//lib/models/cliente.dart
class ClienteDomicilioOption {
  final int slot;
  final String texto;

  const ClienteDomicilioOption({
    required this.slot,
    required this.texto,
  });
}

class Cliente {
  final int id;
  final int? usuarioClienteId;
  final String? username;
  final bool activo;
  final String nombre;
  final String? apellidos;
  final String? telefono;
  final String? email;
  final String? empresa;
  final String? domicilio1;
  final String? domicilio2;
  final String? domicilio3;

  const Cliente({
    required this.id,
    required this.nombre,
    this.usuarioClienteId,
    this.username,
    this.activo = true,
    this.apellidos,
    this.telefono,
    this.email,
    this.empresa,
    this.domicilio1,
    this.domicilio2,
    this.domicilio3,
  });

  String get nombreCompleto {
    final parts = [
      nombre.trim(),
      (apellidos ?? '').trim(),
    ].where((e) => e.isNotEmpty).toList();

    return parts.isEmpty ? nombre : parts.join(' ');
  }

  List<ClienteDomicilioOption> get domiciliosDisponibles {
    final out = <ClienteDomicilioOption>[];

    void addIfPresent(int slot, String? value) {
      final text = (value ?? '').trim();
      if (text.isNotEmpty) {
        out.add(ClienteDomicilioOption(slot: slot, texto: text));
      }
    }

    addIfPresent(1, domicilio1);
    addIfPresent(2, domicilio2);
    addIfPresent(3, domicilio3);

    return out;
  }

  String? get domicilioPrincipal =>
      domiciliosDisponibles.isEmpty ? null : domiciliosDisponibles.first.texto;

  factory Cliente.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;

    int? parseNullableInt(dynamic v) {
      if (v == null || v.toString().trim().isEmpty) return null;
      return int.tryParse(v.toString());
    }

    String? parseNullableString(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    bool parseBool(dynamic v) {
      if (v == null) return false;
      final s = v.toString().trim().toLowerCase();
      return s == '1' || s == 'true';
    }

    return Cliente(
      id: parseInt(json['id']),
      usuarioClienteId: parseNullableInt(json['usuario_cliente_id'] ?? json['usuario_id']),
      username: parseNullableString(json['username']),
      activo: parseBool(json['activo']),
      nombre: (json['nombre'] ?? '').toString(),
      apellidos: parseNullableString(json['apellidos']),
      telefono: parseNullableString(json['telefono']),
      email: parseNullableString(json['email']),
      empresa: parseNullableString(json['empresa']),
      domicilio1: parseNullableString(json['domicilio_1']),
      domicilio2: parseNullableString(json['domicilio_2']),
      domicilio3: parseNullableString(json['domicilio_3']),
    );
  }
}