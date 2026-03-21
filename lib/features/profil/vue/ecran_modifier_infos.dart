// lib/features/profil/vue/ecran_modifier_infos.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';

class EcranModifierInfos extends StatelessWidget {
  const EcranModifierInfos({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = ControleurProfil.to;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        centerTitle: true,
        leading: GestureDetector(
          onTap: () => Get.back(),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppColors.surface2,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border)),
            child: const Icon(Icons.arrow_back_ios_rounded,
                size: 16, color: AppColors.textPrimary),
          ),
        ),
        title: const Text('Modifier mes infos',
            style: TextStyle(
                fontFamily: 'Syne',
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Prénom ────────────────────────────────────────
            const _SectionLabel(icon: '👤', title: 'Prénom *'),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl.nomController,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 15),
              textCapitalization: TextCapitalization.words,
              decoration: _inputDeco('Ton prénom'),
            ),
            const SizedBox(height: 20),

            // ── Date de naissance ──────────────────────────────
            const _SectionLabel(icon: '🎂', title: 'Date de naissance'),
            const SizedBox(height: 8),
            Obx(() => GestureDetector(
                  onTap: () => ctrl.choisirDateNaissance(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      // ✅ FIX : surface au lieu de surface2 pour matcher les paramètres
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(children: [
                      const Icon(Icons.cake_rounded,
                          size: 18, color: AppColors.accent),
                      const SizedBox(width: 12),
                      Text(ctrl.birthdateLabel,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: ctrl.birthdate.value != null
                                  ? AppColors.textPrimary
                                  : AppColors.textMuted)),
                      const Spacer(),
                      const Icon(Icons.chevron_right_rounded,
                          size: 18, color: AppColors.textMuted),
                    ]),
                  ),
                )),
            const SizedBox(height: 20),

            // ── Taille & Poids ─────────────────────────────────
            Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionLabel(icon: '📏', title: 'Taille (cm)'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: ctrl.tailleController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 15),
                        decoration: _inputDeco('ex: 175'),
                      ),
                    ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionLabel(icon: '⚖️', title: 'Poids (kg)'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: ctrl.poidsController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 15),
                        decoration: _inputDeco('ex: 70'),
                      ),
                    ]),
              ),
            ]),
            const SizedBox(height: 20),

            // ── Morphologie ────────────────────────────────────
            const _SectionLabel(icon: '🧍', title: 'Morphologie'),
            const SizedBox(height: 8),
            Obx(() => _ChipRow(
                  options: ControleurProfil.morphologies,
                  selected: ctrl.selectedMorphologie.value,
                  onTap: ctrl.setMorphologie,
                )),
            const SizedBox(height: 20),

            // ── Je recherche ───────────────────────────────────
            const _SectionLabel(icon: '💞', title: 'Je recherche'),
            const SizedBox(height: 8),
            Obx(() => _ChipRow(
                  options: ControleurProfil.lookingForOptions,
                  selected: ctrl.selectedLookingFor.value,
                  onTap: ctrl.setLookingFor,
                )),
            const SizedBox(height: 20),

            // ── Lieu de rencontre ──────────────────────────────
            const _SectionLabel(icon: '📍', title: 'Lieu de rencontre préféré'),
            const SizedBox(height: 8),
            Obx(() => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ControleurProfil.lieuxRencontre.map((lieu) {
                    final isSelected = ctrl.selectedLieuRencontre.value == lieu;
                    return GestureDetector(
                      onTap: () => ctrl.setLieuRencontre(lieu),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: isSelected ? AppColors.gradientPink : null,
                          color: isSelected ? null : AppColors.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: isSelected
                                  ? Colors.transparent
                                  : AppColors.border),
                        ),
                        child: Text(lieu,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.textMuted)),
                      ),
                    );
                  }).toList(),
                )),
            const SizedBox(height: 20),

            // ── Bio ────────────────────────────────────────────
            const _SectionLabel(icon: '✍️', title: 'Ma bio'),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl.bioController,
              maxLines: 4,
              maxLength: 150,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: _inputDeco('Dis quelque chose sur toi...'),
            ),
            const SizedBox(height: 20),

            // ── Intérêts ───────────────────────────────────────
            Row(children: [
              const _SectionLabel(icon: '🎯', title: 'Mes intérêts'),
              const Spacer(),
              Obx(() => Text('${ctrl.selectedInterests.length}/10',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted))),
            ]),
            const SizedBox(height: 4),
            const Text('Appuie pour sélectionner ou retirer',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            Obx(() => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ControleurProfil.allInterests.map((item) {
                    final label = item['label']!;
                    final emoji = item['emoji']!;
                    final isSelected = ctrl.selectedInterests.contains(label);
                    return GestureDetector(
                      onTap: () => ctrl.toggleInterest(label),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: isSelected ? AppColors.gradientPink : null,
                          // ✅ FIX : surface au lieu de surface2
                          color: isSelected ? null : AppColors.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: isSelected
                                  ? Colors.transparent
                                  : AppColors.border),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(emoji, style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text(label,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? Colors.white
                                      : AppColors.textMuted)),
                        ]),
                      ),
                    );
                  }).toList(),
                )),
            const SizedBox(height: 32),

            // ── Bouton Sauvegarder ─────────────────────────────
            Obx(() => GestureDetector(
                  onTap: ctrl.isSaving.value ? null : ctrl.sauvegarderInfos,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient:
                          ctrl.isSaving.value ? null : AppColors.gradientPink,
                      color: ctrl.isSaving.value ? AppColors.surface2 : null,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: ctrl.isSaving.value
                          ? []
                          : [
                              BoxShadow(
                                  color: AppColors.accent.withOpacity(0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6))
                            ],
                    ),
                    child: Center(
                      child: ctrl.isSaving.value
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Sauvegarder',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  // ✅ FIX : fillColor = AppColors.surface pour matcher ecran_parametres
  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.surface,
        counterStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.accent)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
}

// ─── WIDGETS ────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String icon, title;
  const _SectionLabel({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(icon, style: const TextStyle(fontSize: 14)),
      const SizedBox(width: 6),
      Text(title.toUpperCase(),
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.8)),
    ]);
  }
}

class _ChipRow extends StatelessWidget {
  final List<String> options;
  final String selected;
  final void Function(String) onTap;
  const _ChipRow(
      {required this.options, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isSelected = selected == opt;
        return GestureDetector(
          onTap: () => onTap(opt),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              gradient: isSelected ? AppColors.gradientPink : null,
              // ✅ FIX : surface au lieu de surface2
              color: isSelected ? null : AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: isSelected ? Colors.transparent : AppColors.border),
            ),
            child: Text(opt.capitalize!,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.textMuted)),
          ),
        );
      }).toList(),
    );
  }
}
