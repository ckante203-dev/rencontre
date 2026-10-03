import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:get_storage/get_storage.dart';
import 'package:rencontre/core/theme/app_palette.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
import 'package:rencontre/features/auth/view/cgu_screen.dart';

class EcranParametres extends StatelessWidget {
  const EcranParametres({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = ControleurProfil.to;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => ctrl.chargerProfilsBloques());

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
        title: Text('Paramètres',
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
            // ════ COMPTE ════════════════════════════════════════
            const _Titre('Compte'),
            const SizedBox(height: 10),
            Obx(() => _Tuile(
                  icon: '📧',
                  title: 'Modifier l\'email',
                  subtitle: ctrl.monProfil.value?.id != null
                      ? 'Modifier mon adresse email'
                      : 'Email',
                  onTap: () => _dialogEmail(context, ctrl),
                )),
            const SizedBox(height: 10),
            _Tuile(
              icon: '🔒',
              title: 'Modifier le mot de passe',
              subtitle: 'Changer ton mot de passe',
              onTap: () => _dialogPassword(context, ctrl),
            ),
            const SizedBox(height: 28),

            // ════ IDENTITÉ ══════════════════════════════════════
            const _Titre('Mon identité'),
            const SizedBox(height: 10),

            // ✅ Sélecteur de genre
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('♂️', style: TextStyle(fontSize: 14)),
                      SizedBox(width: 6),
                      Text('MON GENRE',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMuted,
                              letterSpacing: 0.8)),
                    ]),
                    const SizedBox(height: 12),
                    Obx(() => Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ControleurProfil.genders.map((genre) {
                            final isSelected =
                                ctrl.selectedGender.value == genre;
                            return GestureDetector(
                              onTap: () => ctrl.setGender(genre),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 9),
                                decoration: BoxDecoration(
                                  gradient: isSelected
                                      ? AppColors.gradientPink
                                      : null,
                                  color: isSelected ? null : AppColors.surface2,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                      color: isSelected
                                          ? Colors.transparent
                                          : AppColors.border),
                                ),
                                child: Text(genre.capitalize!,
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
                  ]),
            ),
            const SizedBox(height: 10),

            // ✅ Je recherche (looking_for) dans les paramètres aussi
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('💞', style: TextStyle(fontSize: 14)),
                      SizedBox(width: 6),
                      Text('JE RECHERCHE',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMuted,
                              letterSpacing: 0.8)),
                    ]),
                    const SizedBox(height: 12),
                    Obx(() => Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              ControleurProfil.lookingForOptions.map((opt) {
                            final isSelected =
                                ctrl.selectedLookingFor.value == opt;
                            return GestureDetector(
                              onTap: () => ctrl.setLookingFor(opt),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 9),
                                decoration: BoxDecoration(
                                  gradient: isSelected
                                      ? AppColors.gradientPink
                                      : null,
                                  color: isSelected ? null : AppColors.surface2,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                      color: isSelected
                                          ? Colors.transparent
                                          : AppColors.border),
                                ),
                                child: Text(opt.capitalize!,
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
                  ]),
            ),
            const SizedBox(height: 28),

            // ════ CONFIDENTIALITÉ ════════════════════════════════
            const _Titre('Confidentialité'),
            const SizedBox(height: 10),
            // ✅ Chaque interrupteur est enregistré dès qu'on le touche.
            Obx(() => _Toggle(
                icon: '🎂',
                title: 'Afficher ma date de naissance',
                subtitle: 'Visible sur ton profil public',
                value: ctrl.showBirthdate.value,
                onChanged: (v) =>
                    ctrl.majReglage(ctrl.showBirthdate, 'show_birthdate', v))),
            const SizedBox(height: 10),
            Obx(() => _Toggle(
                icon: '📍',
                title: 'Afficher ma distance',
                subtitle: 'Les autres voient à quelle distance tu es',
                value: ctrl.showDistance.value,
                onChanged: (v) =>
                    ctrl.majReglage(ctrl.showDistance, 'show_distance', v))),
            const SizedBox(height: 10),
            StatefulBuilder(
                builder: (_, setLocal) => _Toggle(
                      icon: '🔞',
                      title: 'Flouter les photos sensibles',
                      subtitle:
                          'Les photos marquées 🔞 restent floues jusqu\'à ce que tu touches',
                      value: ConversationController.flouterSensibles,
                      onChanged: (v) {
                        GetStorage().write(
                            ConversationController.cleFlouterSensibles, v);
                        setLocal(() {});
                      },
                    )),
            const SizedBox(height: 28),

            // ════ NOTIFICATIONS & SONS ═══════════════════════════
            const _Titre('Notifications & Sons'),
            const SizedBox(height: 10),
            Obx(() => _Toggle(
                icon: '💬',
                title: 'Messages',
                subtitle: 'Notifier à chaque nouveau message',
                value: ctrl.notifMessages.value,
                onChanged: (v) =>
                    ctrl.majReglage(ctrl.notifMessages, 'notif_messages', v))),
            const SizedBox(height: 10),
            Obx(() => _Toggle(
                icon: '🔔',
                title: 'Son des notifications',
                subtitle: 'Jouer un son à chaque notification',
                value: ctrl.notifSon.value,
                onChanged: (v) =>
                    ctrl.majReglage(ctrl.notifSon, 'notif_son', v))),
            const SizedBox(height: 10),
            Obx(() => _Toggle(
                icon: '⭐',
                title: 'Alertes de mes favoris',
                subtitle: 'En ligne, près de toi ou arrivé dans ta ville',
                value: ctrl.notifFavoris.value,
                onChanged: (v) =>
                    ctrl.majReglage(ctrl.notifFavoris, 'notif_favoris', v))),
            const SizedBox(height: 28),

            // ════ THÈME ══════════════════════════════════════════
            const _Titre('Thème de l\'application'),
            const SizedBox(height: 10),
            Obx(() => _SelecteurTheme(
                  selected: ctrl.selectedTheme.value,
                  onSelected: ctrl.setTheme,
                )),
            const SizedBox(height: 28),

            // ════ ABONNEMENT ═════════════════════════════════════
            const _Titre('Abonnement'),
            const SizedBox(height: 10),
            Obx(() => _Tuile(
                  icon: '👑',
                  title: 'Zamu Premium',
                  subtitle: ctrl.isPremium.value
                      ? 'Actif · gérer mon abonnement'
                      : 'Découvrir les avantages Premium',
                  onTap: ctrl.isPremium.value
                      ? ctrl.gererAbonnement
                      : ctrl.ouvrirPaywall,
                )),
            const SizedBox(height: 10),
            _Tuile(
              icon: '🔄',
              title: 'Restaurer mes achats',
              subtitle: 'Après un changement de téléphone',
              onTap: ctrl.restaurerAchats,
            ),
            const SizedBox(height: 28),

            // ════ AIDE & INFORMATIONS ════════════════════════════
            const _Titre('Aide & informations'),
            const SizedBox(height: 10),
            _Tuile(
              icon: '📄',
              title: 'Conditions d\'utilisation',
              subtitle: 'Les règles de Zamu',
              onTap: () => Get.to(() => const CguScreen()),
            ),
            if (ControleurProfil.urlConfidentialite.isNotEmpty) ...[
              const SizedBox(height: 10),
              _Tuile(
                icon: '🛡️',
                title: 'Politique de confidentialité',
                subtitle: 'Comment tes données sont utilisées',
                onTap: () => ctrl.ouvrirLien(ControleurProfil.urlConfidentialite),
              ),
            ],
            if (ControleurProfil.emailContact.isNotEmpty) ...[
              const SizedBox(height: 10),
              _Tuile(
                icon: '✉️',
                title: 'Nous contacter',
                subtitle: ControleurProfil.emailContact,
                onTap: ctrl.contacterSupport,
              ),
            ],
            const SizedBox(height: 10),
            Obx(() => Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        ctrl.versionApp.value.isEmpty
                            ? ''
                            : 'Zamu · version ${ctrl.versionApp.value}',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textMuted)),
                  ),
                )),
            const SizedBox(height: 28),

            // ════ PROFILS BLOQUÉS ════════════════════════════════
            const _Titre('Profils bloqués'),
            const SizedBox(height: 10),
            Obx(() {
              final count = ctrl.blockedProfiles.length;
              return GestureDetector(
                onTap: () => Get.toNamed('/profile/blocked'),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border)),
                  child: Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.block_rounded,
                          color: AppColors.error, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Profils bloqués',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary)),
                            const SizedBox(height: 2),
                            Text(
                              count == 0
                                  ? 'Aucun profil bloqué'
                                  : '$count profil${count > 1 ? 's' : ''} bloqué${count > 1 ? 's' : ''}',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.textMuted),
                            ),
                          ]),
                    ),
                    if (count > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('$count',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Icon(Icons.chevron_right_rounded,
                        color: AppColors.textMuted, size: 20),
                  ]),
                ),
              );
            }),
            const SizedBox(height: 28),

            // ── Déconnexion ────────────────────────────────────
            GestureDetector(
              onTap: ctrl.deconnexion,
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.error.withOpacity(0.4)),
                ),
                child: Center(
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout_rounded,
                            size: 18, color: AppColors.error),
                        SizedBox(width: 8),
                        Text('Se déconnecter',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.error)),
                      ]),
                ),
              ),
            ),

            const SizedBox(height: 12),
            GestureDetector(
              onTap: ctrl.supprimerCompte,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: Text('Supprimer mon compte',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.error.withOpacity(0.7))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _dialogEmail(BuildContext context, ControleurProfil ctrl) {
    final emailCtrl = TextEditingController();
    Get.dialog(AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Modifier l\'email',
          style: TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontSize: 17)),
      content: TextField(
        controller: emailCtrl,
        keyboardType: TextInputType.emailAddress,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: _passInputDeco('Nouvel email', false, () {}),
      ),
      actions: [
        TextButton(
            onPressed: () => Get.back(),
            child: Text('Annuler',
                style: TextStyle(color: AppColors.textMuted))),
        GestureDetector(
          onTap: () {
            Get.back();
            ctrl.modifierEmail(emailCtrl.text);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [AppColors.accent, AppColors.accent2]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('Modifier',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    ));
  }

  void _dialogPassword(BuildContext context, ControleurProfil ctrl) {
    final newPassCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final showNew = false.obs;
    final showConfirm = false.obs;

    Get.dialog(AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Modifier le mot de passe',
          style: TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontSize: 16)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Obx(() => TextField(
              controller: newPassCtrl,
              obscureText: !showNew.value,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _passInputDeco('Nouveau mot de passe', showNew.value,
                  () => showNew.value = !showNew.value),
            )),
        const SizedBox(height: 12),
        Obx(() => TextField(
              controller: confirmCtrl,
              obscureText: !showConfirm.value,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _passInputDeco('Confirmer', showConfirm.value,
                  () => showConfirm.value = !showConfirm.value),
            )),
      ]),
      actions: [
        TextButton(
            onPressed: () => Get.back(),
            child: Text('Annuler',
                style: TextStyle(color: AppColors.textMuted))),
        GestureDetector(
          onTap: () {
            if (newPassCtrl.text != confirmCtrl.text) {
              Get.snackbar('Erreur', 'Les mots de passe ne correspondent pas',
                  snackPosition: SnackPosition.TOP,
                  backgroundColor: AppColors.surface,
                  colorText: Colors.white);
              return;
            }
            Get.back();
            ctrl.modifierMotDePasse(newPassCtrl.text);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [AppColors.accent, AppColors.accent2]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('Modifier',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    ));
  }

  InputDecoration _passInputDeco(String hint, bool show, VoidCallback toggle) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textMuted),
      filled: true,
      fillColor: const Color(0xFF191926),
      suffixIcon: GestureDetector(
        onTap: toggle,
        child: Icon(
            show ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            size: 18,
            color: AppColors.textMuted),
      ),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.surface2)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.surface2)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.accent)),
    );
  }
}

// ─── BLOC SOUTENIR ───────────────────────────────────────────────

// ─── SÉLECTEUR THÈME ────────────────────────────────────────────

class _SelecteurTheme extends StatelessWidget {
  final String selected;
  final void Function(String) onSelected;
  const _SelecteurTheme({required this.selected, required this.onSelected});

  // Couleurs lues dans AppPalettes : la pastille montre le vrai thème.
  static const _themes = [
    {'id': 'dark', 'label': 'Néon rose', 'emoji': '💗'},
    {'id': 'aurore', 'label': 'Aurore', 'emoji': '🌌'},
    {'id': 'lagon', 'label': 'Lagon', 'emoji': '🏝️'},
    {'id': 'sunset', 'label': 'Sunset', 'emoji': '🌅'},
    {'id': 'or_noir', 'label': 'Or noir', 'emoji': '👑'},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _themes.map((t) {
            final isSelected = selected == t['id'] as String;
            final palette = AppPalettes.all[t['id']]!;
            final c1 = palette.accent;
            final c2 = palette.accent2;
            return GestureDetector(
              onTap: () => onSelected(t['id'] as String),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [c1, c2],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 3),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                                color: c1.withOpacity(0.5), blurRadius: 10)
                          ]
                        : [],
                  ),
                  child: Center(
                    child: isSelected
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 22)
                        : Text(t['emoji'] as String,
                            style: const TextStyle(fontSize: 22)),
                  ),
                ),
                const SizedBox(height: 5),
                Text(t['label'] as String,
                    style: TextStyle(
                        fontSize: 10,
                        color: isSelected
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.normal)),
              ]),
            );
          }).toList(),
        ),
      ]),
    );
  }
}

// ─── WIDGETS PARTAGÉS ───────────────────────────────────────────

class _Titre extends StatelessWidget {
  final String text;
  const _Titre(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          fontFamily: 'Syne',
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
          letterSpacing: 0.5));
}

class _Toggle extends StatelessWidget {
  final String icon, title, subtitle;
  final bool value;
  final void Function(bool) onChanged;
  const _Toggle(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.value,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.accent,
          activeTrackColor: AppColors.accent.withOpacity(0.3),
          inactiveThumbColor: AppColors.textMuted,
          inactiveTrackColor: AppColors.surface2,
        ),
      ]),
    );
  }
}

class _Tuile extends StatelessWidget {
  final String icon, title, subtitle;
  final VoidCallback onTap;
  final Color? titleColor;
  const _Tuile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap,
      this.titleColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: titleColor ?? AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          Icon(Icons.chevron_right_rounded,
              color: AppColors.textMuted, size: 20),
        ]),
      ),
    );
  }
}
