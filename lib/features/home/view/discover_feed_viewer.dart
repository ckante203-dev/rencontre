import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/home/view/main_navigation.dart';
import 'package:rencontre/features/annonces/controller/annonces_controller.dart';
import 'package:rencontre/features/annonces/model/annonce_model.dart';
import 'package:rencontre/shared/models/story_model.dart';
import 'package:rencontre/shared/models/user_model.dart';

// ══════════════════════════════════════════════════════════════════
//  ÉLÉMENT DE FEED MIXTE (plein écran) — une story ou une annonce
// ══════════════════════════════════════════════════════════════════

class DiscoverFeedItem {
  final StoryModel? story;
  final AnnonceModel? annonce;

  const DiscoverFeedItem.fromStory(StoryModel s)
      : story = s,
        annonce = null;

  const DiscoverFeedItem.fromAnnonce(AnnonceModel a)
      : annonce = a,
        story = null;

  bool get isStory => story != null;
}

// ══════════════════════════════════════════════════════════════════
//  GROUPE D'ANNONCES — toutes les annonces d'un même auteur
//  regroupées sous une seule carte (comme les stories, 1 par user)
// ══════════════════════════════════════════════════════════════════

class AnnonceGroup {
  final List<AnnonceModel> items; // triées de la plus récente à la plus vieille
  AnnonceGroup(this.items);

  AnnonceModel get cover => items.first;
  int get count => items.length;
  String get userId => cover.userId;
}

List<AnnonceGroup> groupAnnoncesByUser(List<AnnonceModel> annonces) {
  final map = <String, List<AnnonceModel>>{};
  for (final a in annonces) {
    map.putIfAbsent(a.userId, () => []).add(a);
  }
  final groups = map.values.map((list) {
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return AnnonceGroup(list);
  }).toList();
  groups.sort((a, b) => b.cover.createdAt.compareTo(a.cover.createdAt));
  return groups;
}

// ══════════════════════════════════════════════════════════════════
//  CARTE DE GRILLE — ce qui s'affiche dans "Découvrir"
//  (1 carte = 1 story OU 1 groupe d'annonces d'un même auteur)
// ══════════════════════════════════════════════════════════════════

class DiscoverCard {
  final StoryModel? story;
  final AnnonceGroup? annonceGroup;

  const DiscoverCard.story(this.story) : annonceGroup = null;
  const DiscoverCard.annonceGroup(this.annonceGroup) : story = null;

  bool get isStory => story != null;
}

/// Mélange les stories et les groupes d'annonces façon Snapchat
/// "Découvrir" : un groupe d'annonces inséré toutes les 3 stories,
/// puis les groupes restants ajoutés à la fin.
List<DiscoverCard> buildDiscoverCards(
  List<StoryModel> stories,
  List<AnnonceGroup> groups,
) {
  final result = <DiscoverCard>[];
  var gIdx = 0;
  for (var i = 0; i < stories.length; i++) {
    result.add(DiscoverCard.story(stories[i]));
    if ((i + 1) % 3 == 0 && gIdx < groups.length) {
      result.add(DiscoverCard.annonceGroup(groups[gIdx]));
      gIdx++;
    }
  }
  while (gIdx < groups.length) {
    result.add(DiscoverCard.annonceGroup(groups[gIdx]));
    gIdx++;
  }
  return result;
}

/// Transforme les cartes de la grille en liste "à plat" pour le
/// swipe plein écran : un groupe d'annonces devient plusieurs items
/// consécutifs (on peut ainsi swiper entre les annonces d'un même
/// auteur avant de passer à l'élément suivant).
List<DiscoverFeedItem> flattenDiscoverCards(List<DiscoverCard> cards) {
  final result = <DiscoverFeedItem>[];
  for (final c in cards) {
    if (c.isStory) {
      result.add(DiscoverFeedItem.fromStory(c.story!));
    } else {
      for (final a in c.annonceGroup!.items) {
        result.add(DiscoverFeedItem.fromAnnonce(a));
      }
    }
  }
  return result;
}

/// Calcule à quel index de la liste "à plat" correspond le début
/// de la carte tapée (cardIndex), pour ouvrir le viewer au bon endroit.
int startIndexForCard(List<DiscoverCard> cards, int cardIndex) {
  var idx = 0;
  for (var i = 0; i < cardIndex; i++) {
    idx += cards[i].isStory ? 1 : cards[i].annonceGroup!.count;
  }
  return idx;
}

// ══════════════════════════════════════════════════════════════════
//  VIEWER PLEIN ÉCRAN — swipe horizontal entre stories et annonces
// ══════════════════════════════════════════════════════════════════

class DiscoverFeedViewerScreen extends StatefulWidget {
  final List<DiscoverFeedItem> items;
  final int initialIndex;

  const DiscoverFeedViewerScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });

  @override
  State<DiscoverFeedViewerScreen> createState() =>
      _DiscoverFeedViewerScreenState();
}

class _DiscoverFeedViewerScreenState extends State<DiscoverFeedViewerScreen> {
  late final PageController _pageCtrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _current = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageCtrl = PageController(initialPage: _current);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _markSeen(widget.items[_current]));
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _markSeen(DiscoverFeedItem item) {
    if (item.isStory) {
      if (Get.isRegistered<HomeController>()) {
        Get.find<HomeController>().markStoryAsSeen(item.story!.id);
      }
    } else {
      if (Get.isRegistered<AnnoncesController>()) {
        final ctrl = Get.find<AnnoncesController>();
        final fresh =
            ctrl.annonces.firstWhereOrNull((a) => a.id == item.annonce!.id) ??
                item.annonce!;
        ctrl.marquerVue(fresh);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child:
              Text('Rien à afficher', style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageCtrl,
        scrollDirection: Axis.horizontal,
        itemCount: widget.items.length,
        onPageChanged: (i) {
          setState(() => _current = i);
          _markSeen(widget.items[i]);
        },
        itemBuilder: (_, i) {
          final item = widget.items[i];
          return item.isStory
              ? _StoryFeedPage(story: item.story!)
              : _AnnonceFeedPage(annonce: item.annonce!);
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  PAGE STORY (dans le feed mixte)
// ══════════════════════════════════════════════════════════════════

class _StoryFeedPage extends StatefulWidget {
  final StoryModel story;
  const _StoryFeedPage({required this.story});

  @override
  State<_StoryFeedPage> createState() => _StoryFeedPageState();
}

class _StoryFeedPageState extends State<_StoryFeedPage> {
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;
  bool _liked = false;
  final String? _myUid = Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _loadLikeState();
    if (widget.story.isVideo) {
      final ctrl =
          VideoPlayerController.networkUrl(Uri.parse(widget.story.mediaUrl));
      _videoCtrl = ctrl;
      ctrl.initialize().then((_) {
        if (!mounted) return;
        setState(() => _videoReady = true);
        ctrl
          ..setLooping(true)
          ..play();
      });
    }
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  Future<void> _loadLikeState() async {
    final uid = _myUid;
    if (uid == null) return;
    try {
      final row = await Supabase.instance.client
          .from('stories')
          .select('liked_by')
          .eq('id', widget.story.id)
          .maybeSingle();
      if (row == null) return;
      final liked = List<String>.from(row['liked_by'] ?? []);
      if (mounted) setState(() => _liked = liked.contains(uid));
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    if (widget.story.userId == _myUid) return;
    final uid = _myUid;
    if (uid == null) return;
    final was = _liked;
    setState(() => _liked = !was);
    try {
      final row = await Supabase.instance.client
          .from('stories')
          .select('liked_by')
          .eq('id', widget.story.id)
          .maybeSingle();
      if (row == null) return;
      final liked = List<String>.from(row['liked_by'] ?? []);
      if (was) {
        liked.remove(uid);
      } else if (!liked.contains(uid)) {
        liked.add(uid);
      }
      await Supabase.instance.client
          .from('stories')
          .update({'liked_by': liked}).eq('id', widget.story.id);
    } catch (_) {
      if (mounted) setState(() => _liked = was);
    }
  }

  Future<void> _openProfile() async {
    final s = widget.story;
    if (s.userId == _myUid) return;
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', s.userId)
          .maybeSingle();
      if (data == null) return;
      final user = UserModel(
        id: data['id'] ?? s.userId,
        name: data['name'] ?? s.userName,
        age: data['age'] ?? 18,
        bio: data['bio'],
        photoUrl: data['photo_url'] ?? s.userPhotoUrl,
        photoUrls: List<String>.from(data['photo_urls'] ?? []),
        interests: List<String>.from(data['interests'] ?? []),
        gender: data['gender'],
        lookingFor: data['looking_for'],
        isOnline: data['is_online'] ?? false,
      );
      Get.toNamed('/profile/view', arguments: user);
    } catch (_) {}
  }

  String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 0) return 'il y a ${diff.inDays}j';
    if (diff.inHours > 0) return 'il y a ${diff.inHours}h';
    if (diff.inMinutes > 0) return 'il y a ${diff.inMinutes}min';
    return "à l'instant";
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.story;
    final isOwner = s.userId == _myUid;

    return Stack(fit: StackFit.expand, children: [
      Container(color: Colors.black),
      Center(
        child: s.isVideo
            ? (_videoReady && _videoCtrl != null
                ? AspectRatio(
                    aspectRatio: _videoCtrl!.value.aspectRatio,
                    child: VideoPlayer(_videoCtrl!))
                : const CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : CachedNetworkImage(
                imageUrl: s.mediaUrl,
                fit: BoxFit.contain,
                placeholder: (_, __) => const CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
                errorWidget: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white38,
                    size: 48),
              ),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: [Color(0xCC000000), Colors.transparent],
          ),
        ),
      ),
      const Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          height: 160,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [Color(0xBB000000), Colors.transparent],
              ),
            ),
          ),
        ),
      ),
      // ── Header ──
      Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        left: 12,
        right: 12,
        child: Row(children: [
          GestureDetector(
            onTap: _openProfile,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: ClipOval(
                child: s.userPhotoUrl != null && s.userPhotoUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: s.userPhotoUrl!, fit: BoxFit.cover)
                    : Container(
                        color: AppColors.accent2,
                        child: Center(
                          child: Text(
                            s.userName.isNotEmpty
                                ? s.userName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: _openProfile,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.userName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  Text(_ago(s.createdAt),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () => Get.back(),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.black38,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ]),
      ),
      // ── Caption + like ──
      Positioned(
        bottom: MediaQuery.of(context).padding.bottom + 24,
        left: 16,
        right: 16,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (s.caption != null && s.caption!.isNotEmpty)
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(s.caption!,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14)),
                ),
              )
            else
              const Spacer(),
            if (!isOwner) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _toggleLike,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color:
                        _liked ? Colors.pink.withOpacity(0.3) : Colors.black54,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _liked ? Colors.pink : Colors.white24),
                  ),
                  child: Center(
                    child: Text(_liked ? '❤️' : '🤍',
                        style: const TextStyle(fontSize: 20)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════
//  PAGE ANNONCE (dans le feed mixte)
// ══════════════════════════════════════════════════════════════════

class _AnnonceFeedPage extends StatelessWidget {
  final AnnonceModel annonce;
  const _AnnonceFeedPage({required this.annonce});

  void _openInAnnonces() {
    Get.back();
    if (Get.isRegistered<NavigationController>()) {
      Get.find<NavigationController>().goToAnnonces();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMedia = annonce.mediaUrl != null && annonce.mediaUrl!.isNotEmpty;

    return Stack(fit: StackFit.expand, children: [
      Container(color: const Color(0xFF13131A)),
      if (hasMedia)
        CachedNetworkImage(
          imageUrl: annonce.mediaUrl!,
          fit: BoxFit.cover,
          placeholder: (_, __) => const Center(
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2)),
          errorWidget: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined,
                  color: Colors.white38, size: 48)),
        )
      else
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              annonce.titre,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 20,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: [Color(0xCC000000), Colors.transparent],
          ),
        ),
      ),
      const Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          height: 220,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [Color(0xDD000000), Colors.transparent],
              ),
            ),
          ),
        ),
      ),
      // ── Badge "Annonce" + fermer ──
      Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        left: 12,
        right: 12,
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: AppColors.gradientPink,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.campaign_rounded, color: Colors.white, size: 13),
              SizedBox(width: 5),
              Text('Annonce',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ]),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Get.back(),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.black38,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ]),
      ),
      // ── Bas : auteur, titre, réactions ──
      Positioned(
        bottom: MediaQuery.of(context).padding.bottom + 24,
        left: 16,
        right: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: ClipOval(
                  child: annonce.userPhotoUrl != null &&
                          annonce.userPhotoUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: annonce.userPhotoUrl!, fit: BoxFit.cover)
                      : Container(
                          color: AppColors.accent2,
                          child: Center(
                            child: Text(
                                annonce.userName.isNotEmpty
                                    ? annonce.userName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12)),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(annonce.userName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
            if (hasMedia) ...[
              const SizedBox(height: 10),
              Text(annonce.titre,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ],
            const SizedBox(height: 6),
            Text(
              annonce.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Row(children: [
              _ReactionRow(annonce: annonce),
              const Spacer(),
              GestureDetector(
                onTap: _openInAnnonces,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Text('Voir plus',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ],
        ),
      ),
    ]);
  }
}

// ── Ligne de réactions rapides pour une annonce ────────────────────

class _ReactionRow extends StatelessWidget {
  final AnnonceModel annonce;
  const _ReactionRow({required this.annonce});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<AnnoncesController>()) {
      return const SizedBox.shrink();
    }
    final ctrl = Get.find<AnnoncesController>();

    return Obx(() {
      final fresh =
          ctrl.annonces.firstWhereOrNull((a) => a.id == annonce.id) ?? annonce;
      return GestureDetector(
        onTap: () => ctrl.toggleReaction(fresh, '❤️'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: fresh.myReaction.isNotEmpty
                ? Colors.pink.withOpacity(0.25)
                : Colors.black45,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color:
                    fresh.myReaction.isNotEmpty ? Colors.pink : Colors.white24),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(fresh.myReaction.isNotEmpty ? fresh.myReaction : '🤍',
                style: const TextStyle(fontSize: 16)),
            if (fresh.likes > 0) ...[
              const SizedBox(width: 6),
              Text('${fresh.likes}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      );
    });
  }
}
