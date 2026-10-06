import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/home/view/story_screen.dart';
import 'package:rencontre/shared/models/story_model.dart';

// ═══════════════════════════════════════════════════════════════
// La construction de la chaîne complète de stories (tous les
// profils, dans l'ordre) vit dans HomeController.buildStoryChain().
// ═══════════════════════════════════════════════════════════════

class StoriesRow extends GetView<HomeController> {
  /// Si fourni : seuls ces profils ont un rond (ex. amis et favoris)
  final bool Function(String userId)? filtre;
  const StoriesRow({super.key, this.filtre});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final stories = filtre == null
          ? controller.stories
          : controller.stories.where((s) => filtre!(s.userId)).toList();
      final myStory = controller.myActiveStory;
      final hasMyStory = myStory != null;

      return SizedBox(
        height: 86,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 1 + stories.length,
          itemBuilder: (_, i) {
            if (i == 0) {
              return _MyStoryItem(
                hasStory: hasMyStory,
                myStory: myStory,
                myPhotoUrl: controller.myProfile?.photoUrl,
              );
            }
            return _StoryItem(story: stories[i - 1]);
          },
        ),
      );
    });
  }
}

class _MyStoryItem extends StatelessWidget {
  final bool hasStory;
  final StoryModel? myStory;
  final String? myPhotoUrl;

  const _MyStoryItem({
    required this.hasStory,
    required this.myStory,
    required this.myPhotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      // ✅ CORRIGÉ — l'OverflowBox précédent posait deux problèmes
      // dans un ListView horizontal :
      //  1. largeur non bornée → l'OverflowBox prenait une largeur
      //     infinie et l'élément ne s'affichait plus ;
      //  2. minHeight hérité de la liste (96) > maxHeight (90) →
      //     contraintes invalides.
      // Ici : largeur fixée par un SizedBox, et minHeight: 0. Le
      // contenu garde sa hauteur naturelle (~85px) même quand la
      // barre est en cours d'animation, sans erreur d'overflow.
      child: SizedBox(
        width: 54,
        child: OverflowBox(
          minHeight: 0,
          maxHeight: 80,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 54,
                height: 54,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GestureDetector(
                      onTap: _onMainTap,
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                hasStory ? AppColors.accent : AppColors.border,
                            width: hasStory ? 2.5 : 2,
                          ),
                        ),
                        child: ClipOval(
                          child: myPhotoUrl != null && myPhotoUrl!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: myPhotoUrl!, fit: BoxFit.cover)
                              : Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        AppColors.accent,
                                        AppColors.accent2
                                      ],
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.person_rounded,
                                        color: Colors.white, size: 24),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: GestureDetector(
                        onTap: _onPlusTap,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            gradient: AppColors.gradientPink,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.bg, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                  color: AppColors.accent.withOpacity(0.5),
                                  blurRadius: 8)
                            ],
                          ),
                          child: const Icon(Icons.add_rounded,
                              color: Colors.white, size: 17),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Text(
                hasStory ? 'Ma story' : 'Ajouter',
                style: TextStyle(
                  color: hasStory ? AppColors.textPrimary : AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: hasStory ? FontWeight.w700 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onMainTap() {
    if (hasStory && myStory != null) {
      final ctrl = Get.find<HomeController>();
      final chain = ctrl.buildStoryChain(myStory!.userId);
      ouvrirStories(chain.stories, index: chain.startIndex);
    } else {
      _openAddStory();
    }
  }

  void _onPlusTap() => _openAddStory();

  Future<void> _openAddStory() async {
    final result = await Get.to(
      () => const AddStoryScreen(),
      transition: Transition.cupertino,
    );
    if (result == true) {
      Get.find<HomeController>().loadStories();
    }
  }
}

class _StoryItem extends StatelessWidget {
  final StoryModel story;
  const _StoryItem({required this.story});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<HomeController>();
    final allSeen = ctrl.userStoryIsSeen(story.userId);
    // ⚡ Profil boosté : cercle or → orange et petit éclair
    final booste = ctrl.storyBoostee(story.userId);

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        // Précharge dès que le doigt touche le cercle (~100-300 ms gagnées)
        onTapDown: (_) {
          final ctrl = Get.find<HomeController>();
          final premiere = ctrl.storiesForUser(story.userId).firstOrNull;
          if (premiere != null) ctrl.preloadStoryMedia(premiere);
        },
        onTap: _openStory,
        // ✅ CORRIGÉ — même correction que _MyStoryItem :
        // largeur bornée + minHeight: 0.
        child: SizedBox(
          width: 54,
          child: OverflowBox(
            minHeight: 0,
            maxHeight: 80,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(clipBehavior: Clip.none, children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: allSeen
                          ? null
                          : (booste
                              ? const LinearGradient(colors: [
                                  Color(0xFFFFD700),
                                  Color(0xFFFFA500)
                                ])
                              : AppColors.anneauStory),
                      color: allSeen ? AppColors.border : null,
                    ),
                    padding: const EdgeInsets.all(2.5),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.bg, width: 2),
                      ),
                      child: ClipOval(
                        child: story.userPhotoUrl != null &&
                                story.userPhotoUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: story.userPhotoUrl!,
                                fit: BoxFit.cover)
                            : Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [
                                    AppColors.accent,
                                    AppColors.accent2
                                  ]),
                                ),
                                child: Center(
                                  child: Text(
                                    story.userName.isNotEmpty
                                        ? story.userName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 18),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  if (booste)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFFFA500),
                          border: Border.all(color: AppColors.bg, width: 2),
                        ),
                        child: const Icon(Icons.bolt_rounded,
                            size: 12, color: Colors.white),
                      ),
                    ),
                ]),
                const SizedBox(height: 5),
                SizedBox(
                  width: 54,
                  child: Text(
                    story.userName,
                    style: TextStyle(
                      color:
                          allSeen ? AppColors.textMuted : AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: allSeen ? FontWeight.w400 : FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openStory() {
    final ctrl = Get.find<HomeController>();

    final chain = ctrl.buildStoryChain(story.userId);
    if (chain.stories.isEmpty) return;

    ouvrirStories(chain.stories, index: chain.startIndex);
    // ✅ Le marquage "vue" est désormais fait par StoryViewerScreen pour
    // CHAQUE story réellement affichée (et plus seulement la première
    // du profil), ce qui rend userStoryIsSeen cohérent.
  }
}
