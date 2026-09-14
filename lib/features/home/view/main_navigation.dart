import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/home/view/home_screen.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/chat/view/chat_list_screen.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/profil/vue/ecran_profil.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
import 'package:rencontre/features/annonces/view/annonces_screen.dart';
import 'package:rencontre/features/annonces/controller/annonces_controller.dart';
import 'package:rencontre/features/likes/likes_screen.dart';
import 'package:rencontre/features/likes/like_controller.dart';
import 'package:rencontre/features/follow/controller/follow_controller.dart';

class NavigationController extends GetxController {
  // ✅ Index fixes correspondant au nouvel ordre visuel de la barre :
  // Messages(0), Story(1), Découvrir/Accueil(2, centre), Annonces(3), Profil(4)
  static const int accueilIndex = 2;
  static const int annoncesIndex = 3;

  final RxInt currentIndex = 0.obs;
  void goTo(int index) => currentIndex.value = index;
  void goToAnnonces() => currentIndex.value = annoncesIndex;
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
    if (!Get.isRegistered<AnnoncesController>()) {
      Get.put(AnnoncesController(), permanent: true);
    }
    if (!Get.isRegistered<HomeController>()) {
      Get.put(HomeController(), permanent: true);
    }
    if (!Get.isRegistered<LikeController>()) {
      Get.put(LikeController(), permanent: true);
    }
    if (!Get.isRegistered<FollowController>()) {
      Get.put(FollowController(), permanent: true);
    }

    Get.lazyPut<ControleurProfil>(() => ControleurProfil(), fenix: true);

    // ✅ FIX : on diffère à la frame suivante à la fois le reset de l'index
    // ET le rafraîchissement des données (_refreshForCurrentUser). Ce dernier
    // modifie plusieurs valeurs .obs (dont AnnoncesController.loadAnnonces)
    // de façon synchrone — appelé ici pendant initState(), ces écritures
    // avaient lieu AVANT la fin du tout premier build() de cet écran, ce qui
    // provoquait "setState() or markNeedsBuild() called during build" sur
    // les Obx qui dépendent de ces contrôleurs (ex: AnnoncesController).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Toujours démarrer sur Découvrir (désormais au centre de la barre)
      _navCtrl.currentIndex.value = NavigationController.accueilIndex;
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
    if (Get.isRegistered<AnnoncesController>()) {
      Get.find<AnnoncesController>().loadAnnonces();
    }

    if (Get.isRegistered<FollowController>()) {
      Get.find<FollowController>().loadFollowData();
    }
  }

  // ✅ Nouvel ordre : Messages, Story, Découvrir (centre), Annonces, Profil
  final List<Widget> _screens = const [
    ChatListScreen(),
    LikesScreen(),
    HomeScreen(),
    AnnoncesScreen(),
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

// ─── BARRE DE NAVIGATION ─────────────────────────────────────────

class _BarreNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _BarreNavigation({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // ✅ FIX overflow : on calcule nous-mêmes l'espace de sécurité en bas
    // (barre de gestion Android) et on l'AJOUTE à la hauteur totale, au
    // lieu de laisser SafeArea le retirer de l'intérieur d'une hauteur
    // fixe de 60px — c'est ce qui causait le débordement
    // "OVERFLOWED BOTTOM BY 38 PIXELS".
    final bottomInset = MediaQuery.of(context).padding.bottom;
    const contentHeight = 60.0;
    final totalHeight = contentHeight +
        bottomInset +
        16; // +16 pour le bouton central qui dépasse

    return SizedBox(
      height: totalHeight,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // ── Barre de fond avec les 4 icônes normales ──────────
          Container(
            height: contentHeight + bottomInset,
            padding: EdgeInsets.only(bottom: bottomInset),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border:
                  Border(top: BorderSide(color: AppColors.border, width: 1)),
            ),
            child: SizedBox(
              height: contentHeight,
              child: Row(children: [
                _NavItemMessages(
                  index: 0,
                  currentIndex: currentIndex,
                  onTap: onTap,
                ),
                _NavItemStory(
                  index: 1,
                  currentIndex: currentIndex,
                  onTap: onTap,
                ),
                // Espace réservé au bouton Découvrir surélevé
                const SizedBox(width: 64),
                _NavItemAnnonces(
                  index: NavigationController.annoncesIndex,
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
          ),
          // ── Bouton Découvrir central, surélevé façon Snapchat ─
          Positioned(
            top: 0,
            child: _DecouvrirCentralBtn(
              isActive: currentIndex == NavigationController.accueilIndex,
              onTap: () => onTap(NavigationController.accueilIndex),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── BOUTON DÉCOUVRIR CENTRAL (surélevé, façon caméra Snapchat) ──

class _DecouvrirCentralBtn extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  const _DecouvrirCentralBtn({required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.gradientPink,
          border: Border.all(color: AppColors.surface, width: 4),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withOpacity(isActive ? 0.55 : 0.35),
              blurRadius: isActive ? 20 : 12,
              spreadRadius: isActive ? 2 : 0,
            ),
          ],
        ),
        child: Icon(
          Icons.grid_view_rounded,
          color: Colors.white,
          size: isActive ? 30 : 26,
        ),
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

// ─── NAV ITEM ANNONCES ───────────────────────────────────────────

class _NavItemAnnonces extends StatelessWidget {
  final int index, currentIndex;
  final ValueChanged<int> onTap;
  const _NavItemAnnonces(
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
                child: Icon(Icons.campaign_rounded,
                    size: 22,
                    color: isActive ? AppColors.accent : AppColors.textMuted),
              ),
              Obx(() {
                if (!Get.isRegistered<AnnoncesController>()) {
                  return const SizedBox.shrink();
                }
                final unseen = Get.find<AnnoncesController>().unseenCount.value;
                if (unseen == 0) return const SizedBox.shrink();
                return Positioned(
                  top: -2,
                  right: -6,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black, width: 1),
                    ),
                    child: Center(
                      child: Text(
                        unseen > 9 ? '9+' : '$unseen',
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ]),
            const SizedBox(height: 2),
            Text('ANNONCES',
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

// ─── NAV ITEM STANDARD ───────────────────────────────────────────

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
