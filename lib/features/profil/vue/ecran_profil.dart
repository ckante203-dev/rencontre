import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/services/ouvrir_profil.dart';
import 'package:rencontre/features/amis/ecran_amis.dart';
import 'package:rencontre/features/amis/amis_controller.dart';
import 'package:rencontre/features/profil/vue/qr_zamu.dart';
import 'package:rencontre/features/profil/vue/carte_dispo.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:rencontre/features/album/ecran_album_prive.dart';
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

    return Scaffold(
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
                CarteDispo(ctrl: ctrl),
                const SizedBox(height: 14),
                _CartePremium(ctrl: ctrl),
                const SizedBox(height: 14),
                const _CarteAmis(),
                const SizedBox(height: 14),
                _CartePseudo(ctrl: ctrl),
                const SizedBox(height: 14),
                const _CarteAlbum(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      }),
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
                      itemBuilder: (_, i) => CachedNetworkImage(
                        imageUrl: photos[i],
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            _PlaceholderAvatar(ctrl: ctrl),
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
              fontSize: 80, fontWeight: FontWeight.w900, color: AppColors.textMuted.withValues(alpha: 0.5)),
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
                child: Text('${p.name}, ${p.age}',
                    style: TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary)),
              ),
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
        (nbPhotos >= 1, 'Ajoute une photo de profil'),
        (nbPhotos >= 3, 'Ajoute au moins 3 photos'),
        ((p.bio ?? '').trim().isNotEmpty, 'Écris une courte bio'),
        (ctrl.birthdate.value != null, 'Indique ta date de naissance'),
        (p.interests.isNotEmpty, 'Choisis tes intérêts (3 maximum)'),
        ((p.lookingFor ?? '').isNotEmpty, 'Dis ce que tu recherches'),
        (p.taille != null, 'Indique ta taille'),
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
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('Profil complété à $pct %',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted, size: 20),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(children: [
                    Container(height: 6, color: AppColors.surface2),
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
                Text('$conseil pour recevoir plus de likes',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
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

    return Obx(() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border)),
            child: Row(children: [
              Expanded(
                  child: _StatItem(
                      value: '${insights.matchesCount.value}',
                      label: 'Matchs')),
              _Separateur(),
              Expanded(
                  child: _StatItem(
                      value: '${insights.likersCount.value}',
                      label: 'Likes reçus',
                      onTap: ouvrirLikes)),
              _Separateur(),
              Expanded(
                  child: _StatItem(
                      value: '${insights.viewersCount.value}',
                      label: 'Vues du profil',
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
        Text(value,
            style: TextStyle(
                fontFamily: 'Syne',
                fontSize: 20,
                fontWeight: FontWeight.w900,
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
              borderRadius: BorderRadius.circular(18),
              border: premium
                  ? Border.all(color: AppColors.yellow.withOpacity(0.5))
                  : null,
            ),
            child: Row(children: [
              Icon(Icons.workspace_premium_rounded,
                  color: premium ? AppColors.yellow : AppColors.surAccent, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        premium ? 'Zamu Premium actif' : 'Passe à Zamu Premium',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: premium
                                ? AppColors.textPrimary
                                : AppColors.surAccent)),
                    const SizedBox(height: 2),
                    Text(
                        premium
                            ? 'Gérer mon abonnement'
                            : 'Vois qui t\'a liké et qui a visité ton profil',
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

  void _partager(String pseudo) {
    SharePlus.instance.share(ShareParams(
      text: 'Retrouve-moi sur Zamu 💬 : @$pseudo\n'
          'Cherche mon pseudo dans Messages 🔍\n'
          'https://play.google.com/store/apps/details?id=com.vybestyle.zamu',
    ));
  }

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
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
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
                      Text(aucun ? 'Choisis ton pseudo' : '@$pseudo',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(
                          aucun
                              ? 'Tes amis pourront te retrouver avec'
                              : 'Donne-le à tes amis pour qu\'ils te retrouvent',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Mon QR code',
                  onPressed: () => Get.bottomSheet(
                    FeuilleQrZamu(ctrl: ctrl),
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                  ),
                  icon: Icon(Icons.qr_code_2_rounded,
                      color: AppColors.textPrimary, size: 28),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: _BoutonCarte(
                    icon: Icons.edit_rounded,
                    label: aucun ? 'Choisir' : 'Modifier',
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
                      label: 'Copier',
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: '@$pseudo'));
                        Get.snackbar('Copié', '@$pseudo',
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
                      label: 'Partager',
                      degrade: true,
                      onTap: () => _partager(pseudo),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Text('Les autres peuvent me trouver avec ce pseudo',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textPrimary)),
                ),
                Switch.adaptive(
                  value: ctrl.trouvableParPseudo.value,
                  activeColor: AppColors.accent,
                  onChanged: (v) => ctrl.majReglage(
                      ctrl.trouvableParPseudo, 'trouvable_par_pseudo', v),
                ),
              ]),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          gradient: degrade ? AppColors.gradientPink : null,
          color: degrade ? null : AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: degrade ? null : Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: degrade ? AppColors.surAccent : AppColors.textPrimary),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: degrade ? AppColors.surAccent : AppColors.textPrimary)),
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
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
            Text(widget.premiereFois ? 'Choisis ton @pseudo 👋' : 'Ton @pseudo',
                style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(
                widget.premiereFois
                    ? 'Tes amis pourront te retrouver sur Zamu avec ce pseudo.\n'
                        '3 à 20 caractères : lettres, chiffres, . ou _'
                    : '3 à 20 caractères : lettres, chiffres, . ou _',
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
                      ? 'Disponible'
                      : !inchange && dispo == false
                          ? 'Déjà pris ou invalide'
                          : null,
                  helperStyle: TextStyle(
                      color:
                          dispo == true ? AppColors.online : AppColors.error),
                  filled: true,
                  fillColor: AppColors.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
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
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: _envoi
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.surAccent))
                      : const Text('Enregistrer',
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
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: demandes > 0 ? AppColors.accent : AppColors.border),
            ),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
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
                      Text(n == 0 ? 'Mes amis' : 'Mes amis ($n)',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(
                          demandes > 0
                              ? '$demandes demande${demandes > 1 ? 's' : ''} d\'ami en attente'
                              : 'Ajoute tes amis par @pseudo ou QR code',
                          style: TextStyle(
                              fontSize: 12,
                              color: demandes > 0
                                  ? AppColors.accent
                                  : AppColors.textMuted)),
                    ]),
              ),
              if (demandes > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientPink,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$demandes',
                      style: const TextStyle(
                          color: AppColors.surAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ]),
          ),
        );
      }),
    );
  }
}

// ─── ALBUM PRIVÉ ─────────────────────────────────────────────────

class _CarteAlbum extends StatelessWidget {
  const _CarteAlbum();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () => Get.to(() => const EcranMonAlbum()),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: AppColors.gradientPink,
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  const Icon(Icons.lock_rounded, color: AppColors.surAccent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mon album privé',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('Des photos visibles seulement par qui tu choisis',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
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
    }
  }

  Widget _bouton(IconData icone, String libelle, VoidCallback onTap,
          {bool fond = true}) =>
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: fond ? AppColors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.border, width: fond ? 1 : 1.5),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icone, color: AppColors.textPrimary, size: 22),
              const SizedBox(height: 4),
              Text(libelle,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        _bouton(Icons.edit_rounded, 'Modifier',
            () => Get.toNamed(AppRoutes.profilEdit),
            fond: false),
        const SizedBox(width: 10),
        _bouton(Icons.visibility_rounded, 'Aperçu', _apercu),
        const SizedBox(width: 10),
        _bouton(Icons.settings_rounded, 'Paramètres',
            () => Get.toNamed(AppRoutes.profilSettings)),
      ]),
    );
  }
}
