// lib/features/auth/view/signup_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/auth/controller/auth_controller.dart';
import 'package:rencontre/features/auth/view/cgu_screen.dart';
import 'package:rencontre/features/auth/widget/auth_widgets.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  @override
  void initState() {
    super.initState();
    final ctrl = Get.find<AuthController>();
    ctrl.nameController.clear();
    ctrl.usernameController.clear();
    ctrl.birthdateController.clear();
    ctrl.emailController.clear();
    ctrl.passwordController.clear();
    ctrl.confirmPasswordController.clear();
    ctrl.phoneController.clear();
    // ✅ Les .obs doivent être modifiés APRÈS le build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ctrl.clearError();
      ctrl.showEmailOtp.value = false;
      ctrl.passwordStrength.value = 0;
      ctrl.usernameAvailable.value = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AuthController>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _SignupForm(ctrl: ctrl),
    );
  }
}

// ─── FORMULAIRE INSCRIPTION ───────────────────────────────────────

class _SignupForm extends StatelessWidget {
  final AuthController ctrl;
  const _SignupForm({required this.ctrl});

  // ✅ Ouvrir les CGU
  Future<void> _openCgu(BuildContext context) async {
    await Get.to(
      () => const CguScreen(showAcceptButton: false),
      transition: Transition.cupertino,
    );
  }

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
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Icon(Icons.arrow_back_ios_rounded,
                      size: 18, color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: 28),

              ShaderMask(
                shaderCallback: (b) => AppColors.gradientPink.createShader(b),
                child: const Text('Crée ton\ncompte 🚀',
                    style: TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.2)),
              ),
              const SizedBox(height: 8),
              Text('Rejoins des milliers de personnes autour de toi',
                  style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
              const SizedBox(height: 32),

              // ── Prénom ──────────────────────────────────────
              AuthInputField(
                label: 'Prénom',
                hint: 'Ton prénom',
                icon: '👤',
                controller: ctrl.nameController,
                onChanged: (_) => ctrl.clearError(),
              ),
              const SizedBox(height: 14),

              // ── Nom d'utilisateur ────────────────────────────
              _UsernameField(ctrl: ctrl),
              const SizedBox(height: 14),

              // ── Date de naissance ───────────────────────────
              _DateField(
                controller: ctrl.birthdateController,
                onChanged: (_) => ctrl.clearError(),
              ),
              const SizedBox(height: 14),

              // ── Email ───────────────────────────────────────
              AuthInputField(
                label: 'Email',
                hint: 'ton@email.com',
                icon: '✉️',
                controller: ctrl.emailController,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => ctrl.clearError(),
              ),
              const SizedBox(height: 14),

              // ── Mot de passe ────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  const SizedBox(height: 6),
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
              const SizedBox(height: 14),

              // ── Confirmer mot de passe ──────────────────────
              _ConfirmPasswordField(ctrl: ctrl),
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

              AuthSocialButton(
                label: 'Continuer avec Google',
                icon: 'G',
                onTap: ctrl.signInWithGoogle,
              ),
              const SizedBox(height: 20),

              Center(
                child: GestureDetector(
                  onTap: () => Get.toNamed('/login'),
                  child: RichText(
                    text: TextSpan(
                      text: 'Déjà un compte ? ',
                      style:
                          TextStyle(fontSize: 14, color: AppColors.textMuted),
                      children: [
                        TextSpan(
                          text: 'Se connecter',
                          style: TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ✅ CGU cliquable
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    Text(
                      'En créant un compte, tu acceptes nos ',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted.withOpacity(0.7),
                          height: 1.6),
                    ),
                    GestureDetector(
                      onTap: () => _openCgu(context),
                      child: Text(
                        "Conditions d'utilisation",
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600,
                            height: 1.6,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.accent),
                      ),
                    ),
                    Text(
                      ' et notre ',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted.withOpacity(0.7),
                          height: 1.6),
                    ),
                    GestureDetector(
                      onTap: () => _openCgu(context),
                      child: Text(
                        'Politique de confidentialité',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600,
                            height: 1.6,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.accent),
                      ),
                    ),
                  ],
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

// ─── NOM D'UTILISATEUR ─────────────────────────────────────────────

class _UsernameField extends StatelessWidget {
  final AuthController ctrl;
  const _UsernameField({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthInputField(
          label: 'Nom d\'utilisateur',
          hint: 'ex: sarah_ci',
          icon: '@',
          controller: ctrl.usernameController,
          onChanged: (v) {
            ctrl.clearError();
            ctrl.usernameText.value = v;
            ctrl.checkUsernameAvailability(v);
          },
        ),
        Obx(() {
          final length = ctrl.usernameText.value.trim().length;
          final checking = ctrl.checkingUsername.value;
          final available = ctrl.usernameAvailable.value;

          if (length < 3) return const SizedBox.shrink();

          return Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: checking
                ? Text('Vérification...',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted))
                : Row(children: [
                    Icon(
                      available
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                      size: 14,
                      color: available ? AppColors.online : AppColors.error,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      available ? 'Disponible' : 'Déjà pris',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color:
                              available ? AppColors.online : AppColors.error),
                    ),
                  ]),
          );
        }),
      ],
    );
  }
}

// ─── CONFIRMER MOT DE PASSE ───────────────────────────────────────

class _ConfirmPasswordField extends StatefulWidget {
  final AuthController ctrl;
  const _ConfirmPasswordField({required this.ctrl});

  @override
  State<_ConfirmPasswordField> createState() => _ConfirmPasswordFieldState();
}

class _ConfirmPasswordFieldState extends State<_ConfirmPasswordField> {
  @override
  void initState() {
    super.initState();
    widget.ctrl.passwordController.addListener(_rebuild);
    widget.ctrl.confirmPasswordController.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    widget.ctrl.passwordController.removeListener(_rebuild);
    widget.ctrl.confirmPasswordController.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final password = widget.ctrl.passwordController.text;
    final confirm = widget.ctrl.confirmPasswordController.text;
    final hasError = confirm.isNotEmpty && confirm != password;
    final isSuccess = confirm.isNotEmpty && confirm == password;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Obx(() => AuthInputField(
              label: 'Confirmer le mot de passe',
              hint: 'Répète ton mot de passe',
              icon: '🔐',
              controller: widget.ctrl.confirmPasswordController,
              isPassword: true,
              showPassword: widget.ctrl.showConfirmPassword.value,
              onTogglePassword: () => widget.ctrl.showConfirmPassword.toggle(),
              hasError: hasError,
              isSuccess: isSuccess,
              onChanged: (_) => widget.ctrl.clearError(),
            )),
        if (confirm.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Row(children: [
              Icon(
                isSuccess ? Icons.check_circle_rounded : Icons.cancel_rounded,
                size: 14,
                color: isSuccess ? AppColors.online : AppColors.error,
              ),
              const SizedBox(width: 6),
              Text(
                isSuccess
                    ? 'Les mots de passe correspondent'
                    : 'Les mots de passe ne correspondent pas',
                style: TextStyle(
                    fontSize: 11,
                    color: isSuccess ? AppColors.online : AppColors.error,
                    fontWeight: FontWeight.w500),
              ),
            ]),
          ),
      ],
    );
  }
}

// ─── EMAIL OTP SCREEN ─────────────────────────────────────────────
// ⚠️ Plus utilisé pendant l'inscription (voir AuthController). Conservé ici
// tel quel comme base pour l'écran "Vérifier mon email" du profil, à
// réutiliser plus tard (ctrl.verifyEmailOtp / ctrl.resendEmailOtp attendent
// désormais un code à 8 chiffres — pense à passer _OtpEmailInput à 8 cases
// si tu le réutilises).

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
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: AppColors.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border)),
                  child: Icon(Icons.arrow_back_ios_rounded,
                      size: 18, color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: 40),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.gradientPink,
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.accent.withOpacity(0.4),
                        blurRadius: 24,
                        spreadRadius: 2)
                  ],
                ),
                child: const Center(
                    child: Text('📧', style: TextStyle(fontSize: 36))),
              ),
              const SizedBox(height: 28),
              ShaderMask(
                shaderCallback: (b) => AppColors.gradientPink.createShader(b),
                child: const Text('Vérifie\nton email',
                    style: TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.1)),
              ),
              const SizedBox(height: 12),
              Text(
                'On a envoyé un code à 8 chiffres à\n${ctrl.emailController.text.trim()}',
                style: TextStyle(
                    fontSize: 14, color: AppColors.textMuted, height: 1.6),
              ),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.accent.withOpacity(0.25)),
                ),
                child: Row(children: [
                  Icon(Icons.lock_rounded, size: 14, color: AppColors.accent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tu pourras valider ton email plus tard depuis ton profil.',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.accent, height: 1.4),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 32),
              _OtpEmailInput(controller: ctrl.emailOtpController),
              const SizedBox(height: 16),
              Obx(() => AuthErrorMessage(message: ctrl.errorMessage.value)),
              const SizedBox(height: 24),
              Obx(() => AuthPrimaryButton(
                    label: 'Confirmer mon email →',
                    onTap: ctrl.verifyEmailOtp,
                    isLoading: ctrl.isLoading.value,
                  )),
              const SizedBox(height: 24),
              Center(
                child: GestureDetector(
                  onTap: ctrl.resendEmailOtp,
                  child: RichText(
                    text: TextSpan(
                      text: 'Pas reçu le code ? ',
                      style:
                          TextStyle(fontSize: 14, color: AppColors.textMuted),
                      children: [
                        TextSpan(
                          text: 'Renvoyer',
                          style: TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
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

// ─── OTP EMAIL INPUT (8 cases) ────────────────────────────────────
// ⚠️ Ajusté à 8 cases pour matcher le réglage "Email OTP length" de Supabase.

class _OtpEmailInput extends StatefulWidget {
  final TextEditingController controller;
  const _OtpEmailInput({required this.controller});

  @override
  State<_OtpEmailInput> createState() => _OtpEmailInputState();
}

class _OtpEmailInputState extends State<_OtpEmailInput> {
  static const int _length = 8;
  final List<TextEditingController> _ctrls =
      List.generate(_length, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(_length, (_) => FocusNode());

  @override
  void dispose() {
    for (var c in _ctrls) c.dispose();
    for (var f in _nodes) f.dispose();
    super.dispose();
  }

  void _onChanged(int i, String v) {
    if (v.length == 1 && i < _length - 1) _nodes[i + 1].requestFocus();
    if (v.isEmpty && i > 0) _nodes[i - 1].requestFocus();
    widget.controller.text = _ctrls.map((c) => c.text).join();
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: List.generate(
        _length,
        (i) => SizedBox(
          width: 38,
          child: TextField(
            controller: _ctrls[i],
            focusNode: _nodes[i],
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 1,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: AppColors.surface2,
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border, width: 1.5)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.accent, width: 2.5)),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onChanged: (v) => _onChanged(i, v),
          ),
        ),
      ),
    );
  }
}

// ─── DATE FIELD ───────────────────────────────────────────────────

class _DateField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  const _DateField({required this.controller, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('DATE DE NAISSANCE',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 1.2)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          child: Row(children: [
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
                style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                    letterSpacing: 1),
                decoration: InputDecoration(
                  hintText: 'JJ / MM / AAAA',
                  hintStyle: TextStyle(color: AppColors.textMuted),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 16),
                ),
                onChanged: onChanged,
              ),
            ),
          ]),
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
