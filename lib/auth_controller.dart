import 'package:flutter/foundation.dart';

@immutable
class MenuPerms {
  final bool gestionNoticias;
  final bool estadisticas;
  final bool rastreoGeneral;
  final bool empleadoMes;
  final bool gestion;
  final bool clientes;

  const MenuPerms({
    this.gestionNoticias = false,
    this.estadisticas = false,
    this.rastreoGeneral = false,
    this.empleadoMes = false,
    this.gestion = false,
    this.clientes = false,
  });

  bool get any =>
      gestionNoticias ||
      estadisticas ||
      rastreoGeneral ||
      empleadoMes ||
      gestion ||
      clientes;
}

class AuthController {
  static final ValueNotifier<bool> puedeCrearNoticias =
      ValueNotifier<bool>(false);

  static final ValueNotifier<MenuPerms> menuPerms =
      ValueNotifier<MenuPerms>(const MenuPerms());

  static void reset() {
    puedeCrearNoticias.value = false;
    menuPerms.value = const MenuPerms();
  }
}