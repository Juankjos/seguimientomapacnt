// main.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'theme_controller.dart';

import 'models/noticia.dart';
import 'services/api_service.dart';

import 'screens/session_gate.dart';
import 'screens/tomar_noticias_page.dart';
import 'screens/noticia_detalle_page.dart';
import 'screens/avisos_page.dart';
import 'widgets/session_timeout_watcher.dart';
import 'services/session_service.dart';

// ------------------ Local Notifications ------------------
final fln.FlutterLocalNotificationsPlugin _localNotifs =
    fln.FlutterLocalNotificationsPlugin();

const fln.AndroidNotificationChannel _newsChannel = fln.AndroidNotificationChannel(
  'tvc_noticias_high',
  'Noticias',
  description: 'Notificaciones de nuevas noticias',
  importance: fln.Importance.max,
);

const fln.AndroidNotificationChannel _citasChannel = fln.AndroidNotificationChannel(
  'tvc_citas_high',
  'Citas',
  description: 'Recordatorios de citas próximas',
  importance: fln.Importance.max,
);

const fln.AndroidNotificationChannel _avisosChannel = fln.AndroidNotificationChannel(
  'tvc_avisos_high',
  'Avisos',
  description: 'Notificaciones de avisos',
  importance: fln.Importance.max,
);

// Canal para alertas del cronómetro (15 min antes)
const fln.AndroidNotificationChannel _timerChannel = fln.AndroidNotificationChannel(
  'tvc_timer_high',
  'Cronómetro',
  description: 'Alertas del cronómetro de notas',
  importance: fln.Importance.high,
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

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

// Handler recomendado por el plugin para taps en background isolate.
// Para deep-link cuando la app arranca desde cerrada, usamos getNotificationAppLaunchDetails.
@pragma('vm:entry-point')
void notificationTapBackground(fln.NotificationResponse notificationResponse) {
  // No-op
}

Future<void> _initLocalTimeZone() async {
  tzdata.initializeTimeZones();
  try {
    final info = await FlutterTimezone.getLocalTimezone(); // TimezoneInfo
    tz.setLocalLocation(tz.getLocation(info.identifier));
  } catch (_) {
    tz.setLocalLocation(tz.getLocation('UTC'));
  }
}

Future<void> _initFirebaseAndNotifications() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  if (kIsWeb) return;

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  const initSettings = fln.InitializationSettings(
    android: fln.AndroidInitializationSettings('ic_stat_notification'),
    iOS: fln.DarwinInitializationSettings(),
  );

  await _localNotifs.initialize(
    settings: initSettings,
    onDidReceiveNotificationResponse: (resp) async {
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
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  // Si la app fue lanzada desde una notificación local, aquí la capturamos
  try {
    final launchDetails = await _localNotifs.getNotificationAppLaunchDetails();
    final payload = launchDetails?.notificationResponse?.payload;
    if ((_pendingOpenData == null) && payload != null && payload.isNotEmpty) {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        _pendingOpenData =
            decoded.map((k, v) => MapEntry(k.toString(), v as dynamic));
      }
    }
  } catch (_) {}

  final androidImpl = _localNotifs
      .resolvePlatformSpecificImplementation<fln.AndroidFlutterLocalNotificationsPlugin>();

  await androidImpl?.createNotificationChannel(_newsChannel);
  await androidImpl?.createNotificationChannel(_citasChannel);
  await androidImpl?.createNotificationChannel(_avisosChannel);
  await androidImpl?.createNotificationChannel(_timerChannel);

  // Timezone para zonedSchedule
  await _initLocalTimeZone();

  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  await androidImpl?.requestNotificationsPermission();

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // Mostrar push en foreground como local notification
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    final tipo = message.data['tipo']?.toString() ?? '';

    final channel = (tipo == 'cita_proxima')
        ? _citasChannel
        : (tipo == 'aviso')
            ? _avisosChannel
            : _newsChannel;

    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        (tipo == 'aviso' ? 'Nuevo aviso' : 'Nueva notificación');

    final body = message.notification?.body ??
        message.data['body']?.toString() ??
        (tipo == 'aviso'
            ? (message.data['titulo']?.toString() ?? 'Tienes un aviso nuevo')
            : '');

    if (title.trim().isEmpty && body.trim().isEmpty) return;

    await _localNotifs.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: fln.NotificationDetails(
        android: fln.AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: fln.Importance.max,
          priority: fln.Priority.high,
          visibility: fln.NotificationVisibility.public,
          icon: 'ic_stat_notification',
        ),
        iOS: const fln.DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  });

  await _setupNotificationTapHandlers();

  final token = await FirebaseMessaging.instance.getToken();
  debugPrint('✅ FCM Token: $token');
}

// ------------------ Open from notification data ------------------
Future<void> _setupNotificationTapHandlers() async {
  final initial = await FirebaseMessaging.instance.getInitialMessage();
  if (initial != null) {
    _pendingOpenData = initial.data;
  }

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
    await _enqueueOrOpen(message.data);
  });
}

Future<void> _enqueueOrOpen(Map<String, dynamic> data) async {
  if (navigatorKey.currentState == null) {
    _pendingOpenData = data;
    return;
  }
  await _openFromData(data);
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

Future<void> _openFromData(Map<String, dynamic> data) async {
  // ✅ Siempre revisar expiración
  final expired = await SessionService.isExpired();
  if (expired) {
    await SessionService.clearSession();
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SessionGate()),
      (r) => false,
    );
    return;
  }

  final prefs = await SharedPreferences.getInstance();

  final wsToken = prefs.getString('ws_token') ?? '';
  if (wsToken.isNotEmpty) {
    ApiService.wsToken = wsToken;

    if (!kIsWeb) {
      try {
        await FlutterForegroundTask.saveData(key: 'ws_token_latest', value: wsToken);
      } catch (_) {}
    }
  }

  final role = prefs.getString('auth_role') ??
      prefs.getString('last_role') ??
      'reportero';

  final reporteroId = prefs.getInt('auth_reportero_id') ??
      prefs.getInt('last_reportero_id') ??
      0;

  final reporteroNombre = prefs.getString('auth_nombre') ?? '';

  final tipo = data['tipo']?.toString() ?? '';

  // ✅ AVISOS
  if (tipo == 'aviso') {
    final avisoId = int.tryParse(data['aviso_id']?.toString() ?? '');
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => AvisosPage(openAvisoId: avisoId)),
    );
    return;
  }

  // ✅ NOTICIAS (requiere noticia_id)
  final idStr = data['noticia_id']?.toString();
  final noticiaId = int.tryParse(idStr ?? '');
  if (noticiaId == null) return;

  if (role != 'admin' && tipo == 'noticia_sin_asignar') {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => TomarNoticiasPage(
          reporteroId: reporteroId,
          reporteroNombre: reporteroNombre,
        ),
      ),
    );
    return;
  }

  final noticia = await _buscarNoticiaPorId(
    noticiaId: noticiaId,
    role: role,
    reporteroId: reporteroId,
  );

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
      unawaited(_openFromData(data));
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
          title: 'Noticias CNT',
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
            final wrapped = SessionTimeoutWatcher(
              navigatorKey: navigatorKey,
              child: child ?? const SizedBox.shrink(),
            );
            if (kIsWeb) return wrapped;
            return WithForegroundTask(child: wrapped);
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

          home: const SessionGate(),
        );
      },
    );
  }
}
