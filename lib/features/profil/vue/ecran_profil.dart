import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/features/profil/vue/parrainage.dart';
import 'package:rencontre/features/profil/vue/carte_partage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/features/profil/vue/ecran_verification.dart';
import 'package:rencontre/shared/widgets/badge_verifie.dart';
import 'package:rencontre/core/services/ouvrir_profil.dart';
import 'package:rencontre/features/amis/ecran_amis.dart';
import 'package:rencontre/features/amis/amis_controller.dart';
import 'package:rencontre/features/profil/vue/qr_zamu.dart';
import 'package:rencontre/features/profil/vue/carte_dispo.dart';
import 'package:flutter/services.dart';
import 'package:rencontre/features/album/ecran_album_prive.dart';
import 'package:rencontre/features/album/album_service.dart';
import 'package:rencontre/shared/widgets/galerie_photos.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
import 'package:rencontre/features/likes/profile_insights_controller.dart';
import 'package:rencontre/features/home/view/main_navigation.dart';
import 'package:rencontre/core/utils/app_routes.dart';
import 'package:rencontre/shared/widgets/premium_badge.dart';

class EcranProfil extends StatelessWidget {
  const EcranProfil({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<ControleurProfil>();

    // L'écran commence par ma photo : barre d'état claire (heure lisible)
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Obx(() {
          if (ctrl.isLoading.value) {
            return Center(
                child: CircularProgressIndicator(color: AppColors.accent));
          }
          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () async {
              await ctrl.chargerMonProfil();
              if (Get.isRegistered<ProfileInsightsController>()) {
                await Get.find<ProfileInsightsController>().loadCounts();
              }
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  // Rangé par usage : qui je suis → modifier → mes chiffres
                  // → ce qui me met en avant → le reste
                  _GrandePhoto(ctrl: ctrl),
                  const SizedBox(height: 16),
                  _NomStatut(ctrl: ctrl),
                  const SizedBox(height: 16),
                  _BoutonsLigne(ctrl: ctrl),
                  const SizedBox(height: 16),
                  _Stats(),
                  const SizedBox(height: 14),
                  _Completion(ctrl: ctrl),
                  _CarteVerification(ctrl: ctrl),
                  CarteDispo(ctrl: ctrl),
                  const SizedBox(height: 14),
                  _CartePremium(ctrl: ctrl),
                  const SizedBox(height: 14),
                  const _CarteAmis(),
                  const SizedBox(height: 14),
                  _CartePseudo(ctrl: ctrl),
                  const SizedBox(height: 14),
                  const CarteParrainage(),
                  const SizedBox(height: 14),
                  const _CarteAlbum(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── PHOTOS (carrousel) ──────────────────────────────────────────

class _GrandePhoto extends StatefulWidget {
  final ControleurProfil ctrl;
  const _GrandePhoto({required this.ctrl});

  @override
  State<_GrandePhoto> createState() => _GrandePhotoState();
}

class _GrandePhotoState extends State<_GrandePhoto> {
  final _pageCtrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  List<String> _photos() {
    final p = widget.ctrl.monProfil.value;
    final list = <String>[];
    final principale = p?.photoUrl;
    if (principale != null && principale.isNotEmpty) list.add(principale);
    for (final u in widget.ctrl.photoUrls) {
      if (u.isNotEmpty && !list.contains(u)) list.add(u);
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.48;
    final ctrl = widget.ctrl;
    return Obx(() {
      final photos = _photos();
      if (_page >= photos.length && photos.isNotEmpty) _page = 0;
      return SizedBox(
        height: h,
        width: double.infinity,
        child: Stack(
          children: [
            Positioned.fill(
              child: photos.isEmpty
                  ? _PlaceholderAvatar(ctrl: ctrl)
                  : PageView.builder(
                      controller: _pageCtrl,
                      itemCount: photos.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => ouvrirGaleriePhotos(photos, depart: i),
                        child: CachedNetworkImage(
                          imageUrl: photos[i],
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              _PlaceholderAvatar(ctrl: ctrl),
                          memCacheWidth: 1080,
                        ),
                      ),
                    ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.35),
                        Colors.transparent,
                        AppColors.bg.withOpacity(0.3),
                        AppColors.bg.withOpacity(0.95),
                      ],
                      stops: const [0.0, 0.2, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // Indicateur de photo (barres en haut, style stories)
            if (photos.length > 1)
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: 16,
                right: 16,
                child: Row(
                  children: List.generate(
                    photos.length,
                    (i) => Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i == _page
                              ? AppColors.surMedia
                              : AppColors.surMedia.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: 14,
              right: 16,
              child: Obx(() => ctrl.isUploadingPhoto.value
                  ? Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.surMedia),
                      ),
                    )
                  : _IconBtn(
                      icon: Icons.camera_alt_rounded,
                      onTap: ctrl.changerPhoto,
                    )),
            ),
          ],
        ),
      );
    });
  }
}

class _PlaceholderAvatar extends StatelessWidget {
  final ControleurProfil ctrl;
  const _PlaceholderAvatar({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    final name = ctrl.monProfil.value?.name ?? '';
    return Container(
      color: AppColors.surface2,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
              fontSize: 80,
              fontWeight: FontWeight.w900,
              color: AppColors.textMuted.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.surMedia.withValues(alpha: 0.15)),
        ),
        child: Icon(icon, size: 20, color: AppColors.surMedia),
      ),
    );
  }
}

// ─── NOM ─────────────────────────────────────────────────────────

class _NomStatut extends StatelessWidget {
  final ControleurProfil ctrl;
  const _NomStatut({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final p = ctrl.monProfil.value;
      if (p == null) return const SizedBox();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(p.age > 0 ? '${p.name}, ${p.age}' : p.name,
                    style: TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
              ),
              if (ctrl.monProfil.value?.estVerifie == true) ...[
                const SizedBox(width: 6),
                const BadgeVerifie(size: 22),
              ],
              if (ctrl.isPremium.value) ...[
                const SizedBox(width: 6),
                const PremiumBadge(size: 20),
              ],
            ],
          ),
          if (ctrl.monUsername.value.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('@${ctrl.monUsername.value}',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
          ],
          if (p.corpsMesures.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(p.corpsMesures,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ]),
      );
    });
  }
}

// ─── COMPLÉTION DU PROFIL ────────────────────────────────────────

class _Completion extends StatelessWidget {
  final ControleurProfil ctrl;
  const _Completion({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final p = ctrl.monProfil.value;
      if (p == null) return const SizedBox();
      final nbPhotos = {
        if ((p.photoUrl ?? '').isNotEmpty) p.photoUrl!,
        ...ctrl.photoUrls.where((u) => u.isNotEmpty),
      }.length;
      // (étape manquante, conseil affiché)
      final etapes = <(bool, String)>[
        (nbPhotos >= 1, 'Ajoute une photo où l\'on voit ton visage'),
        (nbPhotos >= 3, 'Ajoute au moins 3 photos'),
        ((p.bio ?? '').trim().isNotEmpty, 'Écris une courte bio'),
        (ctrl.birthdate.value != null, 'Indique ta date de naissance'),
        (p.interests.isNotEmpty, 'Choisis tes intérêts (3 maximum)'),
        ((p.lookingFor ?? '').isNotEmpty, 'Dis ce que tu recherches'),
        (p.taille != null, 'Indique ta taille'),
        (p.estVerifie,
            'Vérifie ton profil (badge bleu ✓)'),
      ];
      final faites = etapes.where((e) => e.$1).length;
      if (faites == etapes.length) return const SizedBox();
      final pct = (faites * 100 / etapes.length).round();
      final conseil = etapes.firstWhere((e) => !e.$1).$2;

      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: GestureDetector(
          onTap: () => Get.toNamed(AppRoutes.profilEdit),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.carte,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.carteBord),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('Profil complété à @pct %'.trParams({'pct': pct.toString()}),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.surCarte)),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded,
                      color: AppColors.surCarteDiscret, size: 20),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(children: [
                    Container(height: 6, color: AppColors.carteIcone),
                    FractionallySizedBox(
                      widthFactor: pct / 100,
                      child: Container(
                        height: 6,
                        decoration:
                            BoxDecoration(gradient: AppColors.gradientPink),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                Text('@conseil pour recevoir plus de likes'.trParams({'conseil': conseil.tr}),
                    style: TextStyle(fontSize: 12, color: AppColors.surCarteDiscret)),
              ],
            ),
          ),
        ),
      );
    });
  }
}

// ─── STATS ───────────────────────────────────────────────────────

class _Stats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<ProfileInsightsController>()) {
      return const SizedBox();
    }
    final insights = Get.find<ProfileInsightsController>();
    void ouvrirLikes() {
      if (Get.isRegistered<NavigationController>()) {
        Get.find<NavigationController>().goTo(NavigationController.likesIndex);
      }
    }

    void ouvrirMessages() {
      if (Get.isRegistered<NavigationController>()) {
        Get.find<NavigationController>()
            .goTo(NavigationController.messagesIndex);
      }
    }

    return Obx(() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border)),
            child: Row(children: [
              Expanded(
                  child: _StatItem(
                      value: '${insights.matchesCount.value}',
                      label: 'Matchs'.tr,
                      onTap: ouvrirMessages)),
              _Separateur(),
              Expanded(
                  child: _StatItem(
                      value: '${insights.likersCount.value}',
                      label: 'Likes reçus'.tr,
                      onTap: ouvrirLikes)),
              _Separateur(),
              Expanded(
                  child: _StatItem(
                      value: '${insights.viewersCount.value}',
                      label: 'Vues du profil'.tr,
                      onTap: ouvrirLikes)),
            ]),
          ),
        ));
  }
}

class _Separateur extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 32, color: AppColors.border);
}

class _StatItem extends StatelessWidget {
  final String value, label;
  final VoidCallback? onTap;
  const _StatItem({required this.value, required this.label, this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(children: [
        // Chiffres : police du texte (Syne est trop large pour des nombres)
        Text(value,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ]),
    );
  }
}

// ─── CARTE PREMIUM ───────────────────────────────────────────────

class _CartePremium extends StatelessWidget {
  final ControleurProfil ctrl;
  const _CartePremium({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final premium = ctrl.isPremium.value;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GestureDetector(
          onTap: premium ? ctrl.gererAbonnement : ctrl.ouvrirPaywall,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: premium ? null : AppColors.gradientPink,
              color: premium ? AppColors.surface : null,
              borderRadius: BorderRadius.circular(16),
              border: premium
                  ? Border.all(color: AppColors.yellow.withOpacity(0.5))
                  : null,
            ),
            child: Row(children: [
              Icon(Icons.workspace_premium_rounded,
                  color: premium ? AppColors.yellow : AppColors.surAccent,
                  size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        premium ? 'Zamu Premium actif'.tr : 'Passe à Zamu Premium'.tr,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: premium
                                ? AppColors.textPrimary
                                : AppColors.surAccent)),
                    const SizedBox(height: 2),
                    Text(
                        premium
                            ? 'Gérer mon abonnement'.tr
                            : 'Vois qui t\'a liké et qui a visité ton profil'.tr,
                        style: TextStyle(
                            fontSize: 12,
                            color: premium
                                ? AppColors.textMuted
                                : AppColors.surAccent.withValues(alpha: 0.9))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: premium ? AppColors.textMuted : AppColors.surAccent),
            ]),
          ),
        ),
      );
    });
  }
}

// ─── MON @PSEUDO (façon Snapchat) ───────────────────────────────
// Le pseudo que la personne donne à ses amis pour qu'ils la retrouvent
// dans Messages (🔍). Elle peut le changer, le partager, et choisir d'être
// introuvable.

class _CartePseudo extends StatelessWidget {
  final ControleurProfil ctrl;
  const _CartePseudo({required this.ctrl});

  // Carte image (photo, @pseudo, QR) partagée avec le lien Play Store
  void _partager(String pseudo) => partagerCarteProfil(
        nom: ctrl.nomController.text.trim(),
        pseudo: pseudo,
        photoUrl: ctrl.photoUrls.isNotEmpty ? ctrl.photoUrls.first : null,
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Obx(() {
        final pseudo = ctrl.monUsername.value;
        final aucun = pseudo.isEmpty;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.carte,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.carteBord),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientPink,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text('@',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppColors.surAccent)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(aucun ? 'Choisis ton pseudo'.tr : '@$pseudo',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.surCarte)),
                      const SizedBox(height: 2),
                      Text(
                          aucun
                              ? 'Tes amis pourront te retrouver avec'.tr
                              : 'Donne-le à tes amis pour qu\'ils te retrouvent'.tr,
                          style: TextStyle(
                              fontSize: 12, color: AppColors.surCarteDiscret)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Mon QR code'.tr,
                  onPressed: () => Get.bottomSheet(
                    FeuilleQrZamu(ctrl: ctrl),
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                  ),
                  icon: Icon(Icons.qr_code_2_rounded,
                      color: AppColors.surCarte, size: 28),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: _BoutonCarte(
                    icon: Icons.edit_rounded,
                    label: aucun ? 'Choisir'.tr : 'Modifier'.tr,
                    onTap: () => Get.bottomSheet(
                      FeuillePseudo(ctrl: ctrl),
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ),
                if (!aucun) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _BoutonCarte(
                      icon: Icons.copy_rounded,
                      label: 'Copier'.tr,
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: '@$pseudo'));
                        Get.snackbar('Copié'.tr, '@$pseudo',
                            snackPosition: SnackPosition.TOP,
                            backgroundColor: AppColors.surface,
                            colorText: AppColors.textPrimary,
                            duration: const Duration(seconds: 2));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _BoutonCarte(
                      icon: Icons.share_rounded,
                      label: 'Partager'.tr,
                      degrade: true,
                      onTap: () => _partager(pseudo),
                    ),
                  ),
                ],
              ]),
              // Introuvable par pseudo : réglage dans Paramètres → Confidentialité
              if (!ctrl.trouvableParPseudo.value) ...[
                const SizedBox(height: 8),
                Text('🔒 ${'Introuvable par pseudo (Paramètres)'.tr}',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.surCarteDiscret)),
              ],
            ],
          ),
        );
      }),
    );
  }
}

class _BoutonCarte extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool degrade;
  final VoidCallback onTap;
  const _BoutonCarte(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.degrade = false});

  @override
  Widget build(BuildContext context) {
    // Thème Blanc : bouton principal blanc sur la carte noire
    final blanc = degrade && AppColors.clair;
    final texte = blanc
        ? AppColors.accent
        : degrade
            ? AppColors.surAccent
            : AppColors.surCarte;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          gradient: degrade && !blanc ? AppColors.gradientPink : null,
          color: blanc
              ? AppColors.surAccent
              : degrade
                  ? null
                  : AppColors.carteIcone,
          borderRadius: BorderRadius.circular(12),
          border: degrade || AppColors.clair
              ? null
              : Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: texte),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: texte)),
        ]),
      ),
    );
  }
}

/// Choisir / modifier son @pseudo (disponibilité vérifiée en direct).
class FeuillePseudo extends StatefulWidget {
  final ControleurProfil ctrl;

  /// Proposée au démarrage aux comptes sans pseudo (Google…).
  final bool premiereFois;
  const FeuillePseudo(
      {super.key, required this.ctrl, this.premiereFois = false});

  @override
  State<FeuillePseudo> createState() => _FeuillePseudoState();
}

class _FeuillePseudoState extends State<FeuillePseudo> {
  late final TextEditingController _champ =
      TextEditingController(text: widget.ctrl.monUsername.value);
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    // Repartir propre (pas d'état « déjà pris » d'une saisie précédente)
    widget.ctrl.usernameText.value = widget.ctrl.monUsername.value;
    widget.ctrl.usernameDispo.value = null;
  }

  @override
  void dispose() {
    _champ.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    setState(() => _envoi = true);
    final ok = await widget.ctrl.enregistrerPseudo(_champ.text);
    if (!mounted) return;
    setState(() => _envoi = false);
    if (ok) Get.back();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    return Padding(
      // Clavier déjà géré par Get.bottomSheet (sinon compté deux fois)
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
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
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(widget.premiereFois ? 'Choisis ton @pseudo 👋'.tr : 'Ton @pseudo'.tr,
                style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(
                widget.premiereFois
                    ? 'Tes amis pourront te retrouver sur Zamu avec ce pseudo.\n3 à 20 caractères : lettres, chiffres, . ou _'.tr
                    : '3 à 20 caractères : lettres, chiffres, . ou _'.tr,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 14),
            Obx(() {
              final saisi = ctrl.usernameText.value;
              final inchange = saisi == ctrl.monUsername.value;
              final dispo = ctrl.usernameDispo.value;
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
              return TextField(
                controller: _champ,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 20,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.]')),
                  TextInputFormatter.withFunction((ancien, nouveau) =>
                      nouveau.copyWith(text: nouveau.text.toLowerCase())),
                ],
                onChanged: (v) {
                  ctrl.usernameText.value = v;
                  ctrl.verifierUsername(v);
                },
                onSubmitted: (_) => _valider(),
                decoration: InputDecoration(
                  prefixText: '@ ',
                  prefixStyle:
                      TextStyle(color: AppColors.textMuted, fontSize: 16),
                  hintText: 'ton_pseudo',
                  hintStyle: TextStyle(color: AppColors.textMuted),
                  suffixIcon: suffix,
                  helperText: !inchange && dispo == true
                      ? 'Disponible'.tr
                      : !inchange && dispo == false
                          ? 'Déjà pris ou invalide'.tr
                          : null,
                  helperStyle: TextStyle(
                      color:
                          dispo == true ? AppColors.online : AppColors.error),
                  filled: true,
                  fillColor: AppColors.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              );
            }),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _envoi ? null : _valider,
              child: Container(
                width: double.infinity,
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppColors.gradientPink,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: _envoi
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.surAccent))
                      :  Text('Enregistrer'.tr,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.surAccent)),
                ),
              ),
            ),
          ],
        )),
      ),
    );
  }
}

// ─── MES AMIS ─────────────────────────────────────────────────────

class _CarteAmis extends StatelessWidget {
  const _CarteAmis();

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<AmisController>()) return const SizedBox.shrink();
    final ctrl = AmisController.to;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Obx(() {
        final n = ctrl.amis.length;
        final demandes = ctrl.nbDemandes;
        return GestureDetector(
          onTap: () => Get.to(() => EcranAmis(ouvrirDemandes: demandes > 0)),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.carte,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: demandes > 0 ? AppColors.lien : AppColors.carteBord),
            ),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.carteIcone,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                    child: Text('👥', style: TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n == 0 ? 'Mes amis'.tr : 'Mes amis (@n)'.trParams({'n': n.toString()}),
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.surCarte)),
                      const SizedBox(height: 2),
                      Text(
                          demandes > 0
                              ? '@demandes demande@p d\'ami en attente'.trParams({'demandes': demandes.toString(), 'p': (demandes > 1 ? 's' : '').toString()})
                              : 'Ajoute tes amis par @pseudo ou QR code'.tr,
                          style: TextStyle(
                              fontSize: 12,
                              color: demandes > 0
                                  ? AppColors.lien
                                  : AppColors.surCarteDiscret)),
                    ]),
              ),
              if (demandes > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: AppColors.pastille,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$demandes',
                      style: const TextStyle(
                          color: AppColors.surAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ),
              Icon(Icons.chevron_right_rounded, color: AppColors.surCarteDiscret),
            ]),
          ),
        );
      }),
    );
  }
}

// ─── VÉRIFICATION PAR SELFIE ─────────────────────────────────────

class _CarteVerification extends StatefulWidget {
  final ControleurProfil ctrl;
  const _CarteVerification({required this.ctrl});

  @override
  State<_CarteVerification> createState() => _CarteVerificationState();
}

class _CarteVerificationState extends State<_CarteVerification> {
  String? _statut; // en_attente / validee / refusee

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final d = await derniereVerification();
    if (mounted) setState(() => _statut = d?['statut'] as String?);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Déjà vérifié : le badge à côté du nom suffit
      if (widget.ctrl.monProfil.value?.estVerifie == true) {
        return const SizedBox.shrink();
      }
      final attente = _statut == 'en_attente';
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: GestureDetector(
          onTap: () async {
            await Get.to(() => const EcranVerification());
            _charger();
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.carte,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.carteBord),
            ),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.carteIcone,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                    child: attente
                        ? Icon(Icons.hourglass_top_rounded,
                            size: 20, color: AppColors.surCarte)
                        : const BadgeVerifie(size: 22)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(attente ? 'Vérification en cours'.tr : 'Fais vérifier ton profil'.tr,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.surCarte)),
                    const SizedBox(height: 2),
                    Text(
                        attente
                            ? 'L\'équipe compare ton selfie à tes photos'.tr
                            : 'Un selfie et tu as le badge bleu ✓'.tr,
                        style: TextStyle(
                            fontSize: 12, color: AppColors.surCarteDiscret)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.surCarteDiscret),
            ]),
          ),
        ),
      );
    });
  }
}

// ─── ALBUM PRIVÉ ─────────────────────────────────────────────────

class _CarteAlbum extends StatefulWidget {
  const _CarteAlbum();

  @override
  State<_CarteAlbum> createState() => _CarteAlbumState();
}

class _CarteAlbumState extends State<_CarteAlbum> {
  int? _nombre;

  @override
  void initState() {
    super.initState();
    _compter();
  }

  Future<void> _compter() async {
    final n = await AlbumService.nombreMesPhotos();
    if (mounted) setState(() => _nombre = n);
  }

  @override
  Widget build(BuildContext context) {
    final n = _nombre;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () async {
          await Get.to(() => const EcranMonAlbum());
          _compter();
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.carte,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.carteBord),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: AppColors.gradientPink,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.lock_rounded,
                  color: AppColors.surAccent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      n == null || n == 0
                          ? 'Mon album privé'.tr
                          : '${'Mon album privé'.tr} · $n/${AlbumService.maxPhotos}',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.surCarte)),
                  const SizedBox(height: 2),
                  Text(
                      n == 0
                          ? 'Des photos visibles seulement par qui tu choisis'.tr
                          : "Ouvre-le à quelqu'un depuis une conversation (➕ → Album)".tr,
                      style:
                          TextStyle(fontSize: 12, color: AppColors.surCarteDiscret)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.surCarteDiscret),
          ]),
        ),
      ),
    );
  }
}

// ─── BOUTONS LIGNE ───────────────────────────────────────────────

class _BoutonsLigne extends StatelessWidget {
  final ControleurProfil ctrl;
  const _BoutonsLigne({required this.ctrl});

  /// Mon profil tel que les autres le voient
  static Future<void> _apercu() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', uid)
          .single();
      Get.toNamed('/profile/view', arguments: profilComplet(row));
    } catch (e) {
      debugPrint('aperçu : $e');
      Get.snackbar('Aperçu'.tr, 'Impossible de charger ton profil, réessaie'.tr,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
    }
  }

  Widget _bouton(IconData icone, String libelle, VoidCallback onTap,
          {bool principal = false}) =>
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          // Même style que les cartes : noir à texte blanc en thème Blanc,
          // surface sobre bordée dans les thèmes sombres.
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: principal ? AppColors.carte : AppColors.surface2,
              borderRadius: BorderRadius.circular(16),
              border: principal && !AppColors.clair
                  ? Border.all(color: AppColors.carteBord)
                  : null,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icone,
                  color: principal ? AppColors.surCarte : AppColors.textPrimary,
                  size: 22),
              const SizedBox(height: 4),
              Text(libelle,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: principal
                          ? AppColors.surCarte
                          : AppColors.textPrimary)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        _bouton(Icons.edit_rounded, 'Modifier'.tr,
            () => Get.toNamed(AppRoutes.profilEdit),
            principal: true),
        const SizedBox(width: 10),
        _bouton(Icons.visibility_rounded, 'Aperçu'.tr, _apercu,
            principal: true),
        const SizedBox(width: 10),
        _bouton(Icons.settings_rounded, 'Paramètres'.tr,
            () => Get.toNamed(AppRoutes.profilSettings),
            principal: true),
      ]),
    );
  }
}
