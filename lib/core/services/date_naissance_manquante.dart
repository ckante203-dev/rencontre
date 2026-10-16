import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/auth/controller/auth_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Comptes inscrits sans date de naissance (bug d'inscription corrigé en
/// 1.1.9 : la date se perdait pour ~8 inscrits sur 10). On la demande une
/// fois, de façon obligatoire : âge affiché, filtres par âge et 18 ans
/// minimum vérifié.
class DateNaissanceManquante {
  DateNaissanceManquante._();

  static bool _enCours = false;

  static Future<void> verifier() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || _enCours) return;
    try {
      final p = await Supabase.instance.client
          .from('profiles')
          .select('birthdate, est_officiel')
          .eq('id', uid)
          .maybeSingle();
      if (p == null || p['est_officiel'] == true) return;
      if ((p['birthdate']?.toString() ?? '').trim().isNotEmpty) return;
    } catch (_) {
      return; // hors ligne : on redemandera à la prochaine ouverture
    }
    // Laisser l'Accueil s'afficher d'abord
    await Future.delayed(const Duration(milliseconds: 1500));
    if (Get.isDialogOpen == true) return;
    _enCours = true;
    await Get.dialog(_Fenetre(uid: uid), barrierDismissible: false);
    _enCours = false;
  }
}

class _Fenetre extends StatefulWidget {
  final String uid;
  const _Fenetre({required this.uid});

  @override
  State<_Fenetre> createState() => _FenetreState();
}

class _FenetreState extends State<_Fenetre> {
  final _champ = TextEditingController();
  String _erreur = '';
  bool _envoi = false;
  bool _mineur = false;

  @override
  void dispose() {
    _champ.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    final c = _champ.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (c.length != 8) {
      setState(() => _erreur = 'Date invalide — format JJ/MM/AAAA'.tr);
      return;
    }
    final j = int.parse(c.substring(0, 2));
    final m = int.parse(c.substring(2, 4));
    final a = int.parse(c.substring(4, 8));
    final date = DateTime(a, m, j);
    // Refuse les dates inexistantes (31/02…), que DateTime « corrige »
    if (date.day != j || date.month != m || date.year != a) {
      setState(() => _erreur = 'Date invalide — format JJ/MM/AAAA'.tr);
      return;
    }
    final now = DateTime.now();
    var age = now.year - a;
    if (now.month < m || (now.month == m && now.day < j)) age--;
    if (age > 100 || age < 0) {
      setState(() => _erreur = 'Date invalide — format JJ/MM/AAAA'.tr);
      return;
    }
    if (age < 18) {
      setState(() {
        _mineur = true;
        _erreur = '';
      });
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = '';
    });
    try {
      await Supabase.instance.client.from('profiles').update({
        'birthdate': '${a.toString().padLeft(4, '0')}-'
            '${m.toString().padLeft(2, '0')}-${j.toString().padLeft(2, '0')}',
        'age': age,
      }).eq('id', widget.uid);
      Get.back();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _erreur = 'Erreur de connexion. Réessaie.'.tr;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
            _mineur
                ? 'Zamu est réservé aux 18 ans et plus'.tr
                : 'Ta date de naissance 🎂'.tr,
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              _mineur
                  ? 'Tu ne peux pas utiliser Zamu avant tes 18 ans.'.tr
                  : 'Elle n\'a pas été enregistrée à ton inscription. Ton âge s\'affichera sur ton profil (tu peux masquer ta date dans les paramètres).'
                      .tr,
              style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
          if (!_mineur) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _champ,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [_FormatDate()],
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  letterSpacing: 2),
              decoration: InputDecoration(
                hintText: 'JJ / MM / AAAA'.tr,
                hintStyle: TextStyle(color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surface2,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
              onSubmitted: (_) => _valider(),
            ),
          ],
          if (_erreur.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_erreur,
                style: TextStyle(color: AppColors.error, fontSize: 13)),
          ],
        ]),
        actions: [
          if (_mineur)
            TextButton(
              onPressed: () => Get.find<AuthController>().signOut(),
              child: Text('Se déconnecter'.tr,
                  style: TextStyle(color: AppColors.error)),
            )
          else
            TextButton(
              onPressed: _envoi ? null : _valider,
              child: _envoi
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Valider'.tr,
                      style: TextStyle(
                          color: AppColors.lien,
                          fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

/// JJ/MM/AAAA tapé au clavier numérique
class _FormatDate extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue next) {
    final c = next.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buf = StringBuffer();
    for (int i = 0; i < c.length && i < 8; i++) {
      if (i == 2 || i == 4) buf.write('/');
      buf.write(c[i]);
    }
    final s = buf.toString();
    return TextEditingValue(
        text: s, selection: TextSelection.collapsed(offset: s.length));
  }
}
