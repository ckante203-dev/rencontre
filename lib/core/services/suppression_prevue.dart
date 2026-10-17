import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/auth/controller/auth_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Suppression de compte différée (SQL 077) : si la personne se reconnecte
/// pendant les 30 jours, on lui propose de garder son compte.
class SuppressionPrevue {
  SuppressionPrevue._();

  static Future<void> verifier() async {
    final sb = Supabase.instance.client;
    if (sb.auth.currentUser == null) return;
    DateTime? fin;
    try {
      final r = await sb.rpc('ma_suppression_prevue');
      fin = r == null ? null : DateTime.tryParse('$r')?.toLocal();
    } catch (_) {
      return; // SQL 077 pas encore passé, ou hors ligne
    }
    if (fin == null) return;
    final date =
        '${fin.day.toString().padLeft(2, '0')}/${fin.month.toString().padLeft(2, '0')}/${fin.year}';
    await Future.delayed(const Duration(milliseconds: 800));
    await Get.dialog(
      PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Garder ton compte ?'.tr,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          content: Text(
              'Tu as demandé la suppression de ton compte. Il est masqué et sera supprimé définitivement le @date.'
                  .trParams({'date': date}),
              style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
          actions: [
            TextButton(
              onPressed: () async {
                Get.back();
                await AuthController.to.signOut();
              },
              child: Text('Continuer la suppression'.tr,
                  style: TextStyle(color: AppColors.error)),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await sb.rpc('annuler_suppression_compte');
                  Get.back();
                  Get.snackbar('Bon retour 💜'.tr,
                      'Ton compte est de nouveau visible.'.tr,
                      snackPosition: SnackPosition.TOP,
                      backgroundColor: AppColors.surface,
                      colorText: AppColors.textPrimary);
                } catch (_) {
                  Get.snackbar('Oups'.tr, 'Erreur de connexion. Réessaie.'.tr,
                      snackPosition: SnackPosition.TOP,
                      backgroundColor: AppColors.surface,
                      colorText: AppColors.textPrimary);
                }
              },
              child: Text('Garder mon compte'.tr,
                  style: TextStyle(
                      color: AppColors.lien, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
      barrierDismissible: false,
    );
  }
}
