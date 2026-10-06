import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/core/utils/app_routes.dart';
import 'package:rencontre/features/notifications/controller/notification_controller.dart';

/// 🔔 Activité : likes, matchs, demandes d'amis, stories des favoris…
class BoutonCloche extends StatelessWidget {
  final double taille;
  const BoutonCloche({super.key, this.taille = 42});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<NotificationController>()) {
      Get.put(NotificationController(), permanent: true);
    }
    final ctrl = Get.find<NotificationController>();
    return GestureDetector(
      onTap: () => Get.toNamed(AppRoutes.notifications),
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: taille,
          height: taille,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(Icons.notifications_rounded,
              color: AppColors.textPrimary, size: taille * 0.52),
        ),
        Obx(() {
          final n = ctrl.unreadCount.value;
          if (n == 0) return const SizedBox.shrink();
          return Positioned(
            top: -2,
            right: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18),
              height: 18,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                gradient: AppColors.gradientPink,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.bg, width: 2),
              ),
              child: Center(
                child: Text(n > 99 ? '99+' : '$n',
                    style: const TextStyle(
                        color: AppColors.surAccent,
                        fontSize: 9,
                        fontWeight: FontWeight.w900)),
              ),
            ),
          );
        }),
      ]),
    );
  }
}
