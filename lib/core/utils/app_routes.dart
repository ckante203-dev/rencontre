import 'package:get/get.dart';
import 'package:rencontre/features/auth/view/splash_screen.dart';
import 'package:rencontre/features/auth/view/login_screen.dart';
import 'package:rencontre/features/auth/view/signup_screen.dart';
import 'package:rencontre/features/auth/view/phone_screen.dart';
import 'package:rencontre/features/auth/view/onboarding_screens.dart';
import 'package:rencontre/features/home/view/main_navigation.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/chat/view/conversation_screen.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/profil/vue/ecran_profil_detail.dart';

class AppRoutes {
  static const splash             = '/splash';
  static const login              = '/login';
  static const signup             = '/signup';
  static const loginPhone         = '/login/phone';
  static const onboardPhoto       = '/onboarding/photo';
  static const onboardInterests   = '/onboarding/interests';
  static const onboardPermissions = '/onboarding/permissions';
  static const onboardReady       = '/onboarding/ready';
  static const main               = '/main';
  static const chatConversation   = '/chat/conversation';
  static const profilDetail       = '/profile/view';

  static final pages = [
    GetPage(name: splash,      page: () => const SplashScreen(), transition: Transition.fadeIn),
    GetPage(name: login,       page: () => const LoginScreen()),
    GetPage(name: signup,      page: () => const SignupScreen()),
    GetPage(name: loginPhone,  page: () => const PhoneScreen()),
    GetPage(name: onboardPhoto,       page: () => const OnboardingPhotoScreen(),       transition: Transition.rightToLeft),
    GetPage(name: onboardInterests,   page: () => const OnboardingInterestsScreen(),   transition: Transition.rightToLeft),
    GetPage(name: onboardPermissions, page: () => const OnboardingPermissionsScreen(), transition: Transition.rightToLeft),
    GetPage(name: onboardReady,       page: () => const OnboardingReadyScreen(),       transition: Transition.rightToLeft),
    GetPage(
      name: main,
      page: () => const MainNavigation(),
      transition: Transition.fadeIn,
      binding: BindingsBuilder(() {
        Get.lazyPut<HomeController>(() => HomeController(), fenix: true);
        Get.lazyPut<ChatListController>(() => ChatListController(), fenix: true);
      }),
    ),
    GetPage(
      name: chatConversation,
      page: () => const ConversationScreen(),
      transition: Transition.rightToLeft,
      binding: BindingsBuilder(() { Get.lazyPut<ConversationController>(() => ConversationController()); }),
    ),
    GetPage(
      name: profilDetail,
      page: () => const EcranProfilDetail(),
      transition: Transition.fadeIn,
    ),
  ];
}