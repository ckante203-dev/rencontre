import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/home/view/main_navigation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 🎁 Les nouveaux inscrits reçoivent 48 h de Premium (SQL 064) sans le
/// savoir : on le leur annonce une seule fois, avec ce que ça débloque et
/// le temps restant.
class BienvenuePremium {
  BienvenuePremium._();

  static Future<void> verifier() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final box = GetStorage();
    final cle = 'bienvenue_premium_vu_$uid';
    if (box.read<bool>(cle) == true) return;
    try {
      final p = await Supabase.instance.client
          .from('profiles')
          .select('created_at, boost_jusqua')
          .eq('id', uid)
          .maybeSingle();
      final cree = DateTime.tryParse(p?['created_at']?.toString() ?? '');
      final fin = DateTime.tryParse(p?['boost_jusqua']?.toString() ?? '');
      final maintenant = DateTime.now();
      // Compte récent (≤ 49 h) avec son cadeau encore actif
      if (cree == null || fin == null) return;
      if (maintenant.difference(cree) > const Duration(hours: 49)) {
        box.write(cle, true);
        return;
      }
      if (!fin.isAfter(maintenant)) return;
      // Laisser l'Accueil s'afficher, et ne pas couvrir une autre fenêtre
      await Future.delayed(const Duration(seconds: 3));
      if (Get.isDialogOpen == true || Get.isBottomSheetOpen == true) return;
      box.write(cle, true);
      final heures = fin.difference(DateTime.now()).inHours.clamp(1, 48);
      Get.dialog(_Fenetre(heures: heures), barrierDismissible: true);
    } catch (_) {}
  }
}

class _Fenetre extends StatelessWidget {
  final int heures;
  const _Fenetre({required this.heures});

  @override
  Widget build(BuildContext context) {
    Widget avantage(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(Icons.check_circle_rounded, size: 18, color: AppColors.online),
            const SizedBox(width: 8),
            Expanded(
                child: Text(t,
                    style: TextStyle(
                        fontSize: 14, color: AppColors.textPrimary))),
          ]),
        );
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🎁', style: TextStyle(fontSize: 46)),
          const SizedBox(height: 8),
          Text('Bienvenue sur Zamu !'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(
              'Tu as @h h de Premium offertes'
                  .trParams({'h': heures.toString()}),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent)),
          const SizedBox(height: 16),
          avantage('Vois qui t\'a liké et qui a vu ton profil'.tr),
          avantage('Jusqu\'à 600 profils'.tr),
          avantage('Ton profil mis en avant'.tr),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.gradientPink,
                borderRadius: BorderRadius.circular(16),
              ),
              child: TextButton(
                onPressed: () {
                  Get.back();
                  // L'onglet ❤️ : qui m'a liké / vu
                  if (Get.isRegistered<NavigationController>()) {
                    Get.find<NavigationController>().currentIndex.value =
                        NavigationController.likesIndex;
                  }
                },
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text('Voir qui m\'a liké'.tr,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.surAccent)),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Get.back(),
            child: Text('Plus tard'.tr,
                style: TextStyle(color: AppColors.textMuted)),
          ),
        ]),
      ),
    );
  }
}
