import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/features/nouveautes/ecran_nouveautes.dart';
import 'package:rencontre/features/home/view/ecran_amis_proches.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:get_storage/get_storage.dart';
import 'package:rencontre/core/theme/app_palette.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
import 'package:rencontre/features/auth/view/cgu_screen.dart';
import 'package:rencontre/features/profil/vue/signaler_bug.dart';
import 'package:rencontre/features/profil/vue/ecran_securite.dart';
import 'package:rencontre/features/profil/vue/verifier_email.dart';
import 'package:rencontre/features/home/widget/lecture_auto_stories.dart';
import 'package:rencontre/features/profil/vue/ecran_themes.dart';
import 'package:rencontre/core/i18n/traductions.dart';

/// « tout le monde » → « Tout le monde » (pas « Tout Le Monde »)
String _majuscule(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class EcranParametres extends StatelessWidget {
  const EcranParametres({super.key});

  void _choisirLangue(BuildContext context) {
    Widget choix(String code, String drapeau, String nom) => ListTile(
          leading: Text(drapeau, style: const TextStyle(fontSize: 22)),
          title: Text(nom,
              style: TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          trailing: Langue.code == code
              ? Icon(Icons.check_rounded, color: AppColors.accent)
              : null,
          onTap: () {
            Get.back();
            Langue.changer(code);
          },
        );
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final l in Langue.disponibles) choix(l.code, l.drapeau, l.nom),
          ]),
        ),
      ),
    );
  }

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
        title: Text('Paramètres'.tr,
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
            _Titre('Compte'.tr),
            const SizedBox(height: 10),
            Obx(() => _Tuile(
                  icon: '📧',
                  title: 'Modifier l\'email'.tr,
                  subtitle: ctrl.monProfil.value?.id != null
                      ? 'Modifier mon adresse email'.tr
                      : 'Email'.tr,
                  onTap: () => _dialogEmail(context, ctrl),
                )),
            // ✉️ Vérifier mon e-mail (code par e-mail, comme Snapchat)
            const TuileVerifEmail(),
            const SizedBox(height: 10),
            _Tuile(
              icon: '🔒',
              title: 'Modifier le mot de passe'.tr,
              subtitle: 'Changer ton mot de passe'.tr,
              onTap: () => _dialogPassword(context, ctrl),
            ),
            const SizedBox(height: 28),

            // ════ IDENTITÉ ══════════════════════════════════════
            _Titre('Mon identité'.tr),
            const SizedBox(height: 10),

            // ✅ Sélecteur de genre
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('♂️', style: TextStyle(fontSize: 14)),
                      SizedBox(width: 6),
                      Text('MON GENRE'.tr,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMuted,
                              letterSpacing: 0.8)),
                    ]),
                    const SizedBox(height: 12),
                    // Genre choisi à l'inscription : verrouillé (on ne
                    // peut le choisir qu'une fois s'il manque encore)
                    Obx(() {
                      final verrouille = !ctrl.estAdmin.value &&
                          ControleurProfil.genders
                              .contains(ctrl.selectedGender.value);
                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: ControleurProfil.genders
                                  .where((g) =>
                                      !verrouille ||
                                      g == ctrl.selectedGender.value)
                                  .map((genre) {
                                final isSelected =
                                    ctrl.selectedGender.value == genre;
                                return GestureDetector(
                                  onTap: verrouille
                                      ? null
                                      : () => ctrl.setGender(genre),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 160),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 9),
                                    decoration: BoxDecoration(
                                      gradient: isSelected
                                          ? AppColors.gradientPink
                                          : null,
                                      color: isSelected
                                          ? null
                                          : AppColors.surface2,
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                          color: isSelected
                                              ? Colors.transparent
                                              : AppColors.border),
                                    ),
                                    child: Text(_majuscule(genre).tr,
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: isSelected
                                                ? AppColors.surAccent
                                                : AppColors.textMuted)),
                                  ),
                                );
                              }).toList(),
                            ),
                            if (verrouille) ...[
                              const SizedBox(height: 10),
                              Row(children: [
                                Icon(Icons.lock_outline_rounded,
                                    size: 14, color: AppColors.textMuted),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                      "Choisi à l'inscription, il ne peut plus être modifié."
                                          .tr,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textMuted)),
                                ),
                              ]),
                            ],
                          ]);
                    }),
                  ]),
            ),
            const SizedBox(height: 10),

            // ✅ Je recherche (looking_for) dans les paramètres aussi
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('💞', style: TextStyle(fontSize: 14)),
                      SizedBox(width: 6),
                      Text('JE RECHERCHE'.tr,
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
                                child: Text(_majuscule(opt).tr,
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
                  ]),
            ),
            const SizedBox(height: 28),

            // ════ CONFIDENTIALITÉ ════════════════════════════════
            _Titre('Confidentialité'.tr),
            const SizedBox(height: 10),
            // ✅ Chaque interrupteur est enregistré dès qu'on le touche.
            Obx(() => _Toggle(
                icon: '🎂',
                title: 'Afficher ma date de naissance'.tr,
                subtitle: 'Visible sur ton profil public'.tr,
                value: ctrl.showBirthdate.value,
                onChanged: (v) =>
                    ctrl.majReglage(ctrl.showBirthdate, 'show_birthdate', v))),
            const SizedBox(height: 10),
            Obx(() => _Toggle(
                icon: '🔍',
                title: 'Me trouver par mon nom d\'utilisateur'.tr,
                subtitle:
                    'Les autres peuvent te chercher par @pseudo dans Messages'
                        .tr,
                value: ctrl.trouvableParPseudo.value,
                onChanged: (v) => ctrl.majReglage(
                    ctrl.trouvableParPseudo, 'trouvable_par_pseudo', v))),
            const SizedBox(height: 10),
            Obx(() => _Toggle(
                icon: '👥',
                title: 'Recevoir des demandes d\'ami'.tr,
                subtitle: ctrl.accepteDemandesAmi.value
                    ? 'Tout le monde peut t\'ajouter en ami'.tr
                    : '🔒 Compte privé : personne ne peut t\'ajouter'.tr,
                value: ctrl.accepteDemandesAmi.value,
                onChanged: (v) => ctrl.majReglage(
                    ctrl.accepteDemandesAmi, 'accepte_demandes_ami', v))),
            const SizedBox(height: 10),
            Obx(() => _Toggle(
                icon: '👁️',
                title: 'Masquer quand j\'ai lu 👑'.tr,
                subtitle:
                    'Les autres ne voient pas « Lu » sous leurs messages'.tr,
                value: ctrl.lecturesMasquees.value,
                onChanged: (v) {
                  if (v && !ControleurProfil.estPremiumMaintenant()) {
                    ctrl.ouvrirPaywall();
                    return;
                  }
                  ctrl.majReglage(
                      ctrl.lecturesMasquees, 'lectures_masquees', v);
                })),
            const SizedBox(height: 10),
            Obx(() => _Toggle(
                icon: '📍',
                title: 'Afficher ma distance'.tr,
                subtitle: 'Les autres voient à quelle distance tu es'.tr,
                value: ctrl.showDistance.value,
                onChanged: (v) =>
                    ctrl.majReglage(ctrl.showDistance, 'show_distance', v))),
            const SizedBox(height: 10),
            StatefulBuilder(
                builder: (_, setLocal) => _Toggle(
                      icon: '🔞',
                      title: 'Flouter les photos sensibles'.tr,
                      subtitle:
                          'Les photos marquées 🔞 restent floues jusqu\'à ce que tu touches'
                              .tr,
                      value: ConversationController.flouterSensibles,
                      onChanged: (v) {
                        GetStorage().write(
                            ConversationController.cleFlouterSensibles, v);
                        setLocal(() {});
                      },
                    )),
            const SizedBox(height: 10),
            // Qui voit mes stories
            _Tuile(
              icon: '⭐',
              title: 'Amis proches'.tr,
              subtitle: 'Ceux qui voient tes stories « Amis proches »'.tr,
              onTap: () => Get.to(() => const EcranAmisProches()),
            ),
            const SizedBox(height: 10),
            _Tuile(
              icon: '🚫',
              title: 'Masquer ma story à…'.tr,
              subtitle: 'Ils ne verront aucune de tes stories'.tr,
              onTap: () => Get.to(
                  () => const EcranAmisProches(liste: ListeStory.masques)),
            ),
            const SizedBox(height: 28),

            // ════ NOTIFICATIONS & SONS ═══════════════════════════
            _Titre('Notifications & Sons'.tr),
            const SizedBox(height: 10),
            Obx(() => _Toggle(
                icon: '💬',
                title: 'Messages'.tr,
                subtitle: 'Notifier à chaque nouveau message'.tr,
                value: ctrl.notifMessages.value,
                onChanged: (v) =>
                    ctrl.majReglage(ctrl.notifMessages, 'notif_messages', v))),
            const SizedBox(height: 10),
            Obx(() => _Toggle(
                icon: '🔔',
                title: 'Son des notifications'.tr,
                subtitle: 'Jouer un son à chaque notification'.tr,
                value: ctrl.notifSon.value,
                onChanged: (v) =>
                    ctrl.majReglage(ctrl.notifSon, 'notif_son', v))),
            const SizedBox(height: 10),
            Obx(() => _Toggle(
                icon: '⭐',
                title: 'Alertes de mes favoris'.tr,
                subtitle: 'En ligne, près de toi ou arrivé dans ta ville'.tr,
                value: ctrl.notifFavoris.value,
                onChanged: (v) =>
                    ctrl.majReglage(ctrl.notifFavoris, 'notif_favoris', v))),
            const SizedBox(height: 28),

            // ▶️ Lecture auto des vidéos (Découvrir) : Wi-Fi seulement par défaut
            Obx(() => _Toggle(
                icon: '▶️',
                title: 'Vidéos en lecture auto'.tr,
                subtitle: 'Aussi en données mobiles (sinon Wi-Fi seulement)'.tr,
                value: LectureAutoStories.to.aussiEnDonnees.value,
                onChanged: LectureAutoStories.to.reglerDonnees)),
            const SizedBox(height: 28),

            // ════ THÈME ══════════════════════════════════════════
            _Titre('Thème de l\'application'.tr),
            const SizedBox(height: 10),
            Obx(() {
              final p = AppPalettes.resoudre(ctrl.selectedTheme.value) ??
                  AppPalettes.defaut;
              return _Tuile(
                icon: p.emoji ?? '🎨',
                title: 'Thèmes'.tr,
                subtitle: p.label.tr,
                onTap: () => Get.to(() => const EcranThemes()),
              );
            }),
            const SizedBox(height: 28),

            // ════ LANGUE ═════════════════════════════════════════
            _Titre('parametres.langue'.tr),
            const SizedBox(height: 10),
            _Tuile(
              icon: '🌐',
              title: 'Langue · Language'.tr,
              subtitle: Langue.actuelle.nom,
              onTap: () => _choisirLangue(context),
            ),
            const SizedBox(height: 28),

            // ════ ABONNEMENT ═════════════════════════════════════
            _Titre('Abonnement'.tr),
            const SizedBox(height: 10),
            Obx(() => _Tuile(
                  icon: '👑',
                  title: 'Zamu Premium'.tr,
                  subtitle: ctrl.isPremium.value
                      ? 'Actif · gérer mon abonnement'.tr
                      : 'Découvrir les avantages Premium'.tr,
                  onTap: ctrl.isPremium.value
                      ? ctrl.gererAbonnement
                      : ctrl.ouvrirPaywall,
                )),
            const SizedBox(height: 10),
            _Tuile(
              icon: '🔄',
              title: 'Restaurer mes achats'.tr,
              subtitle: 'Après un changement de téléphone'.tr,
              onTap: ctrl.restaurerAchats,
            ),
            const SizedBox(height: 28),

            // ════ AIDE & INFORMATIONS ════════════════════════════
            _Titre('Aide & informations'.tr),
            const SizedBox(height: 10),
            _Tuile(
              icon: '🐞',
              title: 'Signaler un bug'.tr,
              subtitle: "Un souci dans l'appli ? Dis-le-nous".tr,
              onTap: ouvrirSignalerBug,
            ),
            const SizedBox(height: 10),
            _Tuile(
              icon: '✨',
              title: 'Quoi de neuf'.tr,
              subtitle: 'Les nouveautés de Zamu'.tr,
              onTap: () =>
                  Get.to(() => const EcranNouveautes(), fullscreenDialog: true),
            ),
            const SizedBox(height: 10),
            _Tuile(
              icon: '🛡️',
              title: 'Conseils de sécurité'.tr,
              subtitle: 'Rencontrer en toute confiance'.tr,
              onTap: () => Get.to(() => const EcranSecurite()),
            ),
            const SizedBox(height: 10),
            _Tuile(
              icon: '📄',
              title: 'Conditions d\'utilisation'.tr,
              subtitle: 'Les règles de Zamu'.tr,
              onTap: () => Get.to(() => const CguScreen()),
            ),
            if (ControleurProfil.urlConfidentialite.isNotEmpty) ...[
              const SizedBox(height: 10),
              _Tuile(
                icon: '🛡️',
                title: 'Politique de confidentialité'.tr,
                subtitle: 'Comment tes données sont utilisées'.tr,
                onTap: () =>
                    ctrl.ouvrirLien(ControleurProfil.urlConfidentialite),
              ),
            ],
            if (ControleurProfil.emailContact.isNotEmpty) ...[
              const SizedBox(height: 10),
              _Tuile(
                icon: '✉️',
                title: 'Nous contacter'.tr,
                subtitle: ControleurProfil.emailContact,
                onTap: ctrl.contacterSupport,
              ),
            ],
            const SizedBox(height: 28),

            // ════ PROFILS BLOQUÉS ════════════════════════════════
            _Titre('Profils bloqués'.tr),
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
                      borderRadius: BorderRadius.circular(16),
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
                            Text('Profils bloqués'.tr,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary)),
                            const SizedBox(height: 2),
                            Text(
                              count == 0
                                  ? 'Aucun profil bloqué'.tr
                                  : '@count profil@p bloqué@p2'.trParams({
                                      'count': count.toString(),
                                      'p2': (count > 1 ? 's' : '').toString(),
                                      'p': (count > 1 ? 's' : '').toString()
                                    }),
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
                                color: AppColors.surAccent)),
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
                        Text('Se déconnecter'.tr,
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
                  child: Text('Supprimer mon compte'.tr,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.error.withOpacity(0.7))),
                ),
              ),
            ),
            // Version tout en bas de la page
            Obx(() => Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        ctrl.versionApp.value.isEmpty
                            ? ''
                            : 'Zamu · version @value'.trParams(
                                {'value': ctrl.versionApp.value.toString()}),
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textMuted)),
                  ),
                )),
            const SizedBox(height: 16),
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
      title: Text('Modifier l\'email'.tr,
          style: TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              fontSize: 17)),
      content: TextField(
        controller: emailCtrl,
        keyboardType: TextInputType.emailAddress,
        style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
        decoration: _passInputDeco('Nouvel email'.tr, false, () {}),
      ),
      actions: [
        TextButton(
            onPressed: () => Get.back(),
            child: Text('Annuler'.tr,
                style: TextStyle(color: AppColors.textMuted))),
        GestureDetector(
          onTap: () {
            Get.back();
            ctrl.modifierEmail(emailCtrl.text);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              gradient:
                  LinearGradient(colors: [AppColors.accent, AppColors.accent2]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('Modifier'.tr,
                style: TextStyle(
                    color: AppColors.surAccent, fontWeight: FontWeight.w700)),
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
      title: Text('Modifier le mot de passe'.tr,
          style: TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              fontSize: 16)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Obx(() => TextField(
              controller: newPassCtrl,
              obscureText: !showNew.value,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: _passInputDeco('Nouveau mot de passe'.tr,
                  showNew.value, () => showNew.value = !showNew.value),
            )),
        const SizedBox(height: 12),
        Obx(() => TextField(
              controller: confirmCtrl,
              obscureText: !showConfirm.value,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: _passInputDeco('Confirmer'.tr, showConfirm.value,
                  () => showConfirm.value = !showConfirm.value),
            )),
      ]),
      actions: [
        TextButton(
            onPressed: () => Get.back(),
            child: Text('Annuler'.tr,
                style: TextStyle(color: AppColors.textMuted))),
        GestureDetector(
          onTap: () {
            if (newPassCtrl.text != confirmCtrl.text) {
              Get.snackbar(
                  'Erreur'.tr, 'Les mots de passe ne correspondent pas'.tr,
                  snackPosition: SnackPosition.TOP,
                  backgroundColor: AppColors.surface,
                  colorText: AppColors.textPrimary);
              return;
            }
            Get.back();
            ctrl.modifierMotDePasse(newPassCtrl.text);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              gradient:
                  LinearGradient(colors: [AppColors.accent, AppColors.accent2]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('Modifier'.tr,
                style: TextStyle(
                    color: AppColors.surAccent, fontWeight: FontWeight.w700)),
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
      fillColor: AppColors.surface2,
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
          borderRadius: BorderRadius.circular(16),
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
            borderRadius: BorderRadius.circular(16),
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
