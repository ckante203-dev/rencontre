import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/auth/controller/auth_controller.dart';
import 'package:rencontre/features/auth/widget/auth_widgets.dart';

// ✅ GetView résout le problème Obx automatiquement
class SignupScreen extends GetView<AuthController> {
  const SignupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      // ✅ Obx au niveau body - controller bien accessible via GetView
      body: Obx(() {
        if (controller.showEmailOtp.value) {
          return _EmailOtpScreen(ctrl: controller);
        }
        return _SignupForm(ctrl: controller);
      }),
    );
  }
}

// ─── FORMULAIRE INSCRIPTION ───────────────────────────────────────

class _SignupForm extends StatelessWidget {
  final AuthController ctrl;
  const _SignupForm({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surface2, shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.arrow_back_ios_rounded,
                    size: 18, color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: 28),

              // Header
              ShaderMask(
                shaderCallback: (b) => AppColors.gradientPink.createShader(b),
                child: const Text('Crée ton\ncompte 🚀',
                  style: TextStyle(fontFamily: 'Syne', fontSize: 30,
                    fontWeight: FontWeight.w900, color: Colors.white, height: 1.2)),
              ),
              const SizedBox(height: 8),
              const Text('Rejoins des milliers de personnes autour de toi',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
              const SizedBox(height: 32),

              // Prénom
              AuthInputField(
                label: 'Prénom',
                hint: 'Ton prénom',
                icon: '👤',
                controller: ctrl.nameController,
                onChanged: (_) => ctrl.clearError(),
              ),
              const SizedBox(height: 14),

              // Date de naissance
              _DateField(
                controller: ctrl.birthdateController,
                onChanged: (_) => ctrl.clearError(),
              ),
              const SizedBox(height: 14),

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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ Obx séparé juste pour le champ password
                  Obx(() => AuthInputField(
                    label: 'Mot de passe',
                    hint: 'Min. 8 caractères',
                    icon: '🔒',
                    controller: ctrl.passwordController,
                    isPassword: true,
                    showPassword: ctrl.showPassword.value,
                    onTogglePassword: () => ctrl.showPassword.toggle(),
                    onChanged: (v) {
                      ctrl.updatePasswordStrength(v);
                      ctrl.clearError();
                    },
                  )),
                  const SizedBox(height: 8),
                  // ✅ Obx séparé juste pour la barre de force
                  Obx(() {
                    final s = ctrl.passwordStrength.value;
                    if (s == 0) return const SizedBox.shrink();
                    return PasswordStrengthBar(
                      strength: s,
                      color: ctrl.strengthColor,
                      label: ctrl.strengthLabel,
                    );
                  }),
                ],
              ),
              const SizedBox(height: 16),

              // Erreur
              Obx(() => AuthErrorMessage(message: ctrl.errorMessage.value)),
              const SizedBox(height: 16),

              // Bouton inscription
              Obx(() => AuthPrimaryButton(
                label: 'Créer mon compte →',
                onTap: ctrl.signUpWithEmail,
                isLoading: ctrl.isLoading.value,
              )),
              const SizedBox(height: 20),

              const AuthDivider(),
              const SizedBox(height: 20),

              // Google
              AuthSocialButton(
                label: 'Continuer avec Google',
                icon: 'G',
                onTap: ctrl.signInWithGoogle,
              ),
              const SizedBox(height: 12),

// Téléphone retiré
              const SizedBox(height: 20),

              // Déjà un compte
              Center(
                child: GestureDetector(
                  onTap: () => Get.toNamed('/login'),
                  child: RichText(
                    text: const TextSpan(
                      text: 'Déjà un compte ? ',
                      style: TextStyle(fontSize: 14, color: AppColors.textMuted),
                      children: [TextSpan(
                        text: 'Se connecter',
                        style: TextStyle(color: AppColors.accent,
                          fontWeight: FontWeight.w700))],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'En créant un compte, tu acceptes nos Conditions\nd\'utilisation et notre Politique de confidentialité',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11,
                    color: AppColors.textMuted.withOpacity(0.6), height: 1.5),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── EMAIL OTP SCREEN ─────────────────────────────────────────────

class _EmailOtpScreen extends StatelessWidget {
  final AuthController ctrl;
  const _EmailOtpScreen({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => ctrl.showEmailOtp.value = false,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surface2, shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border)),
                child: const Icon(Icons.arrow_back_ios_rounded,
                  size: 18, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(height: 40),

            // Icône email
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.gradientPink,
                boxShadow: [BoxShadow(
                  color: AppColors.accent.withOpacity(0.4),
                  blurRadius: 24, spreadRadius: 2)],
              ),
              child: const Center(
                child: Text('📧', style: TextStyle(fontSize: 36))),
            ),
            const SizedBox(height: 28),

            ShaderMask(
              shaderCallback: (b) => AppColors.gradientPink.createShader(b),
              child: const Text('Vérifie\nton email',
                style: TextStyle(fontFamily: 'Syne', fontSize: 34,
                  fontWeight: FontWeight.w900, color: Colors.white, height: 1.1)),
            ),
            const SizedBox(height: 12),
            Text(
              'On a envoyé un code à 6 chiffres à\n${ctrl.emailController.text.trim()}',
              style: const TextStyle(fontSize: 14,
                color: AppColors.textMuted, height: 1.6),
            ),
            const SizedBox(height: 40),

            // 6 cases OTP
            _OtpEmailInput(controller: ctrl.emailOtpController),
            const SizedBox(height: 16),

            Obx(() => AuthErrorMessage(message: ctrl.errorMessage.value)),
            const SizedBox(height: 24),

            Obx(() => AuthPrimaryButton(
              label: 'Confirmer mon compte →',
              onTap: ctrl.verifyEmailOtp,
              isLoading: ctrl.isLoading.value,
            )),
            const SizedBox(height: 24),

            // Renvoyer
            Center(
              child: GestureDetector(
                onTap: ctrl.resendEmailOtp,
                child: RichText(
                  text: const TextSpan(
                    text: 'Pas reçu le code ? ',
                    style: TextStyle(fontSize: 14, color: AppColors.textMuted),
                    children: [TextSpan(
                      text: 'Renvoyer',
                      style: TextStyle(color: AppColors.accent,
                        fontWeight: FontWeight.w700, fontSize: 14))],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text('Vérifie aussi tes spams 🗂️',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
            const SizedBox(height: 32),
          ],
        ),
        ),
      ),
    );
  }
}

// ─── OTP EMAIL INPUT (6 cases) ────────────────────────────────────

class _OtpEmailInput extends StatefulWidget {
  final TextEditingController controller;
  const _OtpEmailInput({required this.controller});

  @override
  State<_OtpEmailInput> createState() => _OtpEmailInputState();
}

class _OtpEmailInputState extends State<_OtpEmailInput> {
  final List<TextEditingController> _ctrls =
    List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());

  @override
  void dispose() {
    for (var c in _ctrls) c.dispose();
    for (var f in _nodes) f.dispose();
    super.dispose();
  }

  void _onChanged(int i, String v) {
    if (v.length == 1 && i < 5) _nodes[i + 1].requestFocus();
    else if (v.isEmpty && i > 0) _nodes[i - 1].requestFocus();
    widget.controller.text = _ctrls.map((c) => c.text).join();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(6, (i) => SizedBox(
        width: 48,
        child: TextField(
          controller: _ctrls[i], focusNode: _nodes[i],
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800,
            color: AppColors.textPrimary),
          decoration: InputDecoration(
            counterText: '',
            filled: true, fillColor: AppColors.surface2,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.accent, width: 2.5)),
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onChanged: (v) => _onChanged(i, v),
        ),
      )),
    );
  }
}

// ─── DATE FIELD avec formatage automatique JJ/MM/AAAA ─────────────

class _DateField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  const _DateField({required this.controller, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('DATE DE NAISSANCE',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            color: AppColors.textMuted, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 16),
                child: Text('🎂', style: TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    _DateInputFormatter(),
                  ],
                  style: const TextStyle(fontSize: 15,
                    color: AppColors.textPrimary, letterSpacing: 1),
                  decoration: const InputDecoration(
                    hintText: 'JJ / MM / AAAA',
                    hintStyle: TextStyle(color: AppColors.textMuted),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 16),
                  ),
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue next) {
    final digits = next.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buf = StringBuffer();
    for (int i = 0; i < digits.length && i < 8; i++) {
      if (i == 2 || i == 4) buf.write('/');
      buf.write(digits[i]);
    }
    final str = buf.toString();
    return TextEditingValue(
      text: str,
      selection: TextSelection.collapsed(offset: str.length),
    );
  }
}