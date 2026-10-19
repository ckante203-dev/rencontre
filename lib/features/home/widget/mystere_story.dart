import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/features/likes/like_controller.dart';
import 'package:rencontre/shared/models/story_model.dart';
import 'package:rencontre/shared/models/user_model.dart';

// ─── 🔒 STORY MYSTÈRE (SQL 091) ───────────────────────────────────
// Floutée pour ceux qui n'ont pas encore liké l'auteur : « Like pour la
// découvrir ». L'auteur, et ceux qui l'ont liké ou ont matché avec lui,
// la voient nette. Liker la débloque aussitôt (et fait un match si c'est
// réciproque).
// Les anciennes versions de l'app ignorent l'option (story nette).

/// Vrai si cette story est floutée pour moi.
bool storyVerrouillee(StoryModel s) {
  if (!s.mystere) return false;
  final moi = Supabase.instance.client.auth.currentUser?.id;
  if (moi == null) return true;
  if (moi == s.userId) return false;
  if (!Get.isRegistered<LikeController>()) return true;
  final likes = Get.find<LikeController>();
  return !(likes.hasLiked(s.userId) || likes.hasMatch(s.userId));
}

/// Floute [child] tant que la story est verrouillée pour moi.
/// [compact] : vignette (grille, ronds) → juste un cadenas.
class VoileMystere extends StatelessWidget {
  final StoryModel story;
  final Widget child;
  final bool compact;
  const VoileMystere(
      {super.key, required this.story, required this.child, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (!story.mystere) return child;
    if (!Get.isRegistered<LikeController>()) return _voile();
    final likes = Get.find<LikeController>();
    return Obx(() {
      // Lecture des listes réactives pour se mettre à jour au like
      likes.likedUserIds.length;
      likes.matchedUserIds.length;
      return storyVerrouillee(story) ? _voile() : child;
    });
  }

  Widget _voile() {
    return Stack(fit: StackFit.expand, children: [
      ClipRect(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
              sigmaX: compact ? 12 : 30, sigmaY: compact ? 12 : 30),
          child: child,
        ),
      ),
      Container(color: Colors.black.withValues(alpha: compact ? 0.15 : 0.3)),
      if (compact)
        const Center(
            child: Text('🔒',
                style: TextStyle(fontSize: 26, shadows: [Shadow(blurRadius: 8)])))
      else
        Center(child: _CarteDeverrouiller(story: story)),
    ]);
  }
}

class _CarteDeverrouiller extends StatefulWidget {
  final StoryModel story;
  const _CarteDeverrouiller({required this.story});

  @override
  State<_CarteDeverrouiller> createState() => _CarteDeverrouillerState();
}

class _CarteDeverrouillerState extends State<_CarteDeverrouiller> {
  bool _occupe = false;

  Future<void> _liker() async {
    if (_occupe || !Get.isRegistered<LikeController>()) return;
    final likes = Get.find<LikeController>();
    final s = widget.story;
    if (likes.hasLiked(s.userId)) return; // déjà liké : rien à défaire
    setState(() => _occupe = true);
    HapticFeedback.mediumImpact();
    await likes.toggleLike(UserModel(
      id: s.userId,
      name: s.userName,
      age: 0,
      photoUrl: s.userPhotoUrl,
    ));
    if (mounted) setState(() => _occupe = false);
  }

  @override
  Widget build(BuildContext context) {
    final prenom = widget.story.userName.split(' ').first;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(
        color: const Color(0xE6141418),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🔒', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 6),
        Text('Story mystère'.tr,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text('Like @prenom pour la découvrir 👀'.trParams({'prenom': prenom}),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _liker,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFFF3CAC), Color(0xFF7B2FFF)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: _occupe
                ? const Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white)))
                : Text('❤️ ${'Liker'.tr}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
          ),
        ),
      ]),
    );
  }
}

/// Cache [child] (stickers, légende) tant que la story est verrouillée.
class MasqueSiMystere extends StatelessWidget {
  final StoryModel story;
  final Widget child;
  const MasqueSiMystere({super.key, required this.story, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!story.mystere) return child;
    if (!Get.isRegistered<LikeController>()) return const SizedBox.shrink();
    final likes = Get.find<LikeController>();
    return Obx(() {
      likes.likedUserIds.length;
      likes.matchedUserIds.length;
      return storyVerrouillee(story) ? const SizedBox.shrink() : child;
    });
  }
}
