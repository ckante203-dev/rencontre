import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/core/utils/app_routes.dart';
import 'package:rencontre/features/likes/profile_insights_controller.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
import 'package:rencontre/core/services/revenue_cat_service.dart';

// ✅ Premium = profil (webhook RevenueCat) OU RevenueCat en direct : juste
// après un achat, le profil n'est pas encore à jour et les cartes restaient
// verrouillées (le paywall se rouvrait).
bool _isPremiumNow() {
  final profil = Get.isRegistered<ControleurProfil>() &&
      Get.find<ControleurProfil>().isPremium.value;
  final rc = Get.isRegistered<RevenueCatService>() &&
      Get.find<RevenueCatService>().isPremium.value;
  return profil || rc;
}

class LikesInsightsScreen extends StatelessWidget {
  const LikesInsightsScreen({super.key});

  // ✅ Logique de déblocage :
  // - Premium (profiles.is_premium) → ouvre la vraie liste détaillée.
  // - Pas premium, et le système de paiement RevenueCat est déjà
  //   enregistré → ouvre le paywall pour s'abonner.
  // - Pas premium, et RevenueCat n'est PAS encore enregistré (le cas
  //   actuel, en attente de validation Play Console) → on ne navigue
  //   nulle part pour éviter un crash sur Get.find<RevenueCatService>(),
  //   on affiche juste un message temporaire.
  void _onCardTap(BuildContext context, String type) {
    final isPremium = _isPremiumNow();

    if (isPremium) {
      Get.toNamed(AppRoutes.likesDetails, arguments: type);
      return;
    }

    // ✅ RevenueCat pas encore configuré (en attente de validation Play
    // Console) → fallback sûr, pas de navigation vers un écran qui
    // dépend d'un service non enregistré (évite un crash Get.find()).
    if (!Get.isRegistered<RevenueCatService>()) {
      Get.snackbar(
        '🔒 Bientôt disponible',
        'L\'abonnement premium arrive très bientôt — reviens vite !',
        snackPosition: SnackPosition.TOP,
        backgroundColor: AppColors.surface,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    Get.toNamed(AppRoutes.paywall);
  }

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<ProfileInsightsController>()) {
      Get.put(ProfileInsightsController(), permanent: true);
    }
    final ctrl = Get.find<ProfileInsightsController>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: ctrl.loadCounts,
          color: AppColors.accent,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              ShaderMask(
                shaderCallback: (b) => AppColors.gradientPink.createShader(b),
                child: const Text(
                  'Likes',
                  style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Obx(() {
                final isPremium = _isPremiumNow();
                return Row(
                  children: [
                    Expanded(
                      child: _InsightCard(
                        icon: Icons.remove_red_eye_rounded,
                        label: 'Qui m\'a vu',
                        count: ctrl.viewersCount.value,
                        loading: ctrl.isLoading.value,
                        isPremium: isPremium,
                        onTap: () => _onCardTap(context, 'viewers'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _InsightCard(
                        icon: Icons.favorite_rounded,
                        label: 'Qui m\'a liké',
                        count: ctrl.likersCount.value,
                        loading: ctrl.isLoading.value,
                        isPremium: isPremium,
                        onTap: () => _onCardTap(context, 'likers'),
                      ),
                    ),
                  ],
                );
              }),
              const SizedBox(height: 24),
              Obx(() {
                final isPremium = _isPremiumNow();
                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        isPremium
                            ? Icons.workspace_premium_rounded
                            : Icons.lock_rounded,
                        size: 32,
                        color: AppColors.accent,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isPremium
                            ? 'Tu es Premium ✨'
                            : 'Découvre qui s\'intéresse à toi',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Syne',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isPremium
                            ? 'Tu peux voir qui a vu et liké ton profil.'
                            : 'Passe en Premium pour voir qui a vu et liké ton profil.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 13, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── CARTE INSIGHT ────────────────────────────────────────────────

class _InsightCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final bool loading;
  final bool isPremium;
  final VoidCallback onTap;

  const _InsightCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.loading,
    required this.isPremium,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(icon, size: 18, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                loading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.accent),
                      )
                    : Text(
                        '$count',
                        style: TextStyle(
                          fontFamily: 'Syne',
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
              ],
            ),
            if (!isPremium)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientPink,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.lock_rounded,
                      size: 11, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
