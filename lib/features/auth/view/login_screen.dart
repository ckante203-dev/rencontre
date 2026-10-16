import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/i18n/bouton_langue.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/auth/controller/auth_controller.dart';
import 'package:rencontre/features/auth/view/cgu_screen.dart';
import 'package:rencontre/features/auth/widget/auth_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  @override
  void initState() {
    super.initState();
    final ctrl = Get.find<AuthController>();
    ctrl.emailController.clear();
    ctrl.passwordController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ctrl.clearError();
      ctrl.showPassword.value = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AuthController>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 28),

                // ── HEADER : Nom + choix de la langue ──
                Row(children: [
                  Text(
                    'Zamu'.tr,
                    style: TextStyle(
                      fontFamily: 'Syne',
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  const BoutonLangue(),
                ]),

                const SizedBox(height: 40),

                // ── Titre ──
                Text(
                  'connexion.titre'.tr,
                  style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'connexion.sous_titre'.tr,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF9999BB),
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 32),

                // ── Email ou nom d'utilisateur ──
                AuthInputField(
                  label: 'connexion.identifiant'.tr,
                  hint: 'connexion.identifiant_hint'.tr,
                  icon: '✉️',
                  controller: ctrl.emailController,
                  onChanged: (_) => ctrl.clearError(),
                ),
                const SizedBox(height: 14),

                // ── Mot de passe ──
                Obx(() => AuthInputField(
                      label: 'commun.mot_de_passe'.tr,
                      hint: '••••••••',
                      icon: '🔒',
                      controller: ctrl.passwordController,
                      isPassword: true,
                      showPassword: ctrl.showPassword.value,
                      onTogglePassword: () => ctrl.showPassword.toggle(),
                      onChanged: (_) => ctrl.clearError(),
                    )),

                // ── Mot de passe oublié ──
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => _showForgotPassword(context, ctrl),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'connexion.oublie'.tr,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Erreur ──
                Obx(() => AuthErrorMessage(message: ctrl.errorMessage.value)),
                const SizedBox(height: 16),

                // ── Bouton Se connecter ──
                Obx(() => AuthPrimaryButton(
                      label: 'connexion.bouton'.tr,
                      onTap: ctrl.signInWithEmail,
                      isLoading: ctrl.isLoading.value,
                    )),

                const SizedBox(height: 24),

                // ── Séparateur ──
                Row(
                  children: [
                    Expanded(
                        child: Container(height: 1, color: AppColors.border)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        'commun.ou'.tr,
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9999BB),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                        child: Container(height: 1, color: AppColors.border)),
                  ],
                ),

                const SizedBox(height: 24),

                // ── Continuer avec Google ──
                _GradientBorderButton(
                  icon: 'G',
                  label: 'commun.google'.tr,
                  onTap: ctrl.signInWithGoogle,
                ),
                if (Platform.isIOS) ...[
                  const SizedBox(height: 12),
                  _GradientBorderButton(
                    icon: '\uF8FF',
                    label: 'commun.apple'.tr,
                    onTap: ctrl.signInWithApple,
                  ),
                ],

                const SizedBox(height: 32),

                // ── Pas de compte : gros bouton rouge, bien visible ──
                Center(
                  child: Text('connexion.pas_de_compte'.tr,
                      style: TextStyle(fontSize: 14, color: Color(0xFF9999BB))),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => Get.toNamed('/signup'),
                  child: Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5304A),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFFE5304A).withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        'connexion.inscrire'.tr,
                        style: const TextStyle(
                          color: AppColors.surAccent,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── CGU ──
                Center(
                  child: GestureDetector(
                    onTap: () => Get.to(
                      () => const CguScreen(showAcceptButton: false),
                      transition: Transition.cupertino,
                    ),
                    child: Text(
                      'connexion.liens_legaux'.tr,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        height: 1.5,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showForgotPassword(BuildContext context, AuthController ctrl) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _MotDePasseOublie(
          ctrl: ctrl, emailInitial: ctrl.emailController.text.trim()),
    );
  }
}

/// Mot de passe oublié en deux étapes : 1) e-mail → code envoyé ;
/// 2) code à 8 chiffres + nouveau mot de passe (tout se passe dans l'app).
class _MotDePasseOublie extends StatefulWidget {
  final AuthController ctrl;
  final String emailInitial;
  const _MotDePasseOublie({required this.ctrl, required this.emailInitial});

  @override
  State<_MotDePasseOublie> createState() => _MotDePasseOublieState();
}

class _MotDePasseOublieState extends State<_MotDePasseOublie> {
  late final _email = TextEditingController(
      text: widget.emailInitial.contains('@') ? widget.emailInitial : '');
  final _code = TextEditingController();
  final _mdp = TextEditingController();
  final _mdp2 = TextEditingController();
  bool _codeEnvoye = false;
  bool _chargement = false;
  bool _voirMdp = false;
  String _erreur = '';

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _mdp.dispose();
    _mdp2.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _erreur = 'Entre ton adresse email'.tr);
      return;
    }
    setState(() {
      _chargement = true;
      _erreur = '';
    });
    final err = await widget.ctrl.envoyerCodeReinitialisation(email);
    if (!mounted) return;
    setState(() {
      _chargement = false;
      if (err == null) {
        _codeEnvoye = true;
      } else {
        _erreur = err;
      }
    });
  }

  Future<void> _valider() async {
    final code = _code.text.replaceAll(' ', '');
    if (code.length < 6) {
      setState(() => _erreur = 'Entre le code reçu par email'.tr);
      return;
    }
    if (_mdp.text.length < 8) {
      setState(() =>
          _erreur = 'Le mot de passe doit faire au moins 8 caractères'.tr);
      return;
    }
    if (_mdp.text != _mdp2.text) {
      setState(() => _erreur = 'inscription.mdp_ko'.tr);
      return;
    }
    setState(() {
      _chargement = true;
      _erreur = '';
    });
    final err =
        await widget.ctrl.reinitialiserMotDePasse(_email.text, code, _mdp.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _chargement = false;
        _erreur = err;
      });
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
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'connexion.oublie'.tr,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _codeEnvoye
                  ? 'Entre le code reçu à @email (regarde aussi dans les spams), puis ton nouveau mot de passe.'
                      .trParams({'email': _email.text.trim()})
                  : "On t'envoie un code par email pour choisir un nouveau mot de passe."
                      .tr,
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),
            if (!_codeEnvoye)
              AuthInputField(
                label: 'commun.email'.tr,
                hint: 'commun.email_hint'.tr,
                icon: '✉️',
                controller: _email,
                keyboardType: TextInputType.emailAddress,
              )
            else ...[
              AuthInputField(
                label: 'Code reçu par email'.tr,
                hint: '12345678',
                icon: '🔢',
                controller: _code,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              AuthInputField(
                label: 'Nouveau mot de passe'.tr,
                hint: 'inscription.mdp_hint'.tr,
                icon: '🔒',
                controller: _mdp,
                isPassword: true,
                showPassword: _voirMdp,
                onTogglePassword: () => setState(() => _voirMdp = !_voirMdp),
              ),
              const SizedBox(height: 12),
              AuthInputField(
                label: 'inscription.confirmer_mdp'.tr,
                hint: 'inscription.confirmer_mdp_hint'.tr,
                icon: '🔒',
                controller: _mdp2,
                isPassword: true,
                showPassword: _voirMdp,
                onTogglePassword: () => setState(() => _voirMdp = !_voirMdp),
              ),
            ],
            if (_erreur.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_erreur,
                  style: TextStyle(fontSize: 13, color: AppColors.error)),
            ],
            const SizedBox(height: 16),
            AuthPrimaryButton(
              label: _codeEnvoye
                  ? 'Changer mon mot de passe'.tr
                  : 'Envoyer le code'.tr,
              isLoading: _chargement,
              onTap: () {
                if (_chargement) return;
                _codeEnvoye ? _valider() : _envoyer();
              },
            ),
            if (_codeEnvoye)
              Center(
                child: TextButton(
                  onPressed: _chargement ? null : _envoyer,
                  child: Text('Renvoyer le code'.tr,
                      style: TextStyle(color: AppColors.lien)),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Bouton avec bordure dégradée rose/violet ──────────────────────────────────
class _GradientBorderButton extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;

  const _GradientBorderButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: AppColors.gradientPink,
        ),
        child: Padding(
          padding: const EdgeInsets.all(1.5), // épaisseur de la bordure
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  icon,
                  style: TextStyle(
                    fontSize: 20,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
