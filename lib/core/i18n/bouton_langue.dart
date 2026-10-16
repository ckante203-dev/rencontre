import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/i18n/traductions.dart';
import 'package:rencontre/core/theme/app_theme.dart';

/// Petit bouton « 🌐 FR » en haut des écrans de connexion / inscription :
/// choisir sa langue avant même d'avoir un compte (enregistrée sur le
/// téléphone, puis dans le profil une fois connecté).
class BoutonLangue extends StatelessWidget {
  const BoutonLangue({super.key});

  void _choisir() {
    Widget ligne(String code, String nom, String drapeau) {
      final actif = Langue.code == code;
      return ListTile(
        leading: Text(drapeau, style: const TextStyle(fontSize: 24)),
        title: Text(nom,
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: actif ? FontWeight.w800 : FontWeight.w500)),
        trailing: actif
            ? Icon(Icons.check_circle_rounded, color: AppColors.accent)
            : null,
        onTap: () async {
          Get.back();
          if (!actif) await Langue.changer(code);
        },
      );
    }

    Get.bottomSheet(
      SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            ligne('fr', 'Français', '🇫🇷'),
            ligne('en', 'English', '🇬🇧'),
          ]),
        ),
      ),
      backgroundColor: Colors.transparent,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _choisir,
      // Bien visible : dégradé de la marque, drapeau de la langue choisie
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          gradient: AppColors.gradientPink,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(Langue.code == 'en' ? '🇬🇧' : '🇫🇷',
              style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(Langue.code.toUpperCase(),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.surAccent)),
          const SizedBox(width: 2),
          const Icon(Icons.keyboard_arrow_down_rounded,
              size: 18, color: AppColors.surAccent),
        ]),
      ),
    );
  }
}
