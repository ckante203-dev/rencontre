import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
                _GrandePhoto(ctrl: ctrl),
                const SizedBox(height: 16),
                _NomStatut(ctrl: ctrl),
                const SizedBox(height: 18),
                _Completion(ctrl: ctrl),
                _Stats(),
                const SizedBox(height: 14),
                _CartePremium(ctrl: ctrl),
                const SizedBox(height: 14),
                _BoutonsLigne(ctrl: ctrl),
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
                              ? Colors.white
                              : Colors.white.withOpacity(0.35),
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
                            strokeWidth: 2, color: Colors.white),
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
          style: const TextStyle(
              fontSize: 80, fontWeight: FontWeight.w900, color: Colors.white24),
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
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Icon(icon, size: 20, color: Colors.white),
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
        (p.interests.length >= 3, 'Choisis au moins 3 intérêts'),
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
                  color: premium ? AppColors.yellow : Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(premium ? 'Zamu Premium actif' : 'Passe à Zamu Premium',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: premium
                                ? AppColors.textPrimary
                                : Colors.white)),
                    const SizedBox(height: 2),
                    Text(
                        premium
                            ? 'Gérer mon abonnement'
                            : 'Vois qui t\'a liké et qui a visité ton profil',
                        style: TextStyle(
                            fontSize: 12,
                            color: premium
                                ? AppColors.textMuted
                                : Colors.white.withOpacity(0.9))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: premium ? AppColors.textMuted : Colors.white),
            ]),
          ),
        ),
      );
    });
  }
}

// ─── BOUTONS LIGNE ───────────────────────────────────────────────

class _BoutonsLigne extends StatelessWidget {
  final ControleurProfil ctrl;
  const _BoutonsLigne({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: () => Get.toNamed(AppRoutes.profilEdit),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border, width: 1.5),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.edit_rounded,
                    color: AppColors.textPrimary, size: 22),
                const SizedBox(height: 4),
                Text('Modifier',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () => Get.toNamed(AppRoutes.profilSettings),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.settings_rounded,
                    color: AppColors.textPrimary, size: 22),
                const SizedBox(height: 4),
                Text('Paramètres',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
