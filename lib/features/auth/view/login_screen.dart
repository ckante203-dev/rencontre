import 'package:flutter/material.dart';
import 'package:get/get.dart';
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

                // ── HEADER : Nom ──
                ShaderMask(
                  shaderCallback: (b) => AppColors.gradientPink.createShader(b),
                  child: const Text(
                    'Zamu',
                    style: TextStyle(
                      fontFamily: 'Syne',
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // ── Titre ──
                Text(
                  'Connexion',
                  style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Connecte-toi pour retrouver tes matchs',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF9999BB),
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 32),

                // ── Email ou nom d'utilisateur ──
                AuthInputField(
                  label: 'Email ou nom d\'utilisateur',
                  hint: 'ton@email.com ou ton pseudo',
                  icon: '✉️',
                  controller: ctrl.emailController,
                  onChanged: (_) => ctrl.clearError(),
                ),
                const SizedBox(height: 14),

                // ── Mot de passe ──
                Obx(() => AuthInputField(
                      label: 'Mot de passe',
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
                        'Mot de passe oublié ?',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.accent,
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
                      label: 'Se connecter →',
                      onTap: ctrl.signInWithEmail,
                      isLoading: ctrl.isLoading.value,
                    )),

                const SizedBox(height: 24),

                // ── Séparateur ──
                Row(
                  children: [
                    Expanded(
                        child: Container(height: 1, color: AppColors.border)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        'ou',
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
                  label: 'Continuer avec Google',
                  onTap: ctrl.signInWithGoogle,
                ),

                const SizedBox(height: 32),

                // ── Pas de compte ──
                GestureDetector(
                  onTap: () => Get.toNamed('/signup'),
                  child: Center(
                    child: RichText(
                      text: TextSpan(
                        text: 'Pas encore de compte ?  ',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF9999BB),
                        ),
                        children: [
                          TextSpan(
                            text: 'S\'inscrire',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
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
                    child: const Text(
                      "Conditions d'utilisation · Politique de confidentialité",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B6B8A),
                        height: 1.5,
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xFF6B6B8A),
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
    final forgotEmailCtrl =
        TextEditingController(text: ctrl.emailController.text);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 24),
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
              'Mot de passe oublié ?',
              style: TextStyle(
                fontFamily: 'Syne',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'On t\'envoie un lien de réinitialisation par email.',
              style: TextStyle(fontSize: 13, color: Color(0xFF9999BB)),
            ),
            const SizedBox(height: 20),
            AuthInputField(
              label: 'Email',
              hint: 'ton@email.com',
              icon: '✉️',
              controller: forgotEmailCtrl,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            AuthPrimaryButton(
              label: 'Envoyer le lien',
              onTap: () {
                ctrl.emailController.text = forgotEmailCtrl.text;
                ctrl.sendPasswordReset();
                Get.back();
              },
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
