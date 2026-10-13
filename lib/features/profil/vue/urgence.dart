import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Contact d'urgence (gardé sur le téléphone) et alerte « Je suis en danger » :
/// ouvre WhatsApp (ou les SMS) vers ce contact avec la position GPS.
class Urgence {
  static const _cle = 'contact_urgence';

  static Map<String, String>? get contact {
    try {
      final v = GetStorage().read<Map>(_cle);
      if (v == null) return null;
      return {'nom': '${v['nom'] ?? ''}', 'numero': '${v['numero'] ?? ''}'};
    } catch (_) {
      return null;
    }
  }

  /// Numéro au format international sans « + » (Côte d'Ivoire par défaut)
  static String international(String numero) {
    var n = numero.replaceAll(RegExp(r'[^0-9+]'), '');
    if (n.startsWith('+')) return n.substring(1);
    if (n.startsWith('00')) return n.substring(2);
    if (n.length == 10 && n.startsWith('0')) return '225$n';
    return n;
  }

  /// Saisie ou modification du contact d'urgence
  static Future<void> definir(BuildContext context) async {
    final actuel = contact;
    final nom = TextEditingController(text: actuel?['nom'] ?? '');
    final numero = TextEditingController(text: actuel?['numero'] ?? '');
    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppColors.textMuted),
          filled: true,
          fillColor: AppColors.surface2,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
        );
    // Peut être appelé depuis un menu déjà fermé : contexte de l'appli
    await showModalBottomSheet(
      context: Get.context ?? context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctxFeuille) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctxFeuille).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Contact d'urgence".tr,
                style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(
                'Une personne de confiance. Il reste sur ton téléphone, Zamu ne le voit pas.'
                    .tr,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 14),
            TextField(
                controller: nom,
                style: TextStyle(color: AppColors.textPrimary),
                decoration: deco('Nom (ex : Maman, Awa)'.tr)),
            const SizedBox(height: 10),
            TextField(
                controller: numero,
                keyboardType: TextInputType.phone,
                style: TextStyle(color: AppColors.textPrimary),
                decoration: deco('Numéro WhatsApp (ex : 07 00 00 00 00)'.tr)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  final n = numero.text.trim();
                  if (n.replaceAll(RegExp(r'[^0-9]'), '').length < 8) return;
                  GetStorage().write(
                      _cle, {'nom': nom.text.trim(), 'numero': n});
                  Get.back();
                },
                child: Text('Enregistrer'.tr,
                    style: const TextStyle(
                        color: AppColors.surAccent,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Envoie l'alerte (après confirmation) avec la position actuelle
  static Future<void> alerter(BuildContext context) async {
    final c = contact;
    if (c == null || c['numero']!.isEmpty) {
      await definir(context);
      if (contact == null) return;
    }
    final ok = await Get.dialog<bool>(AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('🚨 Alerter @nom ?'.trParams({'nom': contact!['nom']!.isEmpty ? contact!['numero']! : contact!['nom']!}),
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
      content: Text(
          "Un message avec ta position va s'ouvrir dans WhatsApp, prêt à envoyer. En danger immédiat, appelle aussi la police : 110 ou 111."
              .tr,
          style: TextStyle(color: AppColors.textMuted, height: 1.5)),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('Annuler'.tr,
                style: TextStyle(color: AppColors.textMuted))),
        TextButton(
            onPressed: () => Get.back(result: true),
            child: Text('Alerter'.tr,
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w800))),
      ],
    ));
    if (ok != true) return;

    String lieu = '';
    try {
      final pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high)
          .timeout(const Duration(seconds: 8));
      lieu = 'https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
    } catch (_) {
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) {
          lieu = 'https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
        }
      } catch (_) {}
    }
    final texte = lieu.isEmpty
        ? "🚨 J'ai besoin d'aide, appelle-moi vite. (alerte envoyée depuis Zamu)".tr
        : "🚨 J'ai besoin d'aide, appelle-moi vite. Ma position : @lieu (alerte envoyée depuis Zamu)"
            .trParams({'lieu': lieu});
    final numero = international(contact!['numero']!);
    final whatsapp = Uri.parse(
        'https://wa.me/$numero?text=${Uri.encodeComponent(texte)}');
    final sms = Uri.parse('sms:+$numero?body=${Uri.encodeComponent(texte)}');
    if (!await launchUrl(whatsapp, mode: LaunchMode.externalApplication)) {
      await launchUrl(sms, mode: LaunchMode.externalApplication);
    }
  }
}
