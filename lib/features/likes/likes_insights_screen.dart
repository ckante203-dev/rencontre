import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/core/utils/app_routes.dart';
import 'package:rencontre/core/services/revenue_cat_service.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/premium/view/boost_sheet.dart';
import 'package:rencontre/features/likes/like_controller.dart';
import 'package:rencontre/features/likes/profile_insights_controller.dart';
import 'package:rencontre/shared/models/user_model.dart';

// ══════════════════════════════════════════════════════════════════
//  ONGLET ❤️ — « M'ont liké » / « M'ont vu » en grille de photos.
//  - Premium : vraies photos, like en retour (→ match) ou ✕ direct.
//  - Pas Premium : photos floutées + bouton vers le paywall.
// ══════════════════════════════════════════════════════════════════

/// Pas Premium → paywall (ou message si RevenueCat n'est pas encore prêt,
/// pour éviter un crash sur Get.find<RevenueCatService>()).
void _ouvrirPaywall() {
  if (!Get.isRegistered<RevenueCatService>()) {
    Get.snackbar(
      '🔒 Bientôt disponible',
      'L\'abonnement premium arrive très bientôt — reviens vite !',
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface,
      colorText: AppColors.textPrimary,
      duration: const Duration(seconds: 2),
    );
    return;
  }
  Get.toNamed(AppRoutes.paywall);
}

/// « à l'instant », « il y a 5 min », « il y a 3 h », « hier », « il y a 4 j »…
String _ilYa(DateTime? date) {
  if (date == null) return '';
  final d = DateTime.now().toUtc().difference(date.toUtc());
  if (d.inMinutes < 1) return 'à l\'instant';
  if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
  if (d.inHours < 24) return 'il y a ${d.inHours} h';
  if (d.inDays == 1) return 'hier';
  if (d.inDays < 7) return 'il y a ${d.inDays} j';
  if (d.inDays < 30) return 'il y a ${d.inDays ~/ 7} sem.';
  return 'il y a ${d.inDays ~/ 30} mois';
}

class LikesInsightsScreen extends StatefulWidget {
  const LikesInsightsScreen({super.key});

  @override
  State<LikesInsightsScreen> createState() => _LikesInsightsScreenState();
}

class _LikesInsightsScreenState extends State<LikesInsightsScreen> {
  bool _ongletVues = false;

  ProfileInsightsController get _ctrl {
    if (!Get.isRegistered<ProfileInsightsController>()) {
      Get.put(ProfileInsightsController(), permanent: true);
    }
    return Get.find<ProfileInsightsController>();
  }

  bool _ouverture = false;

  /// Ouvre le profil COMPLET (bio, photos, infos, distance) et permet de
  /// balayer vers les autres personnes de la liste, comme à l'Accueil.
  /// (Avant : fiche presque vide, construite avec le prénom et la photo.)
  Future<void> _ouvrirProfil(
      PersonneInsight p, List<PersonneInsight> liste) async {
    if (p.id.isEmpty || _ouverture) return;
    _ouverture = true;
    try {
      final ids = liste.map((e) => e.id).where((id) => id.isNotEmpty).toList();
      final rows = await supabase
          .from('profiles')
          .select()
          .inFilter('id', ids)
          .timeout(const Duration(seconds: 10)) as List;
      final service = SupabaseService();
      final home = Get.isRegistered<HomeController>()
          ? Get.find<HomeController>()
          : null;
      final parId = <String, UserModel>{
        for (final r in rows)
          if (r['is_suspended'] != true)
            '${r['id']}': (home?.avecDistance(service.profileToUser(r)) ??
                service.profileToUser(r)),
      };
      // Même ordre que la grille
      final profils = [
        for (final e in liste)
          if (parId[e.id] != null) parId[e.id]!
      ];
      final index = profils.indexWhere((u) => u.id == p.id);
      if (index < 0) {
        Get.snackbar('Profil indisponible',
            'Ce profil n\'existe plus ou n\'est pas disponible',
            snackPosition: SnackPosition.TOP,
            backgroundColor: AppColors.surface,
            colorText: AppColors.textPrimary);
        return;
      }
      Get.toNamed('/profile/view',
          arguments: {'profiles': profils, 'initialIndex': index});
    } catch (e) {
      debugPrint('_ouvrirProfil : $e');
    } finally {
      _ouverture = false;
    }
  }

  Future<void> _likerEnRetour(PersonneInsight p) async {
    if (!Get.isRegistered<LikeController>()) {
      Get.put(LikeController(), permanent: true);
    }
    final likes = Get.find<LikeController>();
    // toggleLike retire le like s'il existe déjà → on ne l'appelle pas.
    if (!likes.hasLiked(p.id)) {
      await likes.toggleLike(UserModel(
        id: p.id,
        name: p.name,
        age: p.age ?? 18,
        photoUrl: p.photoUrl,
        isOnline: p.enLigne,
      ));
    }
    if (likes.hasMatch(p.id)) _ctrl.retirerLiker(p.id);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Obx(() {
          final premium = ProfileInsightsController.isPremiumNow();
          final liste = _ongletVues ? ctrl.viewers : ctrl.likers;
          // Lus ici pour que Obx suive aussi ces valeurs.
          ctrl.seuilNouveau.value;
          final nouveauxLikes = ctrl.likers.where(ctrl.estNouveau).length;
          final nouvellesVues = ctrl.viewers.where(ctrl.estNouveau).length;

          return RefreshIndicator(
            onRefresh: ctrl.loadCounts,
            color: AppColors.accent,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Text(
                        'Likes',
                        style: TextStyle(
                          fontFamily: 'Syne',
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                          child: _Onglet(
                            icon: Icons.favorite_rounded,
                            label: 'M\'ont liké',
                            count: ctrl.likersCount.value,
                            nouveaux: nouveauxLikes,
                            actif: !_ongletVues,
                            onTap: () => setState(() => _ongletVues = false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Onglet(
                            icon: Icons.remove_red_eye_rounded,
                            label: 'M\'ont vu',
                            count: ctrl.viewersCount.value,
                            nouveaux: nouvellesVues,
                            actif: _ongletVues,
                            onTap: () => setState(() => _ongletVues = true),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      if (!premium && liste.isNotEmpty) ...[
                        _BanniereDeblocage(
                          count: _ongletVues
                              ? ctrl.viewersCount.value
                              : ctrl.likersCount.value,
                          vues: _ongletVues,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ]),
                  ),
                ),
                if (ctrl.isLoading.value && liste.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.accent)),
                  )
                else if (liste.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _Vide(vues: _ongletVues),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 32),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        childAspectRatio: 0.72,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final p = liste[i];
                          return _CartePersonne(
                            personne: p,
                            premium: premium,
                            nouveau: ctrl.estNouveau(p),
                            dejaLike: _ongletVues &&
                                Get.isRegistered<LikeController>() &&
                                Get.find<LikeController>().hasLiked(p.id),
                            onTap: premium
                                ? () => _ouvrirProfil(p, liste)
                                : _ouvrirPaywall,
                            onLike: premium ? () => _likerEnRetour(p) : null,
                            onPasser: premium && !_ongletVues
                                ? () => ctrl.masquer(p.id)
                                : null,
                          );
                        },
                        childCount: liste.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ─── ONGLET « M'ONT LIKÉ » / « M'ONT VU » ─────────────────────────

class _Onglet extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final int nouveaux;
  final bool actif;
  final VoidCallback onTap;

  const _Onglet({
    required this.icon,
    required this.label,
    required this.count,
    required this.nouveaux,
    required this.actif,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: actif ? AppColors.gradientPink : null,
          color: actif ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: actif ? Colors.transparent : AppColors.border),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: actif ? AppColors.surAccent : AppColors.textPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: actif ? AppColors.surAccent : AppColors.textPrimary)),
                Text(count > 99 ? '99+' : '$count',
                    style: TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: actif ? AppColors.surAccent : AppColors.textPrimary)),
              ],
            ),
          ),
          if (nouveaux > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: actif ? AppColors.surAccent : AppColors.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('+$nouveaux',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: actif ? AppColors.accent : AppColors.surAccent)),
            ),
        ]),
      ),
    );
  }
}

// ─── BANNIÈRE PREMIUM (non abonnés) ───────────────────────────────

class _BanniereDeblocage extends StatelessWidget {
  final int count;
  final bool vues;
  const _BanniereDeblocage({required this.count, required this.vues});

  @override
  Widget build(BuildContext context) {
    final qui = count > 1 ? '$count personnes' : 'Quelqu\'un';
    final texte = vues
        ? '$qui ${count > 1 ? 'ont' : 'a'} regardé ton profil'
        : '$qui ${count > 1 ? 't\'ont' : 't\'a'} liké';

    return GestureDetector(
      onTap: _ouvrirPaywall,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.gradientFull,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          const Icon(Icons.lock_open_rounded, color: AppColors.surAccent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(texte,
                    style: const TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.surAccent)),
                const SizedBox(height: 2),
                Text(
                    vues
                        ? 'Passe en Premium pour voir qui c\'est'
                        : 'Passe en Premium et matche en un geste',
                    style: const TextStyle(fontSize: 12, color: AppColors.surAccent)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surAccent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('Voir',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111111))),
          ),
        ]),
      ),
    );
  }
}

// ─── CARTE D'UNE PERSONNE ─────────────────────────────────────────

class _CartePersonne extends StatelessWidget {
  final PersonneInsight personne;
  final bool premium;
  final bool nouveau;
  final bool dejaLike;
  final VoidCallback onTap;
  final VoidCallback? onLike;
  final VoidCallback? onPasser;

  const _CartePersonne({
    required this.personne,
    required this.premium,
    required this.nouveau,
    required this.dejaLike,
    required this.onTap,
    this.onLike,
    this.onPasser,
  });

  Widget _fond() => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.accent.withOpacity(0.55),
              AppColors.accent2.withOpacity(0.55),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Icon(Icons.person_rounded,
            size: 64, color: AppColors.surMedia.withValues(alpha: 0.5)),
      );

  @override
  Widget build(BuildContext context) {
    final p = personne;
    final photo = p.photoUrl;
    Widget image = photo != null && photo.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: photo,
            fit: BoxFit.cover,
            memCacheWidth: 500,
            fadeInDuration: const Duration(milliseconds: 200),
            placeholder: (_, __) => Container(color: AppColors.surface2),
            errorWidget: (_, __, ___) => _fond(),
          )
        : _fond();
    if (!premium) {
      image = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: image,
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(fit: StackFit.expand, children: [
          image,
          // Dégradé sombre en bas pour lire le texte sur la photo
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [Color(0xCC000000), Color(0x00000000)],
              ),
            ),
          ),
          if (nouveau)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  gradient: AppColors.gradientPink,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('Nouveau',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.surAccent)),
              ),
            ),
          if (!premium)
            // Cadenas sur pastille sombre : lisible même sur une photo claire
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                    color: Colors.black38, shape: BoxShape.circle),
                child: const Icon(Icons.lock_rounded,
                    color: AppColors.surMedia, size: 26),
              ),
            ),
          Positioned(
            left: 10,
            right: 10,
            bottom: onLike != null ? 50 : 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (premium)
                  Row(children: [
                    if (p.enLigne)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: BoxDecoration(
                            color: AppColors.online, shape: BoxShape.circle),
                      ),
                    Expanded(
                      child: Text(
                        p.age != null ? '${p.name}, ${p.age}' : p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.surMedia),
                      ),
                    ),
                  ]),
                if (p.date != null)
                  Text(_ilYa(p.date),
                      style:
                          const TextStyle(fontSize: 11, color: AppColors.surMedia)),
              ],
            ),
          ),
          if (onLike != null)
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Row(children: [
                if (onPasser != null) ...[
                  Expanded(
                    child: _BoutonRond(
                      icon: Icons.close_rounded,
                      fond: const Color(0x66000000),
                      onTap: onPasser!,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: _BoutonRond(
                    icon: dejaLike
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    degrade: true,
                    onTap: dejaLike ? onTap : onLike!,
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _BoutonRond extends StatelessWidget {
  final IconData icon;
  final Color? fond;
  final bool degrade;
  final VoidCallback onTap;

  const _BoutonRond({
    required this.icon,
    required this.onTap,
    this.fond,
    this.degrade = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: fond,
          gradient: degrade ? AppColors.gradientPink : null,
          borderRadius: BorderRadius.circular(17),
          border: degrade ? null : Border.all(color: AppColors.surMedia.withValues(alpha: 0.38)),
        ),
        child: Icon(icon, color: AppColors.surMedia, size: 20),
      ),
    );
  }
}

// ─── LISTE VIDE ───────────────────────────────────────────────────

class _Vide extends StatelessWidget {
  final bool vues;
  const _Vide({required this.vues});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            vues ? Icons.remove_red_eye_outlined : Icons.favorite_border_rounded,
            size: 56,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            vues
                ? 'Personne n\'a encore vu ton profil'
                : 'Personne ne t\'a encore liké',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'Ajoute de belles photos et publie une story pour te faire remarquer.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
          // ⚡ Se faire remarquer tout de suite
          GestureDetector(
            onTap: showBoostSheet,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFA500)]),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.bolt_rounded, color: AppColors.surAccent, size: 20),
                SizedBox(width: 6),
                Text('Booster mon profil',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.surAccent)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
