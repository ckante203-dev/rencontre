import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/features/auth/view/splash_screen.dart';
import 'package:rencontre/features/auth/view/login_screen.dart';
import 'package:rencontre/features/auth/view/signup_screen.dart';
import 'package:rencontre/features/auth/view/phone_screen.dart';
import 'package:rencontre/features/auth/view/phone_verify_screen.dart';
import 'package:rencontre/features/auth/view/onboarding_screens.dart';
import 'package:rencontre/features/home/view/main_navigation.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/chat/view/conversation_screen.dart';
import 'package:rencontre/features/profil/vue/ecran_profil_detail.dart';
import 'package:rencontre/features/profil/vue/ecran_modifier_infos.dart';
import 'package:rencontre/features/profil/vue/ecran_parametres.dart';
import 'package:rencontre/features/profil/vue/ecran_profils_bloques.dart';
import 'package:rencontre/features/notifications/view/notifications_screen.dart';
import 'package:rencontre/features/notifications/controller/notification_controller.dart';
import 'package:rencontre/features/follow/view/followers_screen.dart';
import 'package:rencontre/features/follow/controller/follow_controller.dart';

class AppRoutes {
  static const splash = '/splash';
  static const login = '/login';
  static const signup = '/signup';
  static const loginPhone = '/login/phone';
  static const phoneVerify = '/phone/verify';
  static const onboardBirthdate = '/onboarding/birthdate';
  static const onboardPhoto = '/onboarding/photo';
  static const onboardIdentity = '/onboarding/identity';
  static const onboardInterests = '/onboarding/interests';
  static const onboardPermissions = '/onboarding/permissions';
  static const main = '/main';
  static const chatConversation = '/chat/conversation';
  static const profilDetail = '/profile/view';
  static const profilEdit = '/profile/edit';
  static const profilSettings = '/profile/settings';
  static const profilsBloques = '/profile/blocked';
  static const notifications = '/notifications'; // ✅ NOUVEAU
  static const followers = '/followers'; // ✅ NOUVEAU

  static final pages = [
    GetPage(
        name: splash,
        page: () => const SplashScreen(),
        transition: Transition.fadeIn),
    GetPage(name: login, page: () => const LoginScreen()),
    GetPage(name: signup, page: () => const SignupScreen()),
    GetPage(name: loginPhone, page: () => const PhoneScreen()),
    GetPage(
        name: phoneVerify,
        page: () => const PhoneVerifyScreen(),
        transition: Transition.rightToLeft),
    GetPage(
        name: onboardBirthdate,
        page: () => const OnboardingBirthdateScreen(),
        transition: Transition.rightToLeft),
    GetPage(
        name: onboardPhoto,
        page: () => const OnboardingPhotoScreen(),
        transition: Transition.rightToLeft),
    GetPage(
        name: onboardIdentity,
        page: () => const OnboardingIdentityScreen(),
        transition: Transition.rightToLeft),
    GetPage(
        name: onboardInterests,
        page: () => const OnboardingInterestsScreen(),
        transition: Transition.rightToLeft),
    GetPage(
        name: onboardPermissions,
        page: () => const OnboardingPermissionsScreen(),
        transition: Transition.rightToLeft),
    GetPage(
        name: main,
        page: () => const MainNavigation(),
        transition: Transition.fadeIn,
        binding: BindingsBuilder(() {
          Get.lazyPut<HomeController>(() => HomeController(), fenix: true);
        })),
    GetPage(
        name: chatConversation,
        page: () => const ConversationScreen(),
        transition: Transition.rightToLeft),
    GetPage(
        name: profilDetail,
        page: () => const EcranProfilDetail(),
        transition: Transition.fadeIn),
    GetPage(
        name: profilEdit,
        page: () => const EcranModifierInfos(),
        transition: Transition.cupertino),
    GetPage(
        name: profilSettings,
        page: () => const EcranParametres(),
        transition: Transition.cupertino),
    GetPage(
        name: profilsBloques,
        page: () => const EcranProfilsBloques(),
        transition: Transition.cupertino),
    // ✅ NOUVEAU
    GetPage(
        name: notifications,
        page: () => const NotificationsScreen(),
        transition: Transition.rightToLeft,
        binding: BindingsBuilder(() {
          Get.lazyPut<NotificationController>(() => NotificationController(),
              fenix: true);
        })),
    // ✅ NOUVEAU
    GetPage(
        name: followers,
        page: () => const FollowersScreen(),
        transition: Transition.rightToLeft,
        binding: BindingsBuilder(() {
          Get.lazyPut<FollowController>(() => FollowController(), fenix: true);
        })),
  ];
}
