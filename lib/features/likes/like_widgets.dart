import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/features/likes/like_controller.dart'
    show LikeController;
import 'package:rencontre/core/theme/app_theme.dart';

// ══════════════════════════════════════════════════════════════════
//  BOUTON LIKE
// ══════════════════════════════════════════════════════════════════

class LikeButton extends StatelessWidget {
  final UserModel user;
  final double size;
  const LikeButton({super.key, required this.user, this.size = 50});

  Future<void> _likerAvecMot(LikeController ctrl) async {
    final saisie = TextEditingController();
    final choix = await Get.bottomSheet<String>(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Un mot pour @nom ?'.trParams({'nom': user.name}),
                style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            TextField(
              controller: saisie,
              autofocus: true,
              maxLength: 500,
              maxLines: 3,
              minLines: 1,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Ex : Ton sourire m\'a fait craquer 😄'.tr,
                hintStyle: TextStyle(color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surface2,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF2E9BFF)),
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () => Get.back(result: 'super'),
                  child: Text('⭐ Super Like',
                      style: TextStyle(color: AppColors.textPrimary)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () => Get.back(result: 'like'),
                  child: Text('❤️ Liker'.tr,
                      style: const TextStyle(color: AppColors.surAccent)),
                ),
              ),
            ]),
          ]),
        ),
      ),
      isScrollControlled: true,
    );
    if (choix == null) return;
    await ctrl.likerAvecMot(user, saisie.text, superLike: choix == 'super');
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<LikeController>();
    return Obx(() {
      final liked = ctrl.hasLiked(user.id);
      final matched = ctrl.hasMatch(user.id);
      final loading = ctrl.isLoading.value;

      final bool filled = liked || matched;

      return GestureDetector(
        onTap: loading ? null : () => ctrl.toggleLike(user),
        // Appui long : liker avec un mot (ou un Super Like)
        onLongPress: loading || filled ? null : () => _likerAvecMot(ctrl),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: filled
                ? LinearGradient(
                    colors: [AppColors.accent, AppColors.accent2],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: filled ? null : AppColors.surface2.withValues(alpha: 0.08),
            border: filled
                ? null
                : Border.all(color: AppColors.accent, width: 2),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: AppColors.accent
                          .withOpacity(matched ? 0.6 : 0.4),
                      blurRadius: matched ? 24 : 16,
                      spreadRadius: matched ? 3 : 1,
                    ),
                  ]
                : null,
          ),
          child: loading
              ? Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  ),
                )
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      filled
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: filled ? AppColors.surAccent : AppColors.accent,
                      size: size * 0.5,
                    ),
                    if (matched)
                      Positioned(
                        bottom: size * 0.06,
                        right: size * 0.06,
                        child: Container(
                          width: size * 0.28,
                          height: size * 0.28,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.lock_rounded,
                            size: size * 0.16,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      );
    });
  }
}
