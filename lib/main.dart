import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:permission_handler/permission_handler.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/core/utils/app_routes.dart';
import 'package:rencontre/features/auth/controller/auth_controller.dart';
import 'package:rencontre/core/services/notification_service.dart';

const String _supabaseUrl  = 'https://hccdxchznkpxlfgsoufs.supabase.co';
const String _supabaseAnon = 'sb_publishable_j4U12Xsnk1nVXwG0kaRZSQ_Vhp-dUFV';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Supabase ──────────────────────────────────────────────────
  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnon,
  );

  // ── Timeago French ────────────────────────────────────────────
  timeago.setLocaleMessages('fr', timeago.FrMessages());

  // ── Permissions au démarrage ──────────────────────────────────
  await _demanderPermissions();

  // ── AuthController global ─────────────────────────────────────
  Get.put(AuthController(), permanent: true);

  await NotificationService.initialize();
  runApp(const SnapMeetApp());
}

Future<void> _demanderPermissions() async {
  // Demande toutes les permissions nécessaires en une fois
  final statuts = await [
    Permission.camera,
    Permission.microphone,
    Permission.location,
    Permission.locationWhenInUse,
    Permission.notification,
    Permission.photos,
    Permission.storage,
  ].request();

  // Log pour debug
  statuts.forEach((permission, status) {
    debugPrint('Permission $permission: $status');
  });
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