// lib/features/profil/vue/ecran_modifier_infos.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
            child: Icon(Icons.arrow_back_ios_rounded,
                size: 16, color: AppColors.textPrimary),
          ),
        ),
        title: Text('Modifier mes infos'.tr,
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
            // ✅ NOUVEAU — Galerie de photos (défilable sur le profil public)
            Row(children: [
               _SectionLabel(icon: '🖼️', title: 'Mes photos'.tr),
              const Spacer(),
              Obx(() => Text(
                  '${ctrl.photoUrls.length}/${ControleurProfil.maxPhotos}',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted))),
            ]),
            const SizedBox(height: 4),
            Text('Maintiens et glisse pour réordonner'.tr,
                style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            const _PhotosGridEditor(),
            const SizedBox(height: 24),

            // ── Prénom ────────────────────────────────────────
             _SectionLabel(icon: '👤', title: 'Prénom *'.tr),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl.nomController,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
              textCapitalization: TextCapitalization.words,
              decoration: _inputDeco('Ton prénom'.tr),
            ),
            const SizedBox(height: 20),

            // ── Nom d'utilisateur ─────────────────────────────
             _SectionLabel(icon: '🔗', title: 'Nom d\'utilisateur'.tr),
            const SizedBox(height: 8),
            Obx(() {
              final dispo = ctrl.usernameDispo.value;
              final saisi = ctrl.usernameText.value;
              final inchange = saisi == ctrl.monUsername.value;
              Widget? suffix;
              if (ctrl.verifUsername.value) {
                suffix = Padding(
                  padding: const EdgeInsets.all(14),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.accent)),
                );
              } else if (!inchange && dispo == true) {
                suffix = Icon(Icons.check_circle_rounded,
                    color: AppColors.online, size: 20);
              } else if (!inchange && dispo == false) {
                suffix = Icon(Icons.cancel_rounded,
                    color: AppColors.error, size: 20);
              }
              String? aide;
              Color aideCouleur = AppColors.textMuted;
              if (!inchange && dispo == false) {
                aide = RegExp(r'^[a-z0-9_.]{3,20}$').hasMatch(saisi)
                    ? 'Déjà pris'
                    : '3 à 20 caractères : lettres, chiffres, . ou _';
                aideCouleur = AppColors.error;
              } else if (!inchange && dispo == true) {
                aide = 'Disponible'.tr;
                aideCouleur = AppColors.online;
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: ctrl.usernameController,
                    style:
                        TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLength: 20,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.]')),
                      TextInputFormatter.withFunction((oldV, newV) =>
                          newV.copyWith(text: newV.text.toLowerCase())),
                    ],
                    onChanged: (v) {
                      ctrl.usernameText.value = v;
                      ctrl.verifierUsername(v);
                    },
                    decoration: _inputDeco('ton_pseudo').copyWith(
                      prefixText: '@ ',
                      prefixStyle:
                          TextStyle(color: AppColors.textMuted, fontSize: 15),
                      suffixIcon: suffix,
                    ),
                  ),
                  if (aide != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(aide,
                          style: TextStyle(fontSize: 12, color: aideCouleur)),
                    ),
                ],
              );
            }),
            const SizedBox(height: 20),

            // ── Date de naissance ──────────────────────────────
             _SectionLabel(icon: '🎂', title: 'Date de naissance'.tr),
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
                      Icon(Icons.cake_rounded,
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
                      Icon(Icons.chevron_right_rounded,
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
                       _SectionLabel(icon: '📏', title: 'Taille (cm)'.tr),
                      const SizedBox(height: 8),
                      TextField(
                        controller: ctrl.tailleController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 15),
                        decoration: _inputDeco('ex: 175'.tr),
                      ),
                    ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       _SectionLabel(icon: '⚖️', title: 'Poids (kg)'.tr),
                      const SizedBox(height: 8),
                      TextField(
                        controller: ctrl.poidsController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 15),
                        decoration: _inputDeco('ex: 70'.tr),
                      ),
                    ]),
              ),
            ]),
            const SizedBox(height: 20),

            // ── Morphologie ────────────────────────────────────
             _SectionLabel(icon: '🧍', title: 'Morphologie'.tr),
            const SizedBox(height: 8),
            Obx(() => _ChipRow(
                  options: ControleurProfil.morphologies,
                  selected: ctrl.selectedMorphologie.value,
                  onTap: ctrl.setMorphologie,
                )),
            const SizedBox(height: 20),

            // ── Je recherche ───────────────────────────────────
             _SectionLabel(icon: '💞', title: 'Je recherche'.tr),
            const SizedBox(height: 8),
            Obx(() => _ChipRow(
                  options: ControleurProfil.lookingForOptions,
                  selected: ctrl.selectedLookingFor.value,
                  onTap: ctrl.setLookingFor,
                )),
            const SizedBox(height: 20),

            // ── Lieu de rencontre ──────────────────────────────
             _SectionLabel(icon: '📍', title: 'Où se rencontrer'.tr),
            const SizedBox(height: 4),
            Text('Choisis jusqu\'à 3 lieux'.tr,
                style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            const SizedBox(height: 10),
            Obx(() => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ControleurProfil.lieuxRencontre.map((lieu) {
                    final isSelected = ctrl.lieuxChoisis.contains(lieu);
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
                        child: Text(lieu.tr,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? AppColors.surAccent
                                    : AppColors.textMuted)),
                      ),
                    );
                  }).toList(),
                )),
            const SizedBox(height: 20),

            // ── Bio ────────────────────────────────────────────
             _SectionLabel(icon: '✍️', title: 'Ma bio'.tr),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl.bioController,
              maxLines: 4,
              maxLength: 150,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: _inputDeco('Dis quelque chose sur toi...'.tr),
            ),
            const SizedBox(height: 20),

            // ── Métier / Études ────────────────────────────────
             _SectionLabel(icon: '💼', title: 'Métier'.tr),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl.metierController,
              maxLength: 60,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: _inputDeco('ex: Infirmière, Commerçant, Étudiant…'.tr),
            ),
            const SizedBox(height: 8),
             _SectionLabel(icon: '🎓', title: 'Études'.tr),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl.etudesController,
              maxLength: 80,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: _inputDeco('ex: Université FHB, BTS Commerce…'.tr),
            ),
            const SizedBox(height: 12),

            // ── Langues parlées ────────────────────────────────
             _SectionLabel(icon: '🗣️', title: 'Langues parlées'.tr),
            const SizedBox(height: 10),
            Obx(() => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ControleurProfil.languesDisponibles.map((l) {
                    final choisie = ctrl.languesChoisies.contains(l);
                    return GestureDetector(
                      onTap: () => ctrl.basculerLangue(l),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: choisie ? AppColors.gradientPink : null,
                          color: choisie ? null : AppColors.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: choisie
                                  ? Colors.transparent
                                  : AppColors.border),
                        ),
                        child: Text(l.tr,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: choisie
                                    ? AppColors.surAccent
                                    : AppColors.textMuted)),
                      ),
                    );
                  }).toList(),
                )),
            const SizedBox(height: 20),

            // ── Questions façon Hinge ──────────────────────────
            Row(children: [
               _SectionLabel(icon: '💬', title: 'Mes réponses'.tr),
              const Spacer(),
              Obx(() => Text('${ctrl.questionsChoisies.length}/3',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted))),
            ]),
            const SizedBox(height: 4),
            Text('Réponds à 3 questions : ça donne envie de t\'écrire'.tr,
                style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            const SizedBox(height: 10),
            Obx(() => Column(children: [
                  for (final q in ctrl.questionsChoisies)
                    _CarteQuestion(
                      question: q['q']!,
                      reponse: q['r']!,
                      onTap: () => _editerQuestion(context, q['q']!, q['r']!),
                    ),
                  if (ctrl.questionsChoisies.length < 3)
                    GestureDetector(
                      onTap: () => _choisirQuestion(context),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_rounded,
                                  color: AppColors.textPrimary, size: 18),
                              const SizedBox(width: 6),
                              Text('Ajouter une question'.tr,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary)),
                            ]),
                      ),
                    ),
                ])),
            const SizedBox(height: 20),

            // ── Intérêts ───────────────────────────────────────
            Row(children: [
               _SectionLabel(icon: '🎯', title: 'Mes intérêts'.tr),
              const Spacer(),
              Obx(() => Text('${ctrl.selectedInterests.length}/3',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted))),
            ]),
            const SizedBox(height: 4),
            Text('Choisis jusqu\'à 3 intérêts'.tr,
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
                          Text(label.tr,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? AppColors.surAccent
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
                                  strokeWidth: 2, color: AppColors.surAccent))
                          :  Text('Sauvegarder'.tr,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.surAccent)),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  // ✅ FIX : fillColor = AppColors.surface pour matcher ecran_parametres
  InputDecoration _inputDeco(String hint) => _decoChamp(hint);
}

// ─── WIDGETS ────────────────────────────────────────────────────────

/// Style commun des champs de saisie de cet écran
InputDecoration _decoChamp(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.surface,
        counterStyle: TextStyle(color: AppColors.textMuted, fontSize: 11),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppColors.accent)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

/// Choisir une question pas encore utilisée
void _choisirQuestion(BuildContext context) {
  final ctrl = ControleurProfil.to;
  final restantes = ControleurProfil.questionsDisponibles
      .where((q) => !ctrl.questionsChoisies.any((e) => e['q'] == q))
      .toList();
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: ListView(shrinkWrap: true, children: [
          for (final q in restantes)
            ListTile(
              title: Text(q.tr,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600)),
              trailing: Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted),
              onTap: () {
                Get.back();
                _editerQuestion(context, q, '');
              },
            ),
        ]),
      ),
    ),
  );
}

/// Écrire (ou effacer) la réponse à une question
void _editerQuestion(BuildContext context, String question, String reponse) {
  final ctrl = ControleurProfil.to;
  final saisie = TextEditingController(text: reponse);
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question.tr,
              style: TextStyle(
                  fontFamily: 'Syne',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          TextField(
            controller: saisie,
            autofocus: true,
            maxLength: 200,
            maxLines: 3,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: _decoChamp('Ta réponse…'.tr),
          ),
          const SizedBox(height: 8),
          Row(children: [
            if (reponse.isNotEmpty)
              TextButton(
                onPressed: () {
                  ctrl.definirQuestion(question, '');
                  Get.back();
                },
                child: Text('Retirer'.tr,
                    style: TextStyle(color: AppColors.error)),
              ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                ctrl.definirQuestion(question, saisie.text);
                Get.back();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                decoration: BoxDecoration(
                    gradient: AppColors.gradientPink,
                    borderRadius: BorderRadius.circular(14)),
                child: Text('Valider'.tr,
                    style: const TextStyle(
                        color: AppColors.surAccent,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ],
      ),
    ),
  );
}

class _CarteQuestion extends StatelessWidget {
  final String question;
  final String reponse;
  final VoidCallback onTap;
  const _CarteQuestion(
      {required this.question, required this.reponse, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(question.tr,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(reponse,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ]),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String icon, title;
  const _SectionLabel({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(icon, style: const TextStyle(fontSize: 14)),
      const SizedBox(width: 6),
      Text(title.toUpperCase(),
          style: TextStyle(
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
            child: Text(opt.capitalize!.tr,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? AppColors.surAccent : AppColors.textMuted)),
          ),
        );
      }).toList(),
    );
  }
}

// ─── ✅ NOUVEAU — GALERIE DE PHOTOS RÉORDONNABLE ───────────────────

class _PhotosGridEditor extends StatelessWidget {
  const _PhotosGridEditor();

  @override
  Widget build(BuildContext context) {
    final ctrl = ControleurProfil.to;
    return Obx(() {
      final photos = ctrl.photoUrls;
      // ✅ Lecture synchrone de .length dans le callback Obx : c'est ce qui
      // permet à GetX de détecter la dépendance réactive et de reconstruire
      // ce widget quand photoUrls change (sinon aucune lecture n'est faite
      // avant que itemBuilder ne soit appelé plus tard, hors de portée).
      final count = photos.length;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.85,
        ),
        itemCount: ControleurProfil.maxPhotos,
        itemBuilder: (_, index) {
          if (index < count) {
            return _PhotoSlot(
              key: ValueKey(photos[index]),
              index: index,
              url: photos[index],
            );
          }
          return _AddPhotoSlot(onTap: ctrl.ajouterPhotoProfil);
        },
      );
    });
  }
}

class _PhotoSlot extends StatelessWidget {
  final int index;
  final String url;
  const _PhotoSlot({super.key, required this.index, required this.url});

  @override
  Widget build(BuildContext context) {
    final ctrl = ControleurProfil.to;

    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
          if (index == 0)
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  gradient: AppColors.gradientPink,
                  borderRadius: BorderRadius.circular(8),
                ),
                child:  Text('Principale'.tr,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.surAccent)),
              ),
            ),
          Positioned(
            top: 6,
            right: 6,
            child: GestureDetector(
              onTap: () => ctrl.supprimerPhotoProfil(index),
              child: Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                    color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded,
                    size: 16, color: AppColors.surMedia),
              ),
            ),
          ),
        ],
      ),
    );

    return DragTarget<int>(
      onWillAccept: (from) => from != null && from != index,
      onAccept: (from) => ctrl.reordonnerPhotos(from, index),
      builder: (context, candidateData, rejectedData) {
        final isTarget = candidateData.isNotEmpty;
        return LongPressDraggable<int>(
          data: index,
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(width: 140, height: 160, child: content),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: content),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: isTarget
                  ? Border.all(color: AppColors.accent, width: 2)
                  : null,
            ),
            child: content,
          ),
        );
      },
    );
  }
}

class _AddPhotoSlot extends StatelessWidget {
  final VoidCallback onTap;
  const _AddPhotoSlot({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ctrl = ControleurProfil.to;
    return Obx(() => GestureDetector(
          onTap: ctrl.isUploadingPhoto.value ? null : onTap,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Center(
              child: ctrl.isUploadingPhoto.value
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.accent))
                  : Icon(Icons.add_rounded,
                      size: 32, color: AppColors.textMuted),
            ),
          ),
        ));
  }
}
