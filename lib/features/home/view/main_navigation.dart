import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/home/view/home_screen.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/chat/view/chat_list_screen.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/profil/vue/ecran_profil.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
import 'package:rencontre/features/likes/likes_screen.dart';
import 'package:rencontre/features/likes/like_controller.dart';
import 'package:rencontre/features/likes/likes_insights_screen.dart';
import 'package:rencontre/features/likes/profile_insights_controller.dart';

class NavigationController extends GetxController {
  // ✅ Ordre : Accueil(0), Messages(1), Likes(2), Story(3), Profil(4)
  static const int accueilIndex = 0;
  static const int likesIndex = 2;
  static const int storyIndex = 3;

  // ✅ Onglet à ouvrir au prochain affichage de MainNavigation (clic sur
  // une notification) — sinon le reset post-frame ramenait sur Accueil.
  static int? pendingIndex;

  final RxInt currentIndex = 0.obs;
  void goTo(int index) => currentIndex.value = index;
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  late NavigationController _navCtrl;

  @override
  void initState() {
    super.initState();
    _navCtrl = Get.put(NavigationController(), permanent: true);

    if (!Get.isRegistered<ChatListController>()) {
      Get.put(ChatListController(), permanent: true);
    }
    if (!Get.isRegistered<HomeController>()) {
      Get.put(HomeController(), permanent: true);
    }
    if (!Get.isRegistered<LikeController>()) {
      Get.put(LikeController(), permanent: true);
    }
    if (!Get.isRegistered<ProfileInsightsController>()) {
      Get.put(ProfileInsightsController(), permanent: true);
    }

    if (!Get.isRegistered<ControleurProfil>()) {
      Get.put(ControleurProfil(), permanent: true);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navCtrl.currentIndex.value =
          NavigationController.pendingIndex ?? NavigationController.accueilIndex;
      NavigationController.pendingIndex = null;
      _refreshForCurrentUser();
    });
  }

  void _refreshForCurrentUser() {
    if (Get.isRegistered<HomeController>()) {
      final home = Get.find<HomeController>();
      home.loadProfiles();
      home.loadStories();
      home.loadLikedMe();
    }
  }

  // ✅ Nouvel ordre : Accueil, Messages, Likes, Story, Profil
  final List<Widget> _screens = const [
    HomeScreen(),
    ChatListScreen(),
    LikesInsightsScreen(),
    LikesScreen(),
    EcranProfil(),
  ];

  @override
  Widget build(BuildContext context) {
    return Obx(() => Scaffold(
          backgroundColor: AppColors.bg,
          body: IndexedStack(
              index: _navCtrl.currentIndex.value, children: _screens),
          bottomNavigationBar: _BarreNavigation(
            currentIndex: _navCtrl.currentIndex.value,
            onTap: (i) => _navCtrl.goTo(i),
          ),
        ));
  }
}

// ─── BARRE DE NAVIGATION (5 onglets) ─────────────────────────────

class _BarreNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _BarreNavigation({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    const contentHeight = 60.0;

    return Container(
      height: contentHeight + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: SizedBox(
        height: contentHeight,
        child: Row(children: [
          _NavItem(
            icon: Icons.grid_view_rounded,
            label: 'Accueil',
            index: 0,
            currentIndex: currentIndex,
            onTap: onTap,
          ),
          _NavItemMessages(
            index: 1,
            currentIndex: currentIndex,
            onTap: onTap,
          ),
          _NavItem(
            icon: Icons.favorite_rounded,
            label: 'Likes',
            index: 2,
            currentIndex: currentIndex,
            onTap: onTap,
          ),
          _NavItemStory(
            index: 3,
            currentIndex: currentIndex,
            onTap: onTap,
          ),
          _NavItem(
            icon: Icons.person_rounded,
            label: 'Profil',
            index: 4,
            currentIndex: currentIndex,
            onTap: onTap,
          ),
        ]),
      ),
    );
  }
}

// ─── NAV ITEM STORY (ex "Likes") ─────────────────────────────────

class _NavItemStory extends StatelessWidget {
  final int index, currentIndex;
  final ValueChanged<int> onTap;
  const _NavItemStory(
      {required this.index, required this.currentIndex, required this.onTap});

  bool get isActive => currentIndex == index;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(clipBehavior: Clip.none, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.accent.withOpacity(0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.auto_awesome_mosaic_rounded,
                  size: 22,
                  color: isActive ? AppColors.accent : AppColors.textMuted,
                ),
              ),
              Obx(() {
                if (!Get.isRegistered<HomeController>()) {
                  return const SizedBox.shrink();
                }
                final ctrl = Get.find<HomeController>();
                final count = ctrl.stories.where((s) => !s.isSeen).length;
                if (count == 0) return const SizedBox.shrink();
                return Positioned(
                  top: -2,
                  right: -6,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      gradient: AppColors.gradientPink,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: Center(
                      child: Text(
                        count > 9 ? '9+' : '$count',
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ]),
            const SizedBox(height: 2),
            Text(
              'STORY',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: isActive ? AppColors.accent : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── NAV ITEM MESSAGES ───────────────────────────────────────────

class _NavItemMessages extends StatelessWidget {
  final int index, currentIndex;
  final ValueChanged<int> onTap;
  const _NavItemMessages(
      {required this.index, required this.currentIndex, required this.onTap});

  bool get isActive => currentIndex == index;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(clipBehavior: Clip.none, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.accent.withOpacity(0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.chat_bubble_rounded,
                    size: 22,
                    color: isActive ? AppColors.accent : AppColors.textMuted),
              ),
              GetBuilder<ChatListController>(
                builder: (ctrl) {
                  final total = ctrl.conversations
                      .fold<int>(0, (sum, c) => sum + c.unreadCount);
                  if (total == 0) return const SizedBox.shrink();
                  return Positioned(
                    top: -2,
                    right: -6,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        gradient: AppColors.gradientPink,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      child: Center(
                        child: Text(
                          total > 99 ? '99+' : '$total',
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ]),
            const SizedBox(height: 2),
            Text('MESSAGES',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isActive ? AppColors.accent : AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

// ─── NAV ITEM STANDARD (Accueil, Likes, Profil) ──────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index, currentIndex;
  final ValueChanged<int> onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
  });

  bool get isActive => currentIndex == index;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.accent.withOpacity(0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  size: 22,
                  color: isActive ? AppColors.accent : AppColors.textMuted),
            ),
            const SizedBox(height: 2),
            Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isActive ? AppColors.accent : AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}
