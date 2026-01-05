// main.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'theme_controller.dart';
import 'screens/tomar_noticias_page.dart';
import 'models/noticia.dart';
import 'services/api_service.dart';
import 'screens/login_screen.dart';
import 'screens/noticia_detalle_page.dart';

// ------------------ Local Notifications (Foreground) ------------------
final fln.FlutterLocalNotificationsPlugin _localNotifs =
    fln.FlutterLocalNotificationsPlugin();

const fln.AndroidNotificationChannel _newsChannel = fln.AndroidNotificationChannel(
  'tvc_noticias_high',
  'Noticias',
  description: 'Notificaciones de nuevas noticias',
  importance: fln.Importance.max,
);

// ------------------ Navigation (tap notifications) ------------------
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Map<String, dynamic>? _pendingOpenData;

// ------------------ Firebase init once ------------------
Future<void>? _firebaseInitFuture;

Future<void> initFirebaseOnce() {
  _firebaseInitFuture ??= _initFirebaseAndNotifications();
  return _firebaseInitFuture!;
}

Future<void> _initFirebaseAndNotifications() async {
  if (kIsWeb) return;

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 1) Inicializa Local Notifications
  const initSettings = fln.InitializationSettings(
    android: fln.AndroidInitializationSettings('ic_stat_notification'),
    iOS: fln.DarwinInitializationSettings(),
  );

  await _localNotifs.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (resp) async {
      // Tap en notificación local (foreground)
      final payload = resp.payload;
      if (payload == null || payload.isEmpty) return;

      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map) {
          final map = decoded.map((k, v) => MapEntry(k.toString(), v));
          await _enqueueOrOpen(map);
        }
      } catch (e) {
        debugPrint('⚠️ Payload inválido: $e');
      }
    },
  );

  // 2) Crea canal HIGH (Android 8+)
  final androidImpl = _localNotifs
      .resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(_newsChannel);

  // 3) Permisos (Android 13+ y iOS)
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  await androidImpl?.requestNotificationsPermission(); // Android 13+
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // 4) Foreground: cuando llega un push, muéstralo con notificación local
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
          visibility: fln.NotificationVisibility.public,
          icon: 'ic_stat_notification',
        ),
        iOS: const fln.DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data), // <- para abrir noticia al tocar
    );
  });

  // 5) Tap handlers para notificación push (background / terminated)
  await _setupNotificationTapHandlers();

  // (Opcional) token para debug
  final token = await FirebaseMessaging.instance.getToken();
  debugPrint('✅ FCM Token: $token');
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

}

// ------------------ Open Noticia from notification data ------------------
Future<void> _setupNotificationTapHandlers() async {
  final initial = await FirebaseMessaging.instance.getInitialMessage();
  if (initial != null) {
    _pendingOpenData = initial.data;
  }

  // App en background y tocan notificación push
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
    await _enqueueOrOpen(message.data);
  });
}

Future<void> _enqueueOrOpen(Map<String, dynamic> data) async {
  // Si el Navigator aún no existe (antes del primer frame), lo diferimos
  if (navigatorKey.currentState == null) {
    _pendingOpenData = data;
    return;
  }
  await _openNoticiaFromData(data);
}

Future<Noticia?> _buscarNoticiaPorId({
  required int noticiaId,
  required String role,
  required int reporteroId,
}) async {
  try {
    final List<Noticia> list = (role == 'admin')
        ? await ApiService.getNoticiasAdmin()
        : await ApiService.getNoticiasPorReportero(
            reporteroId: reporteroId,
            incluyeCerradas: true,
          );

    for (final n in list) {
      if (n.id == noticiaId) return n;
    }
    return null;
  } catch (e) {
    debugPrint('Error buscando noticia: $e');
    return null;
  }
}

Future<void> _openNoticiaFromData(Map<String, dynamic> data) async {
  final idStr = data['noticia_id']?.toString();
  final noticiaId = int.tryParse(idStr ?? '');
  if (noticiaId == null) return;

  final prefs = await SharedPreferences.getInstance();
  final role = prefs.getString('last_role') ?? 'reportero';
  final reporteroId = prefs.getInt('last_reportero_id') ?? 0;

  final noticia = await _buscarNoticiaPorId(
    noticiaId: noticiaId,
    role: role,
    reporteroId: reporteroId,
  );

  final tipo = data['tipo']?.toString() ?? '';

  if (role != 'admin' && tipo == 'noticia_sin_asignar') {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => TomarNoticiasPage(
          reporteroId: reporteroId,
          reporteroNombre: '',
        ),
      ),
    );
    return;
  }

  if (noticia == null) {
    final ctx = navigatorKey.currentContext;
    if (ctx != null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('No encontré la noticia #$noticiaId en tu lista.')),
      );
    }
    return;
  }

  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => NoticiaDetallePage(
        noticia: noticia,
        role: role,
      ),
    ),
  );
}

// ------------------ App entry ------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX', null);

  await initFirebaseOnce();

  // ForegroundTask (tu tracking)
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
        eventAction: ForegroundTaskEventAction.repeat(7000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  runApp(const MyApp());

  WidgetsBinding.instance.addPostFrameCallback((_) {
    final data = _pendingOpenData;
    if (data != null) {
      _pendingOpenData = null;
      unawaited(_openNoticiaFromData(data));
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
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
            return WithForegroundTask(child: child ?? const SizedBox.shrink());
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
