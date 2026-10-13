import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Parrainage : mon code = mon @pseudo. Un nouvel inscrit (compte de moins
/// de 7 jours) entre le code d'un ami : 1 h de Boost pour les deux
/// (fonction utiliser_code_parrainage, SQL 053).
class CarteParrainage extends StatefulWidget {
  const CarteParrainage({super.key});

  @override
  State<CarteParrainage> createState() => _CarteParrainageState();
}

class _CarteParrainageState extends State<CarteParrainage> {
  int? _filleuls;
  bool _peutSaisir = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final r = await Supabase.instance.client.rpc('mon_parrainage');
      if (r is Map && mounted) {
        setState(() {
          _filleuls = (r['filleuls'] as num?)?.toInt() ?? 0;
          _peutSaisir = r['peut_saisir'] == true;
        });
      }
    } catch (_) {} // SQL 053 pas encore passé : carte sans compteur
  }

  void _inviter(String pseudo) {
    SharePlus.instance.share(ShareParams(
      text: pseudo.isEmpty
          ? 'Rejoins-moi sur Zamu 💬\nhttps://play.google.com/store/apps/details?id=com.vybestyle.zamu'
              .tr
          : 'Rejoins-moi sur Zamu 💬 À l\'inscription, entre mon code @pseudo : on gagne tous les deux 1 h de Boost ⚡\nhttps://play.google.com/store/apps/details?id=com.vybestyle.zamu'
              .trParams({'pseudo': pseudo}),
    ));
  }

  Future<void> _saisirCode() async {
    final saisie = TextEditingController();
    final code = await Get.dialog<String>(AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Code de parrainage'.tr,
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
      content: TextField(
        controller: saisie,
        autofocus: true,
        style: TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: "Pseudo de l'ami qui t'a invité".tr,
          hintStyle: TextStyle(color: AppColors.textMuted),
          prefixText: '@',
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Get.back(),
            child: Text('Annuler'.tr,
                style: TextStyle(color: AppColors.textMuted))),
        TextButton(
            onPressed: () => Get.back(result: saisie.text.trim()),
            child: Text('Valider'.tr,
                style: TextStyle(color: AppColors.accent))),
      ],
    ));
    if (code == null || code.isEmpty) return;
    String r;
    try {
      r = await Supabase.instance.client.rpc('utiliser_code_parrainage',
          params: {'p_code': code.replaceAll('@', '')}) as String;
    } catch (_) {
      r = 'erreur';
    }
    final messages = {
      'ok': 'Code accepté ⚡ 1 h de Boost pour toi et ton ami !'.tr,
      'introuvable': 'Aucun membre avec ce pseudo'.tr,
      'deja_parraine': 'Tu as déjà utilisé un code'.tr,
      'trop_tard': 'Le code doit être entré dans les 7 jours après l\'inscription'.tr,
      'soi_meme': 'Tu ne peux pas utiliser ton propre code'.tr,
    };
    Get.snackbar('Parrainage'.tr, messages[r] ?? 'Action impossible, réessaie'.tr,
        snackPosition: SnackPosition.TOP,
        backgroundColor: AppColors.surface,
        colorText: AppColors.textPrimary);
    if (r == 'ok') {
      ControleurProfil.to.chargerMonProfil();
      _charger();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pseudo = ControleurProfil.to.monUsername.value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('🎁', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Invite tes amis'.tr,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ),
            if ((_filleuls ?? 0) > 0)
              Text('@n invité@p'.trParams({
                'n': '$_filleuls',
                'p': _filleuls! > 1 ? 's' : '',
              }),
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]),
          const SizedBox(height: 6),
          Text(
              pseudo.isEmpty
                  ? 'Choisis ton pseudo : il sert de code de parrainage.'.tr
                  : 'Ton code : @@pseudo. Chaque ami inscrit avec ton code vous donne 1 h de Boost à tous les deux.'
                      .trParams({'pseudo': pseudo}),
              style: TextStyle(
                  fontSize: 13, color: AppColors.textMuted, height: 1.4)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.share_rounded,
                    color: AppColors.surAccent, size: 18),
                label: Text('Inviter'.tr,
                    style: const TextStyle(color: AppColors.surAccent)),
                onPressed: () => _inviter(pseudo),
              ),
            ),
            if (_peutSaisir) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _saisirCode,
                  child: Text("J'ai un code".tr,
                      style: TextStyle(color: AppColors.textPrimary)),
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}
