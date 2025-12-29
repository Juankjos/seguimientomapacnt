// main.dart
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;


import 'screens/login_screen.dart';
import 'theme_controller.dart';
import 'firebase_options.dart';

// --- Local Notifications (para mostrar en FOREGROUND) ---
final fln.FlutterLocalNotificationsPlugin _localNotifs =
    fln.FlutterLocalNotificationsPlugin();

const fln.AndroidNotificationChannel _newsChannel = fln.AndroidNotificationChannel(
  'tvc_noticias_high',
  'Noticias',
  description: 'Notificaciones de nuevas noticias',
  importance: fln.Importance.max,
);

Future<void>? _firebaseInitFuture;

Future<void> initFirebaseOnce() {
  _firebaseInitFuture ??= _initFirebaseAndNotifications();
  return _firebaseInitFuture!;
}

Future<void> _initFirebaseAndNotifications() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 1) Inicializa plugin local notifications
  const initSettings = fln.InitializationSettings(
    android: fln.AndroidInitializationSettings('@mipmap/ic_launcher'),
  );
  await _localNotifs.initialize(initSettings);


  // 2) Crea canal HIGH (Android 8+)
  final androidImpl = _localNotifs
    .resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(_newsChannel);

  // 3) Permisos (Android 13+ y iOS)
  await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
  await androidImpl?.requestNotificationsPermission(); // Android 13+
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // 4) FOREGROUND: cuando llega un push, muéstralo con notificación local
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    final notif = message.notification;
    if (notif == null) return;

    await _localNotifs.show(
      notif.hashCode,
      notif.title ?? 'Nueva notificación',
      notif.body ?? '',
      fln.NotificationDetails(
        android: fln.AndroidNotificationDetails(
          _newsChannel.id,
          _newsChannel.name,
          channelDescription: _newsChannel.description,
          importance: fln.Importance.max,
          priority: fln.Priority.high,
          visibility: fln.NotificationVisibility.public, // ✅ ya no choca
          icon: message.notification?.android?.smallIcon ?? '@mipmap/ic_launcher',
        ),
      ),
      payload: jsonEncode(message.data),
    );

  });

  // (Opcional) token para debug
  final token = await FirebaseMessaging.instance.getToken();
  debugPrint('✅ FCM Token: $token');
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Corre en background isolate
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  // OJO: aquí normalmente NO necesitas mostrar local notification
  // si tu servidor manda "notification": Android la muestra solo en background/bloqueado.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX', null);

  await initFirebaseOnce();

  // Tu ForegroundTask (igual que lo tienes)
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
        eventAction: ForegroundTaskEventAction.repeat(15000),
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
          supportedLocales: const [Locale('es', 'MX'), Locale('en', '')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            if (kIsWeb) return child ?? const SizedBox.shrink();
            return WithForegroundTask(child: child ?? const SizedBox.shrink());
          },
          themeMode: mode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.light),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF3B82F6),
              brightness: Brightness.dark,
            ),
          ),
          home: const LoginScreen(),
        );
      },
    );
  }
}
