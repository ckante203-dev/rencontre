import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Paramètres → « Signaler un bug » : le membre décrit le problème. La
/// version de l'app, le modèle du téléphone et la version d'Android sont
/// joints (SQL 082). L'équipe répond dans la conversation « Zamu ».
/// Pas de capture d'écran : elles sont bloquées dans l'appli (FLAG_SECURE).
void ouvrirSignalerBug() {
  Get.bottomSheet(
    const _FeuilleBug(),
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
  );
}

class _FeuilleBug extends StatefulWidget {
  const _FeuilleBug();

  @override
  State<_FeuilleBug> createState() => _FeuilleBugState();
}

class _FeuilleBugState extends State<_FeuilleBug> {
  final _texte = TextEditingController();
  bool _envoi = false;
  String _erreur = '';

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  Future<Map<String, String?>> _infosTelephone() async {
    String? version, appareil, systeme;
    try {
      final p = await PackageInfo.fromPlatform();
      version = '${p.version} (${p.buildNumber})';
    } catch (_) {}
    try {
      if (Platform.isAndroid) {
        final m = await const MethodChannel('zamu/appareil')
            .invokeMapMethod<String, String>('modele');
        appareil = m?['appareil'];
        systeme = m?['systeme'];
      } else {
        systeme = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
      }
    } catch (_) {
      systeme = Platform.operatingSystemVersion;
    }
    String cut(String? s, int n) =>
        s == null ? '' : (s.length > n ? s.substring(0, n) : s);
    return {
      'app_version': version == null ? null : cut(version, 40),
      'appareil': appareil == null ? null : cut(appareil, 120),
      'systeme': systeme == null ? null : cut(systeme, 120),
    };
  }

  Future<void> _envoyer() async {
    final texte = _texte.text.trim();
    if (texte.length < 5) {
      setState(() => _erreur = 'Décris le problème en quelques mots'.tr);
      return;
    }
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    setState(() {
      _envoi = true;
      _erreur = '';
    });
    try {
      await _sb.from('bugs_signales').insert({
        'user_id': uid,
        'texte': texte,
        ...await _infosTelephone(),
      });
      Get.back();
      Get.snackbar('Merci ! 🙏'.tr,
          'Ton signalement est bien arrivé. On te répond dans la conversation Zamu.'.tr,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => _erreur = e.message.contains('trop_de_signalements')
            ? 'Tu as déjà envoyé 5 signalements aujourd\'hui. Réessaie demain.'.tr
            : 'Envoi impossible, vérifie ta connexion'.tr);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _erreur = 'Envoi impossible, vérifie ta connexion'.tr);
      }
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Pas de viewInsets : Get.bottomSheet remonte déjà la feuille
      // au-dessus du clavier
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Text('Signaler un bug 🐞'.tr,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(
                'Dis-nous ce qui ne marche pas : où tu étais dans l\'appli, ce que tu as fait, ce qui s\'est passé.'
                    .tr,
                style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 16),
            TextField(
              controller: _texte,
              maxLines: 5,
              minLines: 3,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText:
                    'Ex. : je reçois la notification mais le message n\'apparaît pas…'
                        .tr,
                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                filled: true,
                fillColor: AppColors.surface2,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 4),
            Text(
                'La version de l\'appli et le modèle de ton téléphone sont joints automatiquement.'
                    .tr,
                style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            const SizedBox(height: 14),
            if (_erreur.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_erreur,
                    style: TextStyle(fontSize: 13, color: AppColors.error)),
              ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                    gradient: AppColors.gradientPink,
                    borderRadius: BorderRadius.circular(16)),
                child: TextButton(
                  onPressed: _envoi ? null : _envoyer,
                  child: _envoi
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.surAccent))
                      : Text('Envoyer'.tr,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.surAccent)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
