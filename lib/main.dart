import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'screens/login_screen.dart';
import 'theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX', null);

  // Requerido para comunicación con el isolate del ForegroundTask
  if (!kIsWeb) {
    FlutterForegroundTask.initCommunicationPort();

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'tvc_tracking',
        channelName: 'Rastreo de trayecto',
        channelDescription: 'Rastreo activo durante el trayecto',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000), // 15s
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Seguimiento Mapa CNT',
          debugShowCheckedModeBanner: false,

          locale: const Locale('es', 'MX'),
          supportedLocales: const [
            Locale('es', 'MX'),
            Locale('en', ''),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],

          builder: (context, child) {
            if (kIsWeb) return child ?? const SizedBox.shrink();
            return WithForegroundTask(
              child: child ?? const SizedBox.shrink(),
            );
          },

          themeMode: mode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF3B82F6), // azul tipo “modern”
              brightness: Brightness.dark,
            ).copyWith(
              // superficies más agradables (menos negro puro)
              surface: const Color(0xFF0B1220),
              surfaceVariant: const Color(0xFF162238),

              // acentos
              primary: const Color(0xFF60A5FA),
              secondary: const Color(0xFF34D399),
              error: const Color(0xFFF87171),
            ),
            scaffoldBackgroundColor: const Color(0xFF0B1220),

            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF0B1220),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            cardTheme: CardThemeData(
              color: const Color(0xFF121B2F),
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            dividerTheme: const DividerThemeData(
              color: Colors.white12,
              thickness: 1,
            ),
          ),
          home: const LoginScreen(),
        );
      },
    );
  }
}
