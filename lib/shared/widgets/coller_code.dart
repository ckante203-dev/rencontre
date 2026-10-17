import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';

/// « 📋 Coller le code » : remplit [champ] avec les chiffres copiés depuis
/// l'e-mail (un bouton « Copier » est impossible dans un e-mail).
class BoutonCollerCode extends StatelessWidget {
  final TextEditingController champ;
  const BoutonCollerCode({super.key, required this.champ});

  Future<void> _coller() async {
    final presse = await Clipboard.getData(Clipboard.kTextPlain);
    final chiffres = (presse?.text ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (chiffres.length < 6) {
      Get.snackbar('Rien à coller'.tr,
          'Copie d\'abord le code depuis l\'e-mail (appui long sur le code)'.tr,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
      return;
    }
    champ.text = chiffres.length > 10 ? chiffres.substring(0, 10) : chiffres;
    champ.selection = TextSelection.collapsed(offset: champ.text.length);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: _coller,
        icon: Icon(Icons.content_paste_rounded, size: 18, color: AppColors.lien),
        label: Text('Coller le code'.tr,
            style: TextStyle(
                color: AppColors.lien, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
