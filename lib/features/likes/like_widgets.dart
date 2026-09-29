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
            color: filled ? null : Colors.white.withOpacity(0.08),
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
                      color: filled ? Colors.white : AppColors.accent,
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
