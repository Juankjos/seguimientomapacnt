//lib/theme_controller.dart
import 'package:flutter/material.dart';

/// Controlador global para el tema de la app.
class ThemeController {
  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.light);
}
