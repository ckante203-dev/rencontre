import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/core/theme/theme_controller.dart';
import 'package:rencontre/core/utils/app_routes.dart';
import 'package:rencontre/features/auth/controller/auth_controller.dart';
import 'package:rencontre/core/services/notification_service.dart';
import 'package:rencontre/core/services/revenue_cat_service.dart';

// ✅ Base Supabase — zamu-prod (vybe-studio org)
const String _supabaseUrl = 'https://flixcyjefjcyjwvjdiny.supabase.co';
const String _supabaseAnon =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZsaXhjeWplZmpjeWp3dmpkaW55Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg0MTM4MDMsImV4cCI6MjEwMzk4OTgwM30.2LcUPXgP47xsWr70CdaAOuwu-PZMNl3hcwTIV8cmpz4';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // ✅ Si le push contient un bloc "notification", Android l'affiche déjà
  // lui-même en arrière-plan : en recréer une ici faisait un doublon.
  // Le clic est géré par onMessageOpenedApp / getInitialMessage.
  if (message.notification != null) return;

  await Firebase.initializeApp();
  final data = message.data;
  final type = data['type'] ?? 'message';
  final isLike = type == 'like' || type == 'match';
  await AwesomeNotifications().createNotification(
    content: NotificationContent(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      channelKey: isLike ? (type == 'match' ? 'matches' : 'likes') : 'messages',
      title: isLike
          ? (type == 'match' ? '💘 Nouveau match !' : '❤️ Nouveau like !')
          : (data['senderName'] ?? 'Nouveau message'),
      body: isLike
          ? '${data['from_user_name'] ?? 'Quelqu\'un'} t\'a liké !'
          : (data['message'] ?? ''),
      notificationLayout:
          isLike ? NotificationLayout.Default : NotificationLayout.Messaging,
      wakeUpScreen: true,
      payload: isLike
          ? {
              'type': type,
              'fromUserId': data['from_user_id'] ?? '',
              'userName': data['from_user_name'] ?? '',
            }
          : {
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
    GetStorage.init(),
  ]);

  timeago.setLocaleMessages('fr', timeago.FrMessages());

  // ✅ Crashlytics : toute erreur non gérée (Flutter ou asynchrone) est
  // envoyée à la console Firebase, avec la pile d'appels. Rien n'est
  // envoyé en mode debug (les erreurs restent dans la console du PC).
  await FirebaseCrashlytics.instance
      .setCrashlyticsCollectionEnabled(!kDebugMode);
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (erreur, pile) {
    FirebaseCrashlytics.instance.recordError(erreur, pile, fatal: true);
    return true;
  };

  // ✅ Thème : chargé AVANT runApp pour éviter le flash de thème par défaut.
  final themeCtrl = Get.put(ThemeController(), permanent: true);
  themeCtrl.loadInitial();

  String startRoute = AppRoutes.login;

  final user = Supabase.instance.client.auth.currentUser;
  if (user != null) {
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('onboarding_complete, birthdate, theme')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (row != null && row['theme'] != null) {
        themeCtrl.applyRemote(row['theme'] as String);
      }

      if (row != null && row['onboarding_complete'] == true) {
        startRoute = AppRoutes.main;
        GetStorage().write('onboarding_done_${user.id}', true);
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
      // ✅ Hors ligne / réseau lent : un utilisateur déjà inscrit ne doit
      // pas être renvoyé à l'onboarding.
      final done =
          GetStorage().read<bool>('onboarding_done_${user.id}') ?? false;
      startRoute = done ? AppRoutes.main : AppRoutes.onboardPhoto;
    }
  }

  Get.put(AuthController(), permanent: true);

  // Rapports de plantage rattachés au compte (identifiant seulement, pour
  // retrouver un problème signalé par un utilisateur précis).
  if (user != null) {
    FirebaseCrashlytics.instance.setUserIdentifier(user.id);
  }

  runApp(ZamuApp(initialRoute: startRoute));

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
    final rc = await Get.putAsync(() => RevenueCatService().init());
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid != null) {
      await rc.loginRevenueCat(uid);
    }
  } catch (e) {
    debugPrint('RevenueCatService error: $e');
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

  // ✅ App ouverte : affichage selon le type (message / like / match)
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    NotificationService.showFromPush(message.data,
        message.notification?.title, message.notification?.body);
  });

  // ✅ Clic sur la notification système : même navigation que les
  // notifications locales (l'écran conversation attend un
  // ConversationModel, pas une Map — c'était la cause du crash).
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    NotificationService.handlePushTap(message.data);
  });

  messaging.getInitialMessage().then((initialMessage) {
    if (initialMessage != null) {
      Future.delayed(const Duration(seconds: 1), () {
        NotificationService.handlePushTap(initialMessage.data);
      });
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
      // iOS : position « pendant l'utilisation » uniquement, pas de
      // stockage (n'existe pas) — cf. macros du Podfile.
      if (!Platform.isIOS) Permission.location,
      Permission.locationWhenInUse,
      Permission.notification,
      Permission.photos,
      if (!Platform.isIOS) Permission.storage,
    ].request();
  } catch (e) {
    debugPrint('Permissions error: $e');
  }
}

// Remplacez la classe ZamuApp dans main.dart par celle-ci :

class ZamuApp extends StatelessWidget {
  final String initialRoute;
  const ZamuApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final palette = ThemeController.to.palette.value;
      return GetMaterialApp(
        title: 'Zamu',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.buildFrom(palette),
        themeMode: ThemeMode.dark,
        initialRoute: initialRoute,
        getPages: AppRoutes.pages,
        defaultTransition: Transition.cupertino,
        transitionDuration: const Duration(milliseconds: 280),
      );
    });
  }
}
