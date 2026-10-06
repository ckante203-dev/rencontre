import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/amis/amis_controller.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/home/view/discover_feed_viewer.dart';
import 'package:rencontre/features/home/view/story_screen.dart';
import 'package:rencontre/features/home/widget/stories_row.dart';
import 'package:rencontre/shared/models/story_model.dart';

// ══════════════════════════════════════════════════════════════════
//  ONGLET « STORIES » — façon Snapchat :
//   • en haut : Ma story (+ publier) et les ronds des stories ;
//   • dessous : « À découvrir près de toi », une vignette par profil
//     (boostés, puis non vues d'abord — ordre de discoverStories) ;
//   • un appui ouvre le lecteur plein écran à partir de ce profil,
//     on enchaîne ensuite sur les suivants.
//  (Avant : l'onglet ouvrait directement le plein écran, et la barre
//  de stories était sur l'Accueil.)
// ══════════════════════════════════════════════════════════════════

class OngletStories extends StatelessWidget {
  const OngletStories({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<HomeController>()) {
      Get.put(HomeController(), permanent: true);
    }
    final ctrl = Get.find<HomeController>();
    // Façon Snapchat : en haut mes proches (amis, favoris), en dessous
    // tous les autres — sans doublon
    bool proche(String uid) =>
        ctrl.estFavori(uid) ||
        (Get.isRegistered<AmisController>() && AmisController.to.estAmi(uid));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Obx(() {
          final cartes = buildDiscoverCards(ctrl.discoverStories
              .where((s) => !proche(s.userId))
              .toList());
          return RefreshIndicator(
            onRefresh: ctrl.loadStories,
            color: AppColors.accent,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                    child: Text('Stories',
                        style: TextStyle(
                            fontFamily: 'Syne',
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                  ),
                ),
                // Ma story + ronds (non vues en rose, boostés en or)
                SliverToBoxAdapter(child: StoriesRow(filtre: proche)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                    child: Text('À découvrir près de toi',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                ),
                if (cartes.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _Vide(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 24),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 3,
                        mainAxisSpacing: 3,
                        childAspectRatio: 0.6,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _CarteStory(
                          carte: cartes[i],
                          booste: ctrl.storyBoostee(cartes[i].cover.userId),
                          onTap: () => _ouvrir(cartes, i, ctrl),
                        ),
                        childCount: cartes.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  void _ouvrir(List<DiscoverCard> cartes, int i, HomeController ctrl) {
    final premiere = cartes[i].cover;
    ctrl.preloadStoryMedia(premiere);
    // Toutes les stories, profil par profil : on enchaîne sur les suivants
    final stories = cartes.expand((c) => c.stories).toList();
    // Commence à la 1re story non vue de ce profil
    var debut = startIndexForCard(cartes, i);
    final decalage = cartes[i].stories.indexOf(premiere);
    if (decalage > 0) debut += decalage;
    ouvrirStories(stories, index: debut);
  }
}

// ─── VIGNETTE D'UN PROFIL ─────────────────────────────────────────

class _CarteStory extends StatelessWidget {
  final DiscoverCard carte;
  final bool booste;
  final VoidCallback onTap;
  const _CarteStory(
      {required this.carte, required this.booste, required this.onTap});

  static Color _couleur(String? hex) {
    final h = (hex ?? '').replaceAll('#', '');
    final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return v != null ? Color(v) : const Color(0xFF6A3093);
  }

  Widget _apercu(StoryModel s) {
    if (s.isTextStory) {
      return Container(
        color: _couleur(s.bgColor),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(10),
        child: Text(s.textContent ?? '',
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      );
    }
    // Vidéo : pas de vignette en base → photo du profil + ▶
    final url = s.isVideo ? (s.userPhotoUrl ?? '') : s.mediaUrl;
    if (url.isEmpty) return Container(color: AppColors.surface2);
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: 360,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, __) => Container(color: AppColors.surface2),
      errorWidget: (_, __, ___) => Container(color: AppColors.surface2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = carte.cover;
    final aVoir = carte.stories.any((x) => !x.isSeen);
    final distance = s.showDistance && s.distanceKm != null
        ? HomeController.formatDistance(s.distanceKm! * 1000)
        : null;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(fit: StackFit.expand, children: [
          _apercu(s),
          if (s.isVideo)
            const Center(
              child: Icon(Icons.play_circle_fill_rounded,
                  color: Colors.white70, size: 34),
            ),
          // Déjà vue : légèrement assombrie (comme Snapchat)
          if (!aVoir) Container(color: Colors.black.withValues(alpha: 0.35)),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC000000)],
                  stops: [0.55, 1.0],
                ),
              ),
            ),
          ),
          // Avatar avec anneau (rose = à voir, or = boosté)
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: aVoir
                    ? (booste
                        ? const LinearGradient(colors: [
                            Color(0xFFFFD700),
                            Color(0xFFFFA500)
                          ])
                        : AppColors.gradientPink)
                    : null,
                color: aVoir ? null : Colors.white38,
              ),
              child: CircleAvatar(
                radius: 13,
                backgroundColor: AppColors.surface2,
                backgroundImage: (s.userPhotoUrl ?? '').isNotEmpty
                    ? CachedNetworkImageProvider(s.userPhotoUrl!)
                    : null,
              ),
            ),
          ),
          if (booste)
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(Icons.bolt_rounded, color: Color(0xFFFFC233), size: 18),
            )
          else if (carte.hasMultiple)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${carte.stories.length}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          Positioned(
            left: 7,
            right: 7,
            bottom: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                if (distance != null)
                  Text(distance,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 10.5)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _Vide extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('📸', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text('Pas encore de story autour de toi',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text('Publie la tienne avec le « + » de Ma story : sois le premier !',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ]),
    );
  }
}
