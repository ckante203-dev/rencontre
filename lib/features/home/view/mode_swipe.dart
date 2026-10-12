import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/core/utils/app_routes.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/likes/like_controller.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
import 'package:rencontre/shared/models/user_model.dart';

/// Mode cartes (façon Tinder) : glisser à droite = like, à gauche = passer.
/// Mêmes profils et même limite gratuite que la grille de l'Accueil.
/// ↩︎ Revenir au profil précédent : Premium.
class ModeSwipe extends StatefulWidget {
  const ModeSwipe({super.key});

  @override
  State<ModeSwipe> createState() => _ModeSwipeState();
}

class _ModeSwipeState extends State<ModeSwipe> {
  final home = Get.find<HomeController>();
  late final List<UserModel> _profils;
  int _index = 0;
  Offset _decalage = Offset.zero;
  bool _anime = false;

  @override
  void initState() {
    super.initState();
    final likes = Get.isRegistered<LikeController>()
        ? Get.find<LikeController>()
        : null;
    // Profils déjà likés retirés ; limite gratuite respectée
    _profils = home.filteredUsers
        .take(home.unlockedProfileCount)
        .where((u) => likes == null || !likes.hasLiked(u.id))
        .toList();
  }

  UserModel? get _actuel => _index < _profils.length ? _profils[_index] : null;

  Future<void> _decider(bool aime) async {
    final u = _actuel;
    if (u == null || _anime) return;
    HapticFeedback.lightImpact();
    setState(() {
      _anime = true;
      _decalage = Offset(aime ? 600 : -600, _decalage.dy);
    });
    await Future.delayed(const Duration(milliseconds: 220));
    if (aime && Get.isRegistered<LikeController>()) {
      Get.find<LikeController>().toggleLike(u);
    }
    if (!mounted) return;
    setState(() {
      _index++;
      _decalage = Offset.zero;
      _anime = false;
    });
  }

  Future<void> _superLike() async {
    final u = _actuel;
    if (u == null || _anime || !Get.isRegistered<LikeController>()) return;
    final ok = await Get.find<LikeController>().superLike(u);
    if (!ok || !mounted) return;
    setState(() {
      _anime = true;
      _decalage = const Offset(0, -900);
    });
    await Future.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    setState(() {
      _index++;
      _decalage = Offset.zero;
      _anime = false;
    });
  }

  void _revenir() {
    if (_index == 0) return;
    if (!ControleurProfil.estPremiumMaintenant()) {
      Get.toNamed(AppRoutes.paywall);
      return;
    }
    setState(() => _index--);
  }

  @override
  Widget build(BuildContext context) {
    final u = _actuel;
    final largeur = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        title: Text('Mode cartes'.tr,
            style: TextStyle(
                fontFamily: 'Syne',
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: u == null
            ? _fin()
            : Column(children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: GestureDetector(
                      onTap: () => Get.toNamed(AppRoutes.profilDetail,
                          arguments: u),
                      onPanUpdate: (d) =>
                          setState(() => _decalage += d.delta),
                      onPanEnd: (_) {
                        if (_decalage.dx > largeur * 0.25) {
                          _decider(true);
                        } else if (_decalage.dx < -largeur * 0.25) {
                          _decider(false);
                        } else {
                          setState(() => _decalage = Offset.zero);
                        }
                      },
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: _anime ? 220 : 0),
                        transform: Matrix4.identity()
                          ..translateByDouble(_decalage.dx, _decalage.dy * 0.3, 0, 1)
                          ..rotateZ(_decalage.dx / largeur * 0.3),
                        transformAlignment: Alignment.bottomCenter,
                        child: _Carte(user: u, decalage: _decalage.dx),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _rond(Icons.replay_rounded, AppColors.yellow, 50,
                            _revenir),
                        const SizedBox(width: 18),
                        _rond(Icons.close_rounded, AppColors.error, 64,
                            () => _decider(false)),
                        const SizedBox(width: 14),
                        _rond(Icons.star_rounded, const Color(0xFF2E9BFF), 50,
                            _superLike),
                        const SizedBox(width: 14),
                        _rond(Icons.favorite_rounded, AppColors.accent, 64,
                            () => _decider(true)),
                      ]),
                ),
              ]),
      ),
    );
  }

  Widget _rond(IconData icon, Color couleur, double taille, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: taille,
          height: taille,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: couleur.withValues(alpha: 0.6), width: 2),
          ),
          child: Icon(icon, color: couleur, size: taille * 0.45),
        ),
      );

  Widget _fin() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('✨', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('Tu as vu tous les profils pour le moment'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(
                ControleurProfil.estPremiumMaintenant()
                    ? 'Reviens plus tard ou élargis tes filtres.'.tr
                    : 'Passe Premium pour voir jusqu\'à 600 profils.'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted)),
            if (!ControleurProfil.estPremiumMaintenant()) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                onPressed: () => Get.toNamed(AppRoutes.paywall),
                child: Text('Passer Premium'.tr,
                    style: const TextStyle(color: AppColors.surAccent)),
              ),
            ],
          ]),
        ),
      );
}

class _Carte extends StatelessWidget {
  final UserModel user;
  final double decalage;
  const _Carte({required this.user, required this.decalage});

  @override
  Widget build(BuildContext context) {
    final aime = decalage > 30, passe = decalage < -30;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(fit: StackFit.expand, children: [
        (user.photoUrl ?? '').isNotEmpty
            ? CachedNetworkImage(
                imageUrl: user.photoUrl!, fit: BoxFit.cover, memCacheWidth: 1080)
            : Container(
                color: AppColors.surface2,
                alignment: Alignment.center,
                child: Text(user.name.isNotEmpty ? user.name[0] : '?',
                    style: TextStyle(
                        fontSize: 90,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textMuted))),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.transparent, AppColors.voileMedia],
            ),
          ),
        ),
        Positioned(
          left: 18,
          right: 18,
          bottom: 18,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                user.showBirthdate && user.age > 0
                    ? '${user.name}, ${user.age}'
                    : user.name,
                style: const TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: AppColors.surMedia)),
            if (user.distanceMeters != null && user.showDistance)
              Text('📍 ${HomeController.formatDistance(user.distanceMeters)}',
                  style: const TextStyle(color: AppColors.surMedia, fontSize: 14)),
            if ((user.bio ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(user.bio!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.surMedia, fontSize: 14)),
            ],
          ]),
        ),
        if (aime || passe)
          Positioned(
            top: 30,
            left: aime ? 24 : null,
            right: passe ? 24 : null,
            child: Transform.rotate(
              angle: aime ? -0.3 : 0.3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: aime ? AppColors.online : AppColors.error, width: 3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(aime ? 'LIKE' : 'NON'.tr,
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: aime ? AppColors.online : AppColors.error)),
              ),
            ),
          ),
      ]),
    );
  }
}
