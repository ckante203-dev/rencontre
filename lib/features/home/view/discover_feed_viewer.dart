import 'package:flutter/material.dart';
import 'package:rencontre/features/home/widget/reponse_photo_story.dart';
import 'package:rencontre/features/home/widget/legende_story.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/utils/video_init.dart';
import 'package:video_player/video_player.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/home/view/story_screen.dart';
import 'package:rencontre/features/home/widget/story_report_sheet.dart';
import 'package:rencontre/shared/models/story_model.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/chat/model/message_model.dart';

class DiscoverFeedItem {
  final StoryModel story;

  const DiscoverFeedItem.fromStory(this.story);
}

class DiscoverCard {
  final List<StoryModel> stories;

  const DiscoverCard({required this.stories});

  StoryModel get cover =>
      stories.firstWhere((s) => !s.isSeen, orElse: () => stories.first);

  bool get hasMultiple => stories.length > 1;
}

List<DiscoverCard> buildDiscoverCards(List<StoryModel> stories) {
  final Map<String, List<StoryModel>> grouped = {};
  final List<String> order = [];
  for (final s in stories) {
    if (!grouped.containsKey(s.userId)) {
      grouped[s.userId] = [];
      order.add(s.userId);
    }
    grouped[s.userId]!.add(s);
  }
  return order.map((uid) => DiscoverCard(stories: grouped[uid]!)).toList();
}

List<DiscoverFeedItem> flattenDiscoverCards(List<DiscoverCard> cards) {
  return cards
      .expand((c) => c.stories.map((s) => DiscoverFeedItem.fromStory(s)))
      .toList();
}

int startIndexForCard(List<DiscoverCard> cards, int cardIndex) {
  int idx = 0;
  for (int i = 0; i < cardIndex; i++) {
    idx += cards[i].stories.length;
  }
  return idx;
}

class DiscoverFeedViewerScreen extends StatefulWidget {
  final List<DiscoverFeedItem> items;
  final int initialIndex;
  final bool showCloseButton;
  final Future<void> Function()? onRefresh;
  // ✅ indique si l'onglet contenant cet écran est actuellement
  // affiché (vs monté en arrière-plan via IndexedStack). Permet de
  // couper le son/la vidéo quand on change d'onglet.
  final bool isActiveTab;

  const DiscoverFeedViewerScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.showCloseButton = true,
    this.onRefresh,
    this.isActiveTab = true,
  });

  @override
  State<DiscoverFeedViewerScreen> createState() =>
      _DiscoverFeedViewerScreenState();
}

class _DiscoverFeedViewerScreenState extends State<DiscoverFeedViewerScreen> {
  late final PageController _pageCtrl;
  late int _current;
  // ✅ Clés indexées par l'ID de la story (et non plus par la position) :
  // si la liste change (realtime, actualisation), chaque page garde son
  // propre état (vidéo, like) au lieu d'afficher la légende d'une story
  // avec la vidéo et le like d'une autre.
  final Map<String, GlobalKey<_StoryFeedPageState>> _pageKeys = {};

  GlobalKey<_StoryFeedPageState> _keyFor(String storyId) {
    return _pageKeys.putIfAbsent(
        storyId, () => GlobalKey<_StoryFeedPageState>());
  }

  void _setPageVisible(int index, bool visible) {
    if (index < 0 || index >= widget.items.length) return;
    _pageKeys[widget.items[index].story.id]?.currentState?.setVisible(visible);
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _current = widget.items.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageCtrl = PageController(initialPage: _current);
    if (widget.items.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // ✅ Vue seulement si l'onglet est affiché : monté en arrière-plan
        // au lancement, il marquait vue une story jamais regardée.
        if (widget.isActiveTab) _markSeen(widget.items[_current]);
        // ✅ Ne joue que si l'onglet Story est réellement affiché —
        // évite l'autoplay en arrière-plan au démarrage de l'app.
        _setPageVisible(_current, widget.isActiveTab);
      });
    }
  }

  @override
  void didUpdateWidget(covariant DiscoverFeedViewerScreen old) {
    super.didUpdateWidget(old);

    // ✅ Suit la story affichée par son ID si la liste a bougé (story
    // ajoutée/supprimée avant elle) : on reste sur la même story.
    final currentId = (_current >= 0 && _current < old.items.length)
        ? old.items[_current].story.id
        : null;
    final newIds = widget.items.map((i) => i.story.id).toSet();
    _pageKeys.removeWhere((id, _) => !newIds.contains(id));

    if (widget.items.isNotEmpty && currentId != null) {
      final newIndex =
          widget.items.indexWhere((i) => i.story.id == currentId);
      if (newIndex != -1 && newIndex != _current) {
        _current = newIndex;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_pageCtrl.hasClients) return;
          _pageCtrl.jumpToPage(newIndex);
          // La page a pu être reconstruite pendant le saut : on la
          // (re)déclare visible une fois construite à sa nouvelle place.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _current != newIndex || !widget.isActiveTab) {
              return;
            }
            final st =
                _pageKeys[widget.items[newIndex].story.id]?.currentState;
            if (st != null && !st._isVisible) st.setVisible(true);
          });
        });
      } else if (newIndex == -1) {
        // La story affichée a disparu : la page à cette position est
        // désormais une autre story, qu'il faut rendre visible.
        if (_current >= widget.items.length) {
          _current = widget.items.length - 1;
        }
        final idx = _current;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || idx >= widget.items.length) return;
          _setPageVisible(idx, widget.isActiveTab);
          if (widget.isActiveTab) _markSeen(widget.items[idx]);
        });
      }
    }

    if (widget.items.isNotEmpty && _current >= widget.items.length) {
      _current = widget.items.length - 1;
    }

    // ✅ Liste vide → non vide (stories chargées après l'ouverture de
    // l'onglet) : la première page n'était jamais rendue visible.
    if (old.items.isEmpty && widget.items.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _current >= widget.items.length) return;
        _setPageVisible(_current, widget.isActiveTab);
        if (widget.isActiveTab) _markSeen(widget.items[_current]);
      });
    }
    // ✅ L'onglet devient actif/inactif dans la barre de navigation :
    // on coupe/reprend la vidéo en cours au lieu de la laisser
    // jouer en arrière-plan sur un autre onglet.
    if (widget.isActiveTab != old.isActiveTab && widget.items.isNotEmpty) {
      _setPageVisible(_current, widget.isActiveTab);
      // ✅ La story affichée en arrivant sur l'onglet est regardée : elle
      // n'était jamais marquée vue (seulement celles atteintes en swipant),
      // et son rond restait coloré sur l'accueil et dans les messages.
      if (widget.isActiveTab) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _current >= widget.items.length) return;
          _markSeen(widget.items[_current]);
        });
      }
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _openAddStory() async {
    final result = await Get.to(() => const AddStoryScreen(),
        transition: Transition.cupertino);
    if (result == true && Get.isRegistered<HomeController>()) {
      await Get.find<HomeController>().loadStories();
    }
  }

  // Position de la story i parmi les stories consécutives du même
  // auteur (les items sont regroupés par auteur).
  ({int index, int count}) _positionInGroup(int i) {
    final uid = widget.items[i].story.userId;
    var start = i;
    while (start > 0 && widget.items[start - 1].story.userId == uid) {
      start--;
    }
    var end = i;
    while (end < widget.items.length - 1 &&
        widget.items[end + 1].story.userId == uid) {
      end++;
    }
    return (index: i - start, count: end - start + 1);
  }

  void _markSeen(DiscoverFeedItem item) {
    if (Get.isRegistered<HomeController>()) {
      Get.find<HomeController>().markStoryAsSeen(item.story.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('📸', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            const Text('Rien à découvrir pour le moment',
                style: TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 6),
            const Text('Sois le premier à partager un moment !',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: _openAddStory,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  gradient: AppColors.gradientPink,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 6),
                  Text('Publier ma story',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
            if (widget.onRefresh != null) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: widget.onRefresh,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(20)),
                  child: const Text('Actualiser',
                      style: TextStyle(color: Colors.white70)),
                ),
              ),
            ],
          ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageCtrl,
            scrollDirection: Axis.vertical,
            itemCount: widget.items.length,
            onPageChanged: (i) {
              // ✅ Saut programmatique (suivi de la story courante après
              // une mise à jour de la liste) : rien à faire.
              if (i == _current) return;
              _setPageVisible(_current, false);
              setState(() => _current = i);
              _setPageVisible(i, true);
              _markSeen(widget.items[i]);
            },
            itemBuilder: (_, i) {
              final pos = _positionInGroup(i);
              return _StoryFeedPage(
                key: _keyFor(widget.items[i].story.id),
                story: widget.items[i].story,
                showCloseButton: widget.showCloseButton,
                groupIndex: pos.index,
                groupCount: pos.count,
              );
            },
          ),
          if (widget.onRefresh != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 12,
              child: GestureDetector(
                onTap: widget.onRefresh,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.refresh_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StoryFeedPage extends StatefulWidget {
  final StoryModel story;
  final bool showCloseButton;
  // Position de cette story parmi celles du même auteur (ex. 2/3).
  final int groupIndex;
  final int groupCount;
  const _StoryFeedPage({
    super.key,
    required this.story,
    required this.showCloseButton,
    this.groupIndex = 0,
    this.groupCount = 1,
  });

  @override
  State<_StoryFeedPage> createState() => _StoryFeedPageState();
}

// ✅ NOUVEAU — WidgetsBindingObserver ajouté : coupe la vidéo/le son
// quand l'utilisateur quitte l'app entière (bouton Accueil du
// téléphone, appel entrant, verrouillage d'écran...), symétrique au
// fix déjà appliqué sur story_screen.dart. isActiveTab gérait déjà
// le changement d'onglet À L'INTÉRIEUR de l'app ; ceci couvre le cas
// où c'est le téléphone lui-même qui passe en arrière-plan.
class _StoryFeedPageState extends State<_StoryFeedPage>
    with WidgetsBindingObserver {
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;
  bool _liked = false;
  int _likeCount = 0;
  bool _replyFocused = false;
  bool _muted = false;
  bool _isVisible = false;
  final String? _myUid = Supabase.instance.client.auth.currentUser?.id;

  // ✅ tap simple = pause/lecture (comme TikTok)
  bool _manuallyPaused = false;

  // ✅ NOUVEAU — pause déclenchée par la mise en arrière-plan de
  // l'app (pas par l'utilisateur) : ne doit reprendre QUE si c'est
  // nous qui avions coupé, jamais si l'utilisateur avait pausé
  // lui-même via un tap.
  bool _pausedByLifecycle = false;

  // ✅ double-tap = like, avec petite animation de cœur à l'endroit
  // exact du tap.
  Offset? _lastTapPosition;
  bool _showLikeBurst = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLikeState();
    if (widget.story.isVideo) {
      // ✅ Réutilise la vidéo préchargée par l'accueil (avant : téléchargée
      // une 2ᵉ fois — data gaspillée).
      final ctrl = (Get.isRegistered<HomeController>()
              ? Get.find<HomeController>()
                  .takeCachedVideoController(widget.story.id)
              : null) ??
          VideoPlayerController.networkUrl(Uri.parse(widget.story.mediaUrl));
      _videoCtrl = ctrl;
      initialiserUneFois(ctrl).then((_) {
        if (!mounted) return;
        setState(() => _videoReady = true);
        ctrl.setLooping(true);
        // Vidéo raccourcie : boucle sur le passage choisi par l'auteur
        jouerPassage(ctrl,
            debut: widget.story.videoDebut, fin: widget.story.videoFin);
        if (_isVisible) {
          ctrl.play();
          ctrl.setVolume(_muted ? 0 : 1);
        }
      }).catchError((e) {
        // ✅ Avant : erreur non gérée si la vidéo ne charge pas (réseau…)
        debugPrint('Story vidéo non chargée : $e');
      });
    }
  }

  // ✅ NOUVEAU
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        if (_videoCtrl != null && _videoCtrl!.value.isPlaying) {
          _pausedByLifecycle = true;
          _videoCtrl!.pause();
        }
        break;
      case AppLifecycleState.resumed:
        if (_pausedByLifecycle) {
          _pausedByLifecycle = false;
          // Ne reprend que si cette page est toujours celle affichée
          // et que l'utilisateur n'avait pas lui-même mis en pause.
          if (_isVisible && !_manuallyPaused) {
            _videoCtrl?.play();
          }
        }
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  void setVisible(bool visible) {
    _isVisible = visible;
    if (_videoCtrl == null || !_videoReady) return;
    if (visible) {
      // ✅ Une pause manuelle ne doit valoir que pour la visite en
      // cours : en revenant sur cette story (swipe retour), elle
      // reprend normalement, comme sur TikTok.
      _manuallyPaused = false;
      _videoCtrl!.play();
      _videoCtrl!.setVolume(_muted ? 0 : 1);
    } else {
      _videoCtrl!.pause();
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _videoCtrl?.setVolume(_muted ? 0 : 1);
  }

  // ✅ tap simple sur l'écran : pause/relance la vidéo. Sans effet
  // sur une story image (rien à mettre en pause).
  void _handleSingleTap() {
    if (!widget.story.isVideo || _videoCtrl == null || !_videoReady) return;
    setState(() {
      if (_videoCtrl!.value.isPlaying) {
        _videoCtrl!.pause();
        _manuallyPaused = true;
      } else {
        _videoCtrl!.play();
        _manuallyPaused = false;
      }
    });
  }

  // ✅ double-tap : like uniquement (jamais unlike, comme
  // TikTok/Instagram), avec un cœur qui apparaît puis s'efface.
  void _handleDoubleTap() {
    if (!_liked) {
      _toggleLike();
    }
    setState(() => _showLikeBurst = true);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showLikeBurst = false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoCtrl?.pause();
    _videoCtrl?.dispose();
    super.dispose();
  }

  Future<void> _loadLikeState() async {
    try {
      final row = await Supabase.instance.client
          .from('stories')
          .select('liked_by')
          .eq('id', widget.story.id)
          .maybeSingle();
      final liked = List<String>.from(row?['liked_by'] ?? []);
      if (mounted) {
        setState(() {
          _liked = _myUid != null && liked.contains(_myUid);
          _likeCount = liked.length;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    if (widget.story.userId == _myUid) return;
    final uid = _myUid;
    if (uid == null) return;
    final was = _liked;
    setState(() {
      _liked = !was;
      _likeCount += _liked ? 1 : -1;
    });
    try {
      // ✅ RPC : la RLS n'autorise l'update de stories qu'au propriétaire
      // (le like n'était jamais enregistré), et l'ajout est atomique.
      await Supabase.instance.client.rpc('set_story_like',
          params: {'p_story_id': widget.story.id, 'p_like': !was});
    } catch (_) {
      if (mounted) {
        setState(() {
          _liked = was;
          _likeCount += was ? 1 : -1;
        });
      }
    }
  }

  Future<void> _openProfile() async {
    final s = widget.story;
    if (s.userId == _myUid) return;

    // ✅ Coupe la vidéo (et son son) AVANT de quitter vers le
    // profil — sinon elle continue de jouer en arrière-plan tant
    // que cette page reste montée sous l'écran de profil.
    final wasPlaying = _videoCtrl?.value.isPlaying ?? false;
    _videoCtrl?.pause();

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
      // ✅ On attend le retour de l'écran de profil pour savoir
      // quand relancer la lecture.
      await Get.toNamed('/profile/view', arguments: user);
    } catch (_) {
    } finally {
      // ✅ Ne relance que si la vidéo jouait réellement avant (pas
      // si l'utilisateur l'avait lui-même mise en pause par un tap),
      // et seulement si cette page est toujours celle affichée.
      if (mounted && _isVisible && wasPlaying && !_manuallyPaused) {
        _videoCtrl?.play();
      }
    }
  }

  // Signaler la story : la vidéo est mise en pause pendant le choix ;
  // si la story est signalée, elle disparaît du fil (hideStory).
  Future<void> _report() async {
    final wasPlaying = _videoCtrl?.value.isPlaying ?? false;
    _videoCtrl?.pause();
    final reported = await showStoryReportSheet(widget.story);
    if (!reported && mounted && _isVisible && wasPlaying && !_manuallyPaused) {
      _videoCtrl?.play();
    }
  }

  String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 0) return 'il y a ${diff.inDays}j';
    if (diff.inHours > 0) return 'il y a ${diff.inHours}h';
    if (diff.inMinutes > 0) return 'il y a ${diff.inMinutes}min';
    return "à l'instant";
  }

  // "il y a 2h · 3.4 km" — distance masquée si l'auteur l'a désactivée.
  String _subtitle(StoryModel s, bool isOwner) {
    final ago = _ago(s.createdAt);
    if (isOwner || !s.showDistance || s.distanceKm == null) return ago;
    return '$ago · ${HomeController.formatDistance(s.distanceKm! * 1000)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.story;
    final isOwner = s.userId == _myUid;
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    // ✅ tout l'écran est enveloppé dans un GestureDetector gérant
    // tap simple (pause) et double-tap (like). Les boutons internes
    // (avatar, fermer, mute, cœur, réponse) restent cliquables
    // normalement : Flutter donne toujours la priorité au
    // GestureDetector le plus interne lors de la résolution du
    // geste, donc aucun conflit avec ce calque global.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleSingleTap,
      onDoubleTapDown: (details) => _lastTapPosition = details.localPosition,
      onDoubleTap: _handleDoubleTap,
      child: Stack(fit: StackFit.expand, children: [
        Container(color: Colors.black),
        // ✅ Story texte : pas de média, on affiche le texte sur sa
        // couleur de fond (avant : image vide → icône d'image cassée).
        if (s.isTextStory)
          _TextStoryContent(story: s)
        else
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
        // ✅ icône pause/lecture au centre, visible tant que la
        // vidéo est manuellement en pause (façon TikTok).
        if (widget.story.isVideo && _manuallyPaused)
          const IgnorePointer(
            child: Center(
              child: Icon(Icons.play_arrow_rounded,
                  color: Colors.white70, size: 72),
            ),
          ),
        if (widget.groupCount > 1)
          Positioned(
            top: MediaQuery.of(context).padding.top + 6,
            left: 12,
            right: 12,
            child: IgnorePointer(
              child: Row(
                children: List.generate(widget.groupCount, (k) {
                  return Expanded(
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: k <= widget.groupIndex
                            ? Colors.white
                            : Colors.white30,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
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
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                        child: Text(s.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ),
                      if (s.isOnline && !isOwner) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: Colors.green, shape: BoxShape.circle),
                        ),
                      ],
                    ]),
                    Text(_subtitle(s, isOwner),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
            ),
            if (!isOwner)
              GestureDetector(
                onTap: _report,
                child: Container(
                  width: 34,
                  height: 34,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.more_vert_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
            // Dans l'onglet Story, le bouton Actualiser occupe ce coin.
            if (!widget.showCloseButton) const SizedBox(width: 34),
            if (widget.showCloseButton)
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
        if (!_replyFocused &&
            s.legendePlacee &&
            (s.caption ?? '').isNotEmpty)
          LegendePlacee(
            texte: s.caption!,
            x: s.legendeX!,
            y: s.legendeY!,
            echelle: s.legendeEchelle ?? 1,
          ),
        if (!_replyFocused &&
            !s.legendePlacee &&
            s.caption != null &&
            s.caption!.isNotEmpty)
          Positioned(
            bottom: keyboardH > 0 ? keyboardH + 76 : bottomPad + 76,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(s.caption!,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
            ),
          ),
        if (s.isVideo)
          Positioned(
            top: MediaQuery.of(context).padding.top + 68,
            right: 12,
            child: GestureDetector(
              onTap: _toggleMute,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                        _muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 15),
                    const SizedBox(width: 4),
                    Text(
                      _muted ? 'Muet' : 'Son',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // ✅ Bouton like — milieu à droite, façon TikTok.
        if (!isOwner)
          Positioned(
            right: 12,
            top: 0,
            bottom: keyboardH > 0 ? keyboardH : bottomPad,
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: _toggleLike,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _liked
                            ? Colors.pink.withOpacity(0.3)
                            : Colors.black54,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: _liked ? Colors.pink : Colors.white24),
                      ),
                      child: Center(
                        child: Text(_liked ? '❤️' : '🤍',
                            style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('$_likeCount',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        // ✅ Ma propre story : nombre de vues et de likes.
        if (isOwner)
          Positioned(
            left: 16,
            bottom: bottomPad + 20,
            child: IgnorePointer(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.visibility_rounded,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 5),
                  Text('${s.viewedBy.where((id) => id != _myUid).length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 14),
                  const Icon(Icons.favorite_rounded,
                      color: Colors.pinkAccent, size: 16),
                  const SizedBox(width: 5),
                  Text('$_likeCount',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        // La barre de réponse occupe toute la largeur disponible en bas.
        if (!isOwner)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            bottom: keyboardH > 0 ? keyboardH + 8 : bottomPad + 16,
            left: 16,
            right: 16,
            child: _ReplyBar(
              story: s,
              onFocusChanged: (focused) {
                setState(() => _replyFocused = focused);
              },
            ),
          ),
        // ✅ cœur qui apparaît à l'endroit du double-tap et s'efface
        // après un court instant.
        if (_showLikeBurst)
          Positioned(
            left: (_lastTapPosition?.dx ?? 0) - 50,
            top: (_lastTapPosition?.dy ?? 0) - 50,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showLikeBurst ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: const Text('❤️', style: TextStyle(fontSize: 100)),
              ),
            ),
          ),
      ]),
    );
  }
}

class _TextStoryContent extends StatelessWidget {
  final StoryModel story;
  const _TextStoryContent({required this.story});

  static Color _colorFromHex(String? hex) {
    var h = (hex ?? '').replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFF7B2FFF);
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    return Container(
      color: _colorFromHex(story.bgColor),
      alignment: Alignment.center,
      // Laisse la place à l'en-tête, au bouton like et à la barre de
      // réponse pour que le texte ne passe pas dessous.
      padding: EdgeInsets.fromLTRB(64, pad.top + 80, 64, pad.bottom + 90),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width - 128),
          child: Text(
            story.textContent ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplyBar extends StatefulWidget {
  final StoryModel story;
  final ValueChanged<bool> onFocusChanged;
  const _ReplyBar({required this.story, required this.onFocusChanged});

  @override
  State<_ReplyBar> createState() => _ReplyBarState();
}

class _ReplyBarState extends State<_ReplyBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false, _hasText = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => widget.onFocusChanged(_focus.hasFocus));
    _ctrl.addListener(() {
      final h = _ctrl.text.trim().isNotEmpty;
      if (h != _hasText) setState(() => _hasText = h);
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    if (uid == widget.story.userId) {
      Get.snackbar('Oups', 'Tu ne peux pas répondre à ta propre story',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white);
      return;
    }
    setState(() => _sending = true);
    try {
      // Point d'entrée centralisé : applique la règle "sans match, la
      // conversation démarre en demande de message".
      final convId =
          await SupabaseService().getOrCreateConversation(widget.story.userId);
      final storyData = StoryReplyData(
        storyId: widget.story.id,
        storyPreviewUrl: widget.story.mediaUrl,
        storyIsVideo: widget.story.isVideo,
        storyOwnerName: widget.story.userName,
        storyText: widget.story.isTextStory ? widget.story.textContent : null,
        storyBgColor: widget.story.isTextStory ? widget.story.bgColor : null,
      );
      final safeContent = text.substring(0, text.length.clamp(0, 500));
      if (Get.isRegistered<ConversationController>(tag: convId)) {
        await Get.find<ConversationController>(tag: convId).sendStoryReply(
          conversationId: convId,
          text: safeContent,
          storyData: storyData,
        );
      } else {
        await ConversationController.insertStoryReplyRow(
          conversationId: convId,
          senderId: uid,
          text: safeContent,
          storyData: storyData,
        );
        await Supabase.instance.client.from('conversations').update(
            {'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', convId);
        await SupabaseService().maybePromoteMessageRequest(convId);
      }
      _ctrl.clear();
      _focus.unfocus();
      widget.onFocusChanged(false);
      if (mounted) {
        Get.snackbar('Réponse envoyée ✓', '',
            snackPosition: SnackPosition.TOP,
            backgroundColor: AppColors.surface,
            colorText: Colors.white,
            duration: const Duration(seconds: 2));
      }
    } catch (e) {
      debugPrint('replyStory error: $e');
      if (mounted) {
        Get.snackbar('Erreur', "Impossible d'envoyer le message",
            snackPosition: SnackPosition.TOP,
            backgroundColor: AppColors.surface,
            colorText: Colors.white);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      // 📷 Répondre en photo (snap éphémère), façon Snap
      BoutonReponsePhoto(
          story: widget.story, onActif: widget.onFocusChanged),
      const SizedBox(width: 8),
      Expanded(
          child: Container(
        constraints: const BoxConstraints(minHeight: 44, maxHeight: 110),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _focus.hasFocus
                ? AppColors.accent.withOpacity(0.6)
                : Colors.white24,
            width: _focus.hasFocus ? 1.5 : 1,
          ),
        ),
        child: TextField(
          controller: _ctrl,
          focusNode: _focus,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          maxLines: 4,
          minLines: 1,
          maxLength: 500,
          buildCounter: (_,
                  {required currentLength, required isFocused, maxLength}) =>
              null,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            hintText: 'Répondre à la story...',
            hintStyle: TextStyle(color: Colors.white54, fontSize: 13),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      )),
      const SizedBox(width: 8),
      AnimatedOpacity(
        opacity: _hasText ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: _hasText && !_sending ? _send : null,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                gradient: AppColors.gradientPink, shape: BoxShape.circle),
            child: _sending
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
          ),
        ),
      ),
    ]);
  }
}
