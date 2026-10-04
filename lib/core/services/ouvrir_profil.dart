import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';

/// Ouvre le profil complet d'une personne à partir de son id
/// (recherche par @pseudo, QR code Zamu…). La fiche est rechargée depuis
/// la base : un profil partiel afficherait un âge et une bio faux.
Future<void> ouvrirProfilParId(String id) async {
  try {
    final row = await supabase
        .from('profiles')
        .select()
        .eq('id', id)
        .maybeSingle()
        .timeout(const Duration(seconds: 10));
    if (row == null || row['is_suspended'] == true) {
      _introuvable();
      return;
    }
    if (id == supabase.auth.currentUser?.id) {
      Get.snackbar('C\'est toi 😄', 'Ce code est ton propre profil',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white);
      return;
    }
    Get.toNamed('/profile/view',
        arguments: SupabaseService().profileToUser(row));
  } catch (e) {
    debugPrint('ouvrirProfilParId : $e');
    _introuvable();
  }
}

void _introuvable() => Get.snackbar(
    'Profil introuvable', 'Ce profil n\'existe plus ou n\'est pas disponible',
    snackPosition: SnackPosition.TOP,
    backgroundColor: AppColors.surface,
    colorText: Colors.white);
