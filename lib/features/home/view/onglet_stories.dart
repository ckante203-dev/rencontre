import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/amis/amis_controller.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/home/view/discover_feed_viewer.dart';
import 'package:rencontre/features/home/view/story_screen.dart';
import 'package:rencontre/shared/models/story_model.dart';

// ══════════════════════════════════════════════════════════════════
//  ONGLET « STORIES » — calqué sur Snapchat, 3 sections :
//   • Amis      : grands ronds avec l'APERÇU de la story (Ma story 1er)
//   • ⭐ Favoris : cartes verticales qui défilent (secret : la personne
//                 ne sait pas qu'elle est en favori)
//   • Découvrir : grandes cartes sur 2 colonnes (boostés, non vues 1ers)
//  Un appui ouvre le lecteur façon Snapchat (ouvrirStories) et enchaîne
//  sur les profils suivants de la MÊME section.
// ══════════════════════════════════════════════════════════════════

class OngletStories extends StatelessWidget {
  const OngletStories({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<HomeController>()) {
      Get.put(HomeController(), permanent: true);
    }
    final ctrl = Get.find<HomeController>();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppColors.barreSysteme,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Obx(() {
            bool estAmi(String uid) =>
                Get.isRegistered<AmisController>() &&
                AmisController.to.estAmi(uid);

            final cartes = buildDiscoverCards(ctrl.discoverStories);
            final amis = cartes.where((c) => estAmi(c.cover.userId)).toList();
            final favoris = cartes
                .where((c) =>
                    !estAmi(c.cover.userId) && ctrl.estFavori(c.cover.userId))
                .toList();
            final autres = cartes
                .where((c) =>
                    !estAmi(c.cover.userId) && !ctrl.estFavori(c.cover.userId))
                .toList();
            final maStory = ctrl.myActiveStory;

            return RefreshIndicator(
              onRefresh: ctrl.loadStories,
              color: AppColors.accent,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // ── En-tête ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                      child: Row(children: [
                        Text('Stories',
                            style: TextStyle(
                                fontFamily: 'Syne',
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                        const Spacer(),
                        _BoutonRond(
                          icone: Icons.add_a_photo_rounded,
                          onTap: () => _publier(ctrl),
                        ),
                      ]),
                    ),
                  ),

                  // ── Amis (Ma story en premier) ──
                  _titre('Amis'),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 128,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          _RondStory(
                            nom: 'Ma story',
                            story: maStory,
                            photoProfil: ctrl.myProfile?.photoUrl,
                            aVoir: false,
                            plus: true,
                            onTap: () {
                              if (maStory == null) {
                                _publier(ctrl);
                              } else {
                                final chain =
                                    ctrl.buildStoryChain(maStory.userId);
                                ouvrirStories(chain.stories,
                                    index: chain.startIndex);
                              }
                            },
                          ),
                          for (var i = 0; i < amis.length; i++)
                            _RondStory(
                              nom: amis[i].cover.userName,
                              story: amis[i].cover,
                              photoProfil: amis[i].cover.userPhotoUrl,
                              aVoir: amis[i].stories.any((s) => !s.isSeen),
                              booste: ctrl.storyBoostee(amis[i].cover.userId),
                              onTap: () => _ouvrir(amis, i, ctrl),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // ── ⭐ Favoris ──
                  if (favoris.isNotEmpty) ...[
                    _titre('⭐ Favoris'),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 200,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: favoris.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) => SizedBox(
                            width: 124,
                            child: _CarteStory(
                              carte: favoris[i],
                              booste:
                                  ctrl.storyBoostee(favoris[i].cover.userId),
                              compacte: true,
                              onTap: () => _ouvrir(favoris, i, ctrl),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],

                  // ── Découvrir ──
                  _titre('Découvrir'),
                  if (autres.isEmpty)
                    SliverFillRemaining(hasScrollBody: false, child: _Vide())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.64,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _CarteStory(
                            carte: autres[i],
                            booste: ctrl.storyBoostee(autres[i].cover.userId),
                            onTap: () => _ouvrir(autres, i, ctrl),
                          ),
                          childCount: autres.length,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  static Widget _titre(String texte) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
          child: Text(texte,
              style: TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ),
      );

  static Future<void> _publier(HomeController ctrl) async {
    final r = await Get.to(() => const AddStoryScreen(),
        transition: Transition.cupertino);
    if (r == true) ctrl.loadStories();
  }

  /// Ouvre le lecteur sur ce profil (1re story non vue), puis enchaîne
  /// sur les profils suivants de la même section.
  static void _ouvrir(List<DiscoverCard> cartes, int i, HomeController ctrl) {
    final premiere = cartes[i].cover;
    ctrl.preloadStoryMedia(premiere);
    final stories = cartes.expand((c) => c.stories).toList();
    var debut = startIndexForCard(cartes, i);
    final decalage = cartes[i].stories.indexOf(premiere);
    if (decalage > 0) debut += decalage;
    ouvrirStories(stories, index: debut);
  }
}

// ─── Aperçu d'une story (photo, texte sur sa couleur, vidéo) ────────

Color _couleur(String? hex) {
  final h = (hex ?? '').replaceAll('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v != null ? Color(v) : const Color(0xFF6A3093);
}

Widget _apercu(StoryModel s, {double texte = 13}) {
  if (s.isTextStory) {
    return Container(
      color: _couleur(s.bgColor),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(10),
      child: Text(s.textContent ?? '',
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.white,
              fontSize: texte,
              fontWeight: FontWeight.w700)),
    );
  }
  // Vidéo : pas de vignette en base → photo du profil
  final url = s.isVideo ? (s.userPhotoUrl ?? '') : s.mediaUrl;
  if (url.isEmpty) return Container(color: AppColors.surface2);
  return CachedNetworkImage(
    imageUrl: url,
    fit: BoxFit.cover,
    memCacheWidth: 400,
    fadeInDuration: const Duration(milliseconds: 200),
    placeholder: (_, __) => Container(color: AppColors.surface2),
    errorWidget: (_, __, ___) => Container(color: AppColors.surface2),
  );
}

String _ilYa(DateTime d) {
  final e = DateTime.now().difference(d);
  if (e.inMinutes < 1) return 'maintenant';
  if (e.inMinutes < 60) return '${e.inMinutes} min';
  if (e.inHours < 24) return '${e.inHours} h';
  return 'Hier';
}

// ─── GRAND ROND (section Amis) ────────────────────────────────────

class _RondStory extends StatelessWidget {
  final String nom;
  final StoryModel? story;
  final String? photoProfil;
  final bool aVoir;
  final bool booste;
  final bool plus; // Ma story : « + »
  final VoidCallback onTap;
  const _RondStory({
    required this.nom,
    required this.story,
    required this.photoProfil,
    required this.aVoir,
    required this.onTap,
    this.booste = false,
    this.plus = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = story;
    final anneau = aVoir
        ? (booste
            ? const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFFFA500)])
            : AppColors.gradientPink)
        : null;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 92,
        child: Column(children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 84,
              height: 84,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: anneau,
                color: anneau == null ? AppColors.border : null,
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.bg),
                child: ClipOval(
                  child: s != null
                      ? _apercu(s, texte: 9)
                      : ((photoProfil ?? '').isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: photoProfil!, fit: BoxFit.cover)
                          : Container(color: AppColors.surface2)),
                ),
              ),
            ),
            if (plus)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.gradientPink,
                    border: Border.all(color: AppColors.bg, width: 2),
                  ),
                  child: const Icon(Icons.add_rounded,
                      color: Colors.white, size: 16),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Text(nom,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: aVoir ? FontWeight.w700 : FontWeight.w500,
                  color: aVoir ? AppColors.textPrimary : AppColors.textMuted)),
        ]),
      ),
    );
  }
}

// ─── CARTE (Favoris : compacte ; Découvrir : grande) ───────────────

class _CarteStory extends StatelessWidget {
  final DiscoverCard carte;
  final bool booste;
  final bool compacte;
  final VoidCallback onTap;
  const _CarteStory({
    required this.carte,
    required this.booste,
    required this.onTap,
    this.compacte = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = carte.cover;
    final aVoir = carte.stories.any((x) => !x.isSeen);
    final distance = s.showDistance && s.distanceKm != null
        ? HomeController.formatDistance(s.distanceKm! * 1000)
        : null;
    final avatar = compacte ? 15.0 : 17.0;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(fit: StackFit.expand, children: [
          _apercu(s, texte: compacte ? 12 : 15),
          if (s.isVideo)
            const Center(
              child: Icon(Icons.play_circle_fill_rounded,
                  color: Colors.white70, size: 36),
            ),
          // Déjà vue : assombrie, comme Snapchat
          if (!aVoir) Container(color: Colors.black.withValues(alpha: 0.35)),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xD9000000)],
                  stops: [0.5, 1.0],
                ),
              ),
            ),
          ),
          if (booste)
            const Positioned(
              top: 8,
              right: 8,
              child:
                  Icon(Icons.bolt_rounded, color: Color(0xFFFFC233), size: 20),
            ),
          Positioned(
            left: 9,
            right: 9,
            bottom: 9,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Avatar avec anneau (rose = à voir)
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: aVoir ? AppColors.gradientPink : null,
                    color: aVoir ? null : Colors.white54,
                  ),
                  child: CircleAvatar(
                    radius: avatar,
                    backgroundColor: AppColors.surface2,
                    backgroundImage: (s.userPhotoUrl ?? '').isNotEmpty
                        ? CachedNetworkImageProvider(s.userPhotoUrl!)
                        : null,
                  ),
                ),
                const SizedBox(height: 5),
                Text(s.userName,
                    maxLines: compacte ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: compacte ? 13.5 : 17,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        shadows: const [
                          Shadow(color: Colors.black54, blurRadius: 6)
                        ])),
                if (!compacte)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                        distance != null
                            ? '${_ilYa(s.createdAt)} · $distance'
                            : _ilYa(s.createdAt),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _BoutonRond extends StatelessWidget {
  final IconData icone;
  final VoidCallback onTap;
  const _BoutonRond({required this.icone, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icone, color: AppColors.textPrimary, size: 21),
      ),
    );
  }
}

class _Vide extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('📸', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text('Pas encore de story à découvrir',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text('Publie la tienne avec le « + » de Ma story : sois le premier !',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ]),
    );
  }
}
