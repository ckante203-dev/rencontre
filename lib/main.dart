import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/core/utils/app_routes.dart';
import 'package:rencontre/features/auth/controller/auth_controller.dart';
import 'package:rencontre/core/services/notification_service.dart';

const String _supabaseUrl = 'https://hccdxchznkpxlfgsoufs.supabase.co';
const String _supabaseAnon = 'sb_publishable_j4U12Xsnk1nVXwG0kaRZSQ_Vhp-dUFV';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final data = message.data;
  final notification = message.notification;
  await AwesomeNotifications().createNotification(
    content: NotificationContent(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      channelKey: 'messages',
      title: notification?.title ?? data['senderName'] ?? 'Nouveau message',
      body: notification?.body ?? data['message'] ?? '',
      notificationLayout: NotificationLayout.Messaging,
      wakeUpScreen: true,
      payload: {
        'type': 'message',
        'conversationId': data['conversationId'] ?? '',
        'senderName': data['senderName'] ?? '',
      },
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await Future.wait([
    Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnon),
    Firebase.initializeApp(),
  ]);

  timeago.setLocaleMessages('fr', timeago.FrMessages());

  // ✅ String (pas final) avec valeur par défaut
  String startRoute = AppRoutes.login;

  final user = Supabase.instance.client.auth.currentUser;
  if (user != null) {
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('onboarding_complete, birthdate')
          .eq('id', user.id)
          .maybeSingle();

      if (row != null && row['onboarding_complete'] == true) {
        startRoute = AppRoutes.main;
      } else {
        final hasBirthdate = row != null &&
            row['birthdate'] != null &&
            (row['birthdate'] as String).isNotEmpty;
        final identities = user.identities ?? [];
        final isGoogle = identities.any((i) => i.provider == 'google');
        if (isGoogle && !hasBirthdate) {
          startRoute = AppRoutes.onboardBirthdate;
        } else {
          startRoute = AppRoutes.onboardPhoto;
        }
      }
    } catch (_) {
      startRoute = AppRoutes.onboardPhoto;
    }
  }

  Get.put(AuthController(), permanent: true);

  runApp(SnapMeetApp(initialRoute: startRoute));

  _initEnArrierePlan();
}

Future<void> _initEnArrierePlan() async {
  try {
    await NotificationService.initialize();
    NotificationService.listenToNotifications();
  } catch (e) {
    debugPrint('NotificationService error: $e');
  }

  try {
    await _setupFirebaseMessaging();
  } catch (e) {
    debugPrint('Firebase Messaging error: $e');
  }

  try {
    await _saveAppVersion();
  } catch (e) {
    debugPrint('AppVersion error: $e');
  }

  try {
    _demanderPermissions();
  } catch (e) {
    debugPrint('Permissions error: $e');
  }
}

Future<void> _saveAppVersion() async {
  try {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final packageInfo = await PackageInfo.fromPlatform();
    final version = packageInfo.version;
    await Supabase.instance.client
        .from('profiles')
        .update({'app_version': version}).eq('id', uid);
    debugPrint('✅ App version sauvegardée: $version');
  } catch (e) {
    debugPrint('saveAppVersion error: $e');
  }
}

Future<void> _setupFirebaseMessaging() async {
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  final messaging = FirebaseMessaging.instance;

  messaging.requestPermission(alert: true, badge: true, sound: true);

  messaging.getToken().then((token) {
    if (token != null) _saveFcmToken(token);
  });

  messaging.onTokenRefresh.listen(_saveFcmToken);

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final data = message.data;
    final convId = data['conversationId'] ?? '';
    final senderName = data['senderName'] ?? 'Quelqu\'un';
    final msg = data['message'] ?? message.notification?.body ?? '';
    NotificationService.showMessageNotification(
      senderName: senderName,
      message: msg,
      conversationId: convId,
    );
  });

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    final convId = message.data['conversationId'];
    final senderName = message.data['senderName'] ?? '';
    if (convId != null && convId.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 500), () {
        Get.toNamed('/chat/conversation',
            arguments: {'id': convId, 'userName': senderName});
      });
    }
  });

  messaging.getInitialMessage().then((initialMessage) {
    if (initialMessage != null) {
      final convId = initialMessage.data['conversationId'];
      final senderName = initialMessage.data['senderName'] ?? '';
      if (convId != null && convId.isNotEmpty) {
        Future.delayed(const Duration(seconds: 1), () {
          Get.toNamed('/chat/conversation',
              arguments: {'id': convId, 'userName': senderName});
        });
      }
    }
  });
}

Future<void> _saveFcmToken(String token) async {
  try {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    await Supabase.instance.client
        .from('profiles')
        .update({'fcm_token': token}).eq('id', uid);
    debugPrint('✅ FCM Token sauvegardé: ${token.substring(0, 20)}...');
  } catch (e) {
    debugPrint('FCM token save error: $e');
  }
}

Future<void> _demanderPermissions() async {
  try {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.location,
      Permission.locationWhenInUse,
      Permission.notification,
      Permission.photos,
      Permission.storage,
    ].request();
  } catch (e) {
    debugPrint('Permissions error: $e');
  }
}

class SnapMeetApp extends StatelessWidget {
  final String initialRoute;
  const SnapMeetApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'SnapMeet',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      initialRoute: initialRoute,
      getPages: AppRoutes.pages,
      defaultTransition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 280),
    );
  }
}
