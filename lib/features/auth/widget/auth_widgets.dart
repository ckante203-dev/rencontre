import 'package:flutter/material.dart';
import 'package:rencontre/core/theme/app_theme.dart';

// ─── INPUT FIELD ────────────────────────────────────────────────

class AuthInputField extends StatelessWidget {
  final String label;
  final String hint;
  final String icon;
  final TextEditingController controller;
  final bool isPassword;
  final bool showPassword;
  final VoidCallback? onTogglePassword;
  final TextInputType keyboardType;
  final Function(String)? onChanged;
  final bool hasError;
  final bool isSuccess;
  final String? suffixText;

  const AuthInputField({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    this.isPassword = false,
    this.showPassword = false,
    this.onTogglePassword,
    this.keyboardType = TextInputType.text,
    this.onChanged,
    this.hasError = false,
    this.isSuccess = false,
    this.suffixText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: AppColors.textMuted, letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: hasError ? [
              BoxShadow(color: AppColors.error.withOpacity(0.15), blurRadius: 8, spreadRadius: 1),
            ] : isSuccess ? [
              BoxShadow(color: AppColors.online.withOpacity(0.1), blurRadius: 8, spreadRadius: 1),
            ] : null,
          ),
          child: TextField(
            controller: controller,
            obscureText: isPassword && !showPassword,
            keyboardType: keyboardType,
            style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 14, right: 8),
                child: Text(icon, style: const TextStyle(fontSize: 18)),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 44),
              suffixIcon: isPassword
                ? GestureDetector(
                    onTap: onTogglePassword,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Text(showPassword ? '🙈' : '👁',
                        style: const TextStyle(fontSize: 18)),
                    ),
                  )
                : suffixText != null
                  ? Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Text(suffixText!,
                        style: const TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w600)),
                    )
                  : null,
              suffixIconConstraints: const BoxConstraints(minHeight: 0),
              filled: true,
              fillColor: AppColors.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: hasError ? AppColors.error
                    : isSuccess ? AppColors.online
                    : AppColors.border,
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: hasError ? AppColors.error : AppColors.accent,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── PRIMARY BUTTON ─────────────────────────────────────────────

class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isLoading;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          gradient: isLoading ? null : AppColors.gradientPink,
          color: isLoading ? AppColors.surface2 : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isLoading ? null : [
            BoxShadow(
              color: AppColors.accent.withOpacity(0.3),
              blurRadius: 20, offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: isLoading
            ? const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Text(label,
                style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700,
                  color: Colors.white, letterSpacing: 0.3,
                )),
        ),
      ),
    );
  }
}

// ─── SOCIAL BUTTON ──────────────────────────────────────────────

class AuthSocialButton extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;

  const AuthSocialButton({
    super.key,
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
        height: 50,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Text(label,
              style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              )),
          ],
        ),
      ),
    );
  }
}

// ─── DIVIDER ────────────────────────────────────────────────────

class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: AppColors.border)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('ou', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ),
        Expanded(child: Container(height: 1, color: AppColors.border)),
      ],
    );
  }
}

// ─── ERROR MESSAGE ──────────────────────────────────────────────

class AuthErrorMessage extends StatelessWidget {
  final String message;
  const AuthErrorMessage({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
              style: const TextStyle(
                fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w500,
              )),
          ),
        ],
      ),
    );
  }
}

// ─── PASSWORD STRENGTH BAR ──────────────────────────────────────

class PasswordStrengthBar extends StatelessWidget {
  final int strength; // 0-4
  final Color color;
  final String label;

  const PasswordStrengthBar({
    super.key,
    required this.strength,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (i) => Expanded(
            child: Container(
              height: 3,
              margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
              decoration: BoxDecoration(
                color: i < strength ? color : AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          )),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
        ],
      ],
    );
  }
}
