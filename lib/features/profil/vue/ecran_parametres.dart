import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';

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
            child: const Icon(Icons.arrow_back_ios_rounded,
                size: 16, color: AppColors.textPrimary),
          ),
        ),
        title: const Text('Paramètres',
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

            // ════ CONFIDENTIALITÉ ════════════════════════════════
            const _Titre('Confidentialité'),
            const SizedBox(height: 10),
            Obx(() => _Toggle(
                icon: '🎂',
                title: 'Afficher ma date de naissance',
                subtitle: 'Visible sur ton profil public',
                value: ctrl.showBirthdate.value,
                onChanged: (v) => ctrl.showBirthdate.value = v)),
            const SizedBox(height: 10),
            Obx(() => _Toggle(
                icon: '📍',
                title: 'Afficher ma distance',
                subtitle: 'Les autres voient ta distance approximative',
                value: ctrl.showDistance.value,
                onChanged: (v) => ctrl.showDistance.value = v)),
            const SizedBox(height: 10),
            Obx(() => _Toggle(
                icon: '🌍',
                title: 'Profil public',
                subtitle: 'Ton profil est visible par tous',
                value: ctrl.profilPublic.value,
                onChanged: (v) => ctrl.profilPublic.value = v)),
            const SizedBox(height: 28),

            // ════ NOTIFICATIONS & SONS ═══════════════════════════
            const _Titre('Notifications & Sons'),
            const SizedBox(height: 10),
            Obx(() => _Toggle(
                icon: '💬',
                title: 'Messages',
                subtitle: 'Notifier à chaque nouveau message',
                value: ctrl.notifMessages.value,
                onChanged: (v) => ctrl.notifMessages.value = v)),
            const SizedBox(height: 10),
            Obx(() => _Toggle(
                icon: '📡',
                title: 'Personnes à proximité',
                subtitle: 'Notifier quand quelqu\'un est proche',
                value: ctrl.notifNearby.value,
                onChanged: (v) => ctrl.notifNearby.value = v)),
            const SizedBox(height: 10),
            Obx(() => _Toggle(
                icon: '📖',
                title: 'Stories',
                subtitle: 'Notifier les nouvelles stories',
                value: ctrl.notifStories.value,
                onChanged: (v) => ctrl.notifStories.value = v)),
            const SizedBox(height: 10),
            Obx(() => _Toggle(
                icon: '📢',
                title: 'Annonces',
                subtitle: 'Notifier les nouvelles annonces',
                value: ctrl.notifAnnonces.value,
                onChanged: (v) => ctrl.notifAnnonces.value = v)),
            const SizedBox(height: 10),
            Obx(() => _Toggle(
                icon: '🔔',
                title: 'Son des notifications',
                subtitle: 'Activer la sonnerie',
                value: ctrl.notifSon.value,
                onChanged: (v) => ctrl.notifSon.value = v)),
            const SizedBox(height: 28),

            // ════ THÈME ══════════════════════════════════════════
            const _Titre('Thème de l\'application'),
            const SizedBox(height: 10),
            Obx(() => _SelecteurTheme(
                selected: ctrl.selectedTheme.value, onSelected: ctrl.setTheme)),
            const SizedBox(height: 28),

            // ════ PROFILS BLOQUÉS ════════════════════════════════
            // ✅ Bouton simple → ouvre page dédiée
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
                      child: const Icon(Icons.block_rounded,
                          color: AppColors.error, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Profils bloqués',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary)),
                            const SizedBox(height: 2),
                            Text(
                              count == 0
                                  ? 'Aucun profil bloqué'
                                  : '$count profil${count > 1 ? 's' : ''} bloqué${count > 1 ? 's' : ''}',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textMuted),
                            ),
                          ]),
                    ),
                    // ✅ Badge rouge si profils bloqués
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
                    const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textMuted, size: 20),
                  ]),
                ),
              );
            }),
            const SizedBox(height: 28),

            // ════ SOUTENIR SNAPMEET ══════════════════════════════
            const _Titre('Soutenir SnapMeet'),
            const SizedBox(height: 10),
            _BlocSoutien(ctrl: ctrl),
            const SizedBox(height: 16),

            // ════ NOUS CONTACTER ═════════════════════════════════
            GestureDetector(
              onTap: ctrl.ouvrirWhatsApp,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF25D366).withOpacity(0.3)),
                ),
                child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('💬', style: TextStyle(fontSize: 20)),
                      SizedBox(width: 10),
                      Text('Nous contacter sur WhatsApp',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF25D366))),
                      SizedBox(width: 6),
                      Icon(Icons.open_in_new_rounded,
                          size: 16, color: Color(0xFF25D366)),
                    ]),
              ),
            ),
            const SizedBox(height: 32),

            // ── Bouton Sauvegarder ─────────────────────────────
            Obx(() => GestureDetector(
                  onTap:
                      ctrl.isSaving.value ? null : ctrl.sauvegarderParametres,
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
            const SizedBox(height: 12),

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
                child: const Center(
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
          ],
        ),
      ),
    );
  }

  void _dialogEmail(BuildContext context, ControleurProfil ctrl) {
    final emailCtrl = TextEditingController();
    Get.dialog(AlertDialog(
      backgroundColor: const Color(0xFF11111C),
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
            child: const Text('Annuler',
                style: TextStyle(color: Color(0xFF5A5A78)))),
        GestureDetector(
          onTap: () {
            Get.back();
            ctrl.modifierEmail(emailCtrl.text);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFFF3CAC), Color(0xFF7B2FFF)]),
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
      backgroundColor: const Color(0xFF11111C),
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
            child: const Text('Annuler',
                style: TextStyle(color: Color(0xFF5A5A78)))),
        GestureDetector(
          onTap: () {
            if (newPassCtrl.text != confirmCtrl.text) {
              Get.snackbar('Erreur', 'Les mots de passe ne correspondent pas',
                  snackPosition: SnackPosition.TOP,
                  backgroundColor: const Color(0xFF13131A),
                  colorText: Colors.white);
              return;
            }
            Get.back();
            ctrl.modifierMotDePasse(newPassCtrl.text);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFFF3CAC), Color(0xFF7B2FFF)]),
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
      hintStyle: const TextStyle(color: Color(0xFF5A5A78)),
      filled: true,
      fillColor: const Color(0xFF191926),
      suffixIcon: GestureDetector(
        onTap: toggle,
        child: Icon(
            show ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            size: 18,
            color: const Color(0xFF5A5A78)),
      ),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF252538))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF252538))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF3CAC))),
    );
  }
}

// ─── BLOC SOUTENIR ───────────────────────────────────────────────

class _BlocSoutien extends StatelessWidget {
  final ControleurProfil ctrl;
  const _BlocSoutien({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Si tu aimes SnapMeet, soutiens le projet 🙏',
            style: TextStyle(
                fontSize: 13, color: AppColors.textMuted, height: 1.5)),
        const SizedBox(height: 12),
        _TuilePaiement(
          logo: '🟡',
          nom: 'MTN Money',
          numero: '+225 05 66 83 01 95',
          couleur: const Color(0xFFFFD700),
          onCopier: () => ctrl.copierNumero('+225 05 66 83 01 95'),
        ),
        const SizedBox(height: 10),
        _TuilePaiement(
          logo: '🔵',
          nom: 'Wave',
          numero: '+225 05 66 83 01 95',
          couleur: const Color(0xFF1E90FF),
          onCopier: () => ctrl.copierNumero('+225 05 66 83 01 95'),
        ),
      ]),
    );
  }
}

class _TuilePaiement extends StatelessWidget {
  final String logo, nom, numero;
  final Color couleur;
  final VoidCallback onCopier;
  const _TuilePaiement(
      {required this.logo,
      required this.nom,
      required this.numero,
      required this.couleur,
      required this.onCopier});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: couleur.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: couleur.withOpacity(0.25)),
      ),
      child: Row(children: [
        Text(logo, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nom,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: couleur)),
            Text(numero,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
          ]),
        ),
        GestureDetector(
          onTap: onCopier,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: couleur.withOpacity(0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Copier',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: couleur)),
          ),
        ),
      ]),
    );
  }
}

// ─── SÉLECTEUR THÈME ────────────────────────────────────────────

class _SelecteurTheme extends StatelessWidget {
  final String selected;
  final void Function(String) onSelected;
  const _SelecteurTheme({required this.selected, required this.onSelected});

  static const _themes = [
    {
      'id': 'dark',
      'label': 'Sombre',
      'emoji': '🌙',
      'c1': Color(0xFF0D0D1A),
      'c2': Color(0xFF1A1A2E)
    },
    {
      'id': 'pink',
      'label': 'Rose',
      'emoji': '💗',
      'c1': Color(0xFFFF3CAC),
      'c2': Color(0xFF7B2FFF)
    },
    {
      'id': 'ocean',
      'label': 'Océan',
      'emoji': '🌊',
      'c1': Color(0xFF00B4DB),
      'c2': Color(0xFF0083B0)
    },
    {
      'id': 'sunset',
      'label': 'Sunset',
      'emoji': '🌅',
      'c1': Color(0xFFFF6B6B),
      'c2': Color(0xFFFF3CAC)
    },
    {
      'id': 'forest',
      'label': 'Forêt',
      'emoji': '🌿',
      'c1': Color(0xFF00B894),
      'c2': Color(0xFF00F5D4)
    },
    {
      'id': 'gold',
      'label': 'Or',
      'emoji': '✨',
      'c1': Color(0xFFFFD700),
      'c2': Color(0xFFFFA500)
    },
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
            final c1 = t['c1'] as Color;
            final c2 = t['c2'] as Color;
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
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline_rounded,
                size: 13, color: AppColors.textMuted),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                  'Les thèmes seront disponibles dans la prochaine mise à jour.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ),
          ]),
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
      style: const TextStyle(
          fontFamily: 'Syne',
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: AppColors.accent,
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
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(subtitle,
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted)),
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
  final Color titleColor;
  const _Tuile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap,
      this.titleColor = AppColors.textPrimary});

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
                      color: titleColor)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textMuted, size: 20),
        ]),
      ),
    );
  }
}
