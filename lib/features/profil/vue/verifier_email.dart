import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/shared/widgets/coller_code.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Vérification de l'adresse e-mail après l'inscription (comme Snapchat) :
/// on s'inscrit sans attendre, puis Paramètres → « Vérifier mon e-mail »
/// envoie un code (modèle « Magic Link » de Supabase, avec {{ .Token }}).
class TuileVerifEmail extends StatefulWidget {
  const TuileVerifEmail({super.key});

  @override
  State<TuileVerifEmail> createState() => _TuileVerifEmailState();
}

class _TuileVerifEmailState extends State<TuileVerifEmail> {
  bool? _verifie;

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final p = await _sb
          .from('profiles')
          .select('email_verified')
          .eq('id', uid)
          .maybeSingle();
      if (mounted) setState(() => _verifie = p?['email_verified'] == true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final email = _sb.auth.currentUser?.email ?? '';
    // Comptes Google / sans e-mail : rien à vérifier
    if (_verifie == null || email.isEmpty) return const SizedBox.shrink();
    final ok = _verifie!;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GestureDetector(
        onTap: ok
            ? null
            : () async {
                final fait = await Get.bottomSheet<bool>(
                    _FeuilleVerif(email: email),
                    isScrollControlled: true,
                    backgroundColor: AppColors.surface,
                    shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(24))));
                if (fait == true && mounted) setState(() => _verifie = true);
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: ok ? AppColors.border : AppColors.accent, width: ok ? 1 : 1.5)),
          child: Row(children: [
            Text(ok ? '✅' : '✉️', style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ok ? 'E-mail vérifié'.tr : 'Vérifier mon e-mail'.tr,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                        ok
                            ? email
                            : 'Protège ton compte : on t\'envoie un code'.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                  ]),
            ),
            if (!ok)
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted, size: 20),
          ]),
        ),
      ),
    );
  }
}

class _FeuilleVerif extends StatefulWidget {
  final String email;
  const _FeuilleVerif({required this.email});

  @override
  State<_FeuilleVerif> createState() => _FeuilleVerifState();
}

class _FeuilleVerifState extends State<_FeuilleVerif> {
  final _code = TextEditingController();
  bool _envoye = false;
  bool _chargement = false;
  String _erreur = '';

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    setState(() {
      _chargement = true;
      _erreur = '';
    });
    try {
      await _sb.auth.signInWithOtp(email: widget.email, shouldCreateUser: false);
      if (mounted) setState(() => _envoye = true);
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _erreur = e.message.toLowerCase().contains('rate') ||
                e.message.contains('seconds')
            ? 'Trop de demandes. Réessaie dans quelques minutes.'.tr
            : 'Erreur de connexion. Réessaie.'.tr);
      }
    } catch (_) {
      if (mounted) setState(() => _erreur = 'Erreur de connexion. Réessaie.'.tr);
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _valider() async {
    final code = _code.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (code.length < 6) {
      setState(() => _erreur = 'Entre le code reçu par email'.tr);
      return;
    }
    setState(() {
      _chargement = true;
      _erreur = '';
    });
    try {
      final res = await _sb.auth
          .verifyOTP(email: widget.email, token: code, type: OtpType.email);
      final uid = res.user?.id ?? _sb.auth.currentUser?.id;
      if (uid == null) throw Exception('code');
      await _sb.from('profiles').update({'email_verified': true}).eq('id', uid);
      Get.back(result: true);
      Get.snackbar('E-mail vérifié ✅'.tr, widget.email,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
    } on AuthException catch (_) {
      if (mounted) {
        setState(() => _erreur =
            'Code incorrect ou expiré. Renvoie un nouveau code.'.tr);
      }
    } catch (_) {
      if (mounted) setState(() => _erreur = 'Erreur de connexion. Réessaie.'.tr);
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 24),
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
            Text('Vérifier mon e-mail'.tr,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(
                _envoye
                    ? 'Entre le code reçu à @email (regarde aussi dans les spams).'
                        .trParams({'email': widget.email})
                    : 'On envoie un code à @email pour confirmer que c\'est bien ton adresse.'
                        .trParams({'email': widget.email}),
                style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 18),
            if (_envoye) ...[
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: '12345678',
                  hintStyle: TextStyle(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.surface2,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
              ),
              BoutonCollerCode(champ: _code),
            ],
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
                  onPressed: _chargement
                      ? null
                      : (_envoye ? _valider : _envoyer),
                  child: _chargement
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.surAccent))
                      : Text(
                          _envoye ? 'Valider'.tr : 'Envoyer le code'.tr,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.surAccent)),
                ),
              ),
            ),
            if (_envoye)
              Center(
                child: TextButton(
                  onPressed: _chargement ? null : _envoyer,
                  child: Text('Renvoyer le code'.tr,
                      style: TextStyle(color: AppColors.lien)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
