import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/auth/controller/auth_controller.dart';
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
    // ✅ FIX : vider les champs à chaque ouverture
    // évite le conflit avec SignupScreen qui partage les mêmes controllers
    final ctrl = Get.find<AuthController>();
    ctrl.emailController.clear();
    ctrl.passwordController.clear();
    ctrl.clearError();
    ctrl.showPassword.value = false;
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
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => Get.back(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(Icons.arrow_back_ios_rounded,
                        size: 18, color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(height: 28),

                ShaderMask(
                  shaderCallback: (b) => AppColors.gradientPink.createShader(b),
                  child: const Text('Content de te\nrevoir 👋',
                      style: TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.2,
                      )),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Connecte-toi pour retrouver tes matchs',
                  style: TextStyle(fontSize: 14, color: AppColors.textMuted),
                ),
                const SizedBox(height: 32),

                // Email
                AuthInputField(
                  label: 'Email',
                  hint: 'ton@email.com',
                  icon: '✉️',
                  controller: ctrl.emailController,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => ctrl.clearError(),
                ),
                const SizedBox(height: 14),

                // Mot de passe
                // ✅ FIX : Obx correct — showPassword est bien un RxBool
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

                // Mot de passe oublié
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => _showForgotPassword(context, ctrl),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('Mot de passe oublié ?',
                          style: TextStyle(
                              fontSize: 13,
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),

                // Erreur
                Obx(() => AuthErrorMessage(message: ctrl.errorMessage.value)),
                const SizedBox(height: 16),

                // Bouton connexion
                Obx(() => AuthPrimaryButton(
                      label: 'Se connecter →',
                      onTap: ctrl.signInWithEmail,
                      isLoading: ctrl.isLoading.value,
                    )),
                const SizedBox(height: 20),

                const AuthDivider(),
                const SizedBox(height: 20),

                AuthSocialButton(
                  icon: 'G',
                  label: 'Continuer avec Google',
                  onTap: ctrl.signInWithGoogle,
                ),
                const SizedBox(height: 10),
                AuthSocialButton(
                  icon: '📱',
                  label: 'Continuer avec le téléphone',
                  onTap: () => Get.toNamed('/login/phone'),
                ),
                const SizedBox(height: 28),

                GestureDetector(
                  onTap: () => Get.offNamed('/signup'),
                  child: Center(
                    child: RichText(
                      text: const TextSpan(
                        text: 'Pas encore de compte ? ',
                        style:
                            TextStyle(fontSize: 14, color: AppColors.textMuted),
                        children: [
                          TextSpan(
                            text: 'S\'inscrire',
                            style: TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showForgotPassword(BuildContext context, AuthController ctrl) {
    // ✅ FIX : TextEditingController local pour éviter conflit avec emailController
    final forgotEmailCtrl = TextEditingController(
      text: ctrl.emailController.text,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            const Text('Mot de passe oublié ?',
                style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            const Text('On t\'envoie un lien de réinitialisation par email.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 20),
            // ✅ FIX : controller local — pas de Obx ici
            AuthInputField(
              label: 'Email',
              hint: 'ton@email.com',
              icon: '✉️',
              controller: forgotEmailCtrl,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            // ✅ FIX : pas de Obx dans le bottomSheet — bouton simple
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
