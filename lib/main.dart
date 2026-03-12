import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/core/utils/app_routes.dart';
import 'package:rencontre/features/auth/controller/auth_controller.dart';
import 'package:rencontre/core/services/notification_service.dart';

const String _supabaseUrl = 'https://hccdxchznkpxlfgsoufs.supabase.co';
const String _supabaseAnon = 'sb_publishable_j4U12Xsnk1nVXwG0kaRZSQ_Vhp-dUFV';

// ── Handler notifications en arrière-plan (OBLIGATOIRE top-level) ──
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Affiche la notification via awesome_notifications
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

  // ── Supabase ──────────────────────────────────────────────────
  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnon,
  );

  // ── Firebase ──────────────────────────────────────────────────
  await Firebase.initializeApp();

  // ── Notifications locales (awesome_notifications) ─────────────
  await NotificationService.initialize();
  NotificationService.listenToNotifications();

  // ── Firebase Messaging ────────────────────────────────────────
  await _setupFirebaseMessaging();

  // ── Timeago French ────────────────────────────────────────────
  timeago.setLocaleMessages('fr', timeago.FrMessages());

  // ── Permissions au démarrage ──────────────────────────────────
  await _demanderPermissions();

  // ── AuthController global ─────────────────────────────────────
  Get.put(AuthController(), permanent: true);

  runApp(const SnapMeetApp());
}

Future<void> _setupFirebaseMessaging() async {
  // Handler quand app est complètement fermée
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  final messaging = FirebaseMessaging.instance;

  // Demande permission iOS (Android 13+ géré par awesome_notifications)
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // Récupère le token FCM et le sauvegarde dans Supabase
  final token = await messaging.getToken();
  if (token != null) {
    await _saveFcmToken(token);
  }

  // Si le token change (ex: réinstallation)
  messaging.onTokenRefresh.listen(_saveFcmToken);

  // Notification reçue quand app est EN PREMIER PLAN
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

  // Notification cliquée quand app est en ARRIÈRE-PLAN (pas fermée)
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

  // App ouverte DEPUIS une notification (app était fermée)
  final initialMessage = await messaging.getInitialMessage();
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
  await [
    Permission.camera,
    Permission.microphone,
    Permission.location,
    Permission.locationWhenInUse,
    Permission.notification,
    Permission.photos,
    Permission.storage,
  ].request();
}

class SnapMeetApp extends StatelessWidget {
  const SnapMeetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'SnapMeet',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      initialRoute: AppRoutes.splash,
      getPages: AppRoutes.pages,
      defaultTransition: Transition.cupertino,
      transitionDuration: const Duration(milliseconds: 280),
    );
  }
}
