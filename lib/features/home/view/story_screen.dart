import 'dart:async';
import 'dart:io';
import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:rencontre/features/home/widget/legende_story.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/foundation.dart' show compute;
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/services/ouvrir_profil.dart';
import 'package:rencontre/features/home/widget/barre_reponse_story.dart';
import 'package:rencontre/features/evenements/evenements_controller.dart';
import 'package:rencontre/features/evenements/evenement_model.dart';
import 'package:rencontre/features/chat/view/sticker_sheet.dart';
import 'package:rencontre/features/home/widget/stickers_story.dart';
import 'package:rencontre/features/home/widget/camera_story.dart';
import 'package:rencontre/features/home/view/ecran_amis_proches.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/utils/video_init.dart';
import 'package:video_player/video_player.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/home/widget/story_report_sheet.dart';
import 'package:rencontre/shared/models/story_model.dart';

Color _colorFromHex(String hex) {
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.parse(h, radix: 16));
}

// ══════════════════════════════════════════════════════════════════
//  ✅ RÉÉCRIT — comportement façon WhatsApp/Telegram :
//  - TAP (zone gauche/droite) : avance/recule d'UNE story À
//    L'INTÉRIEUR DU MÊME PROFIL. Une fois les stories du profil
//    épuisées, enchaîne automatiquement sur le profil suivant.
//  - SWIPE HORIZONTAL (glissement du doigt) : saute DIRECTEMENT au
//    profil suivant/précédent, quelle que soit la story affichée.
//
//  L'API publique du widget (stories + initialIndex, tous deux une
//  liste "plate" comme avant) est inchangée : aucun appelant
//  existant n'a besoin d'être modifié.
// ══════════════════════════════════════════════════════════════════

/// Ouvre le lecteur de stories façon Snapchat. Route transparente : en
/// glissant vers le bas, l'écran d'origine réapparaît derrière la story.
Future<void> ouvrirStories(List<StoryModel> stories, {int index = 0}) async {
  await Get.to(() => StoryViewerScreen(stories: stories, initialIndex: index),
      opaque: false,
      transition: Transition.fadeIn,
      duration: const Duration(milliseconds: 220));
}

class StoryViewerScreen extends StatefulWidget {
  final List<StoryModel> stories;
  final int initialIndex;

  const StoryViewerScreen(
      {super.key, required this.stories, this.initialIndex = 0});

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with TickerProviderStateMixin {
  // ── Glisser façon Snapchat : ↓ fermer (la story suit le doigt),
  //    ↑ répondre (ou voir qui a vu ma story) ──────────────────────
  double _dragY = 0;
  bool _drague = false;
  late final AnimationController _retourCtrl;
  double _retourDepuis = 0;
  int _demandeClavier = 0;

  // ── Regroupement par profil ──────────────────────────────────
  late List<List<StoryModel>> _groups;
  late int _profileIndex;
  late int _storyIndexInProfile;

  late AnimationController _progressCtrl;
  late final PageController _pageCtrl;
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;
  final String? _myUid = Supabase.instance.client.auth.currentUser?.id;
  bool _replyFocused = false;
  bool _paused = false;
  bool _longPressing = false;
  final Set<String> _likedStoryIds = {};

  // ── Cache & préchargement vidéo/image (perf) ────────────────────
  // Indexés par l'ID de la story (plus robuste qu'une position,
  // maintenant que la navigation n'est plus purement linéaire).
  final Map<String, VideoPlayerController> _videoCache = {};
  final Set<String> _precachedImages = {};
  int _loadToken = 0;

  static const Duration _imageDuration = Duration(seconds: 5);
  static const int _freeViewersLimit = 10;

  StoryModel get _currentStory => _groups[_profileIndex][_storyIndexInProfile];
  List<StoryModel> get _currentGroup => _groups[_profileIndex];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    _groups = _groupByProfile(widget.stories);

    if (_groups.isEmpty) {
      _profileIndex = 0;
      _storyIndexInProfile = 0;
    } else {
      final pos = _resolveInitialPosition(widget.initialIndex);
      _profileIndex = pos[0];
      _storyIndexInProfile = pos[1];
    }

    _pageCtrl = PageController(initialPage: _profileIndex);
    _retourCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(() {
        setState(() => _dragY = _retourDepuis *
            (1 - Curves.easeOut.transform(_retourCtrl.value)));
      });
    _progressCtrl = AnimationController(vsync: this);
    _progressCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _advance();
    });

    if (_groups.isNotEmpty) {
      // ✅ Après la 1ʳᵉ image : le préchargement (precacheImage) a besoin
      // du contexte, interdit pendant initState (« dependOnInheritedWidget
      // … called before initState() completed » sur une story photo).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadCurrentStory();
      });
    }
  }

  /// Regroupe la liste plate reçue en sous-listes consécutives par
  /// userId : chaque groupe = les stories d'UN SEUL profil, dans
  /// l'ordre. Suppose que l'appelant fournit déjà une liste
  /// contiguë par profil (c'est le cas pour tous les appelants
  /// actuels : StoriesRow, écran de profil, grille de publications
  /// — qui ne passent d'ailleurs souvent qu'un seul profil).
  List<List<StoryModel>> _groupByProfile(List<StoryModel> flat) {
    final groups = <List<StoryModel>>[];
    for (final s in flat) {
      if (groups.isNotEmpty && groups.last.first.userId == s.userId) {
        groups.last.add(s);
      } else {
        groups.add([s]);
      }
    }
    return groups;
  }

  /// Convertit l'index "plat" reçu par le widget (rétro-compatible
  /// avec tous les appelants existants) en position (profil, story
  /// dans ce profil).
  List<int> _resolveInitialPosition(int flatIndex) {
    int remaining = flatIndex.clamp(0, widget.stories.length - 1);
    for (int g = 0; g < _groups.length; g++) {
      if (remaining < _groups[g].length) return [g, remaining];
      remaining -= _groups[g].length;
    }
    return [_groups.length - 1, _groups.last.length - 1];
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _retourCtrl.dispose();
    _progressCtrl.dispose();
    for (final c in _videoCache.values) {
      c.dispose();
    }
    _videoCache.clear();
    super.dispose();
  }

  // ── Position plate courante (toutes stories confondues, même à
  // cheval sur deux profils) — utilisée uniquement pour le
  // préchargement / l'éviction du cache vidéo. ────────────────────
  int get _flatIndexOfCurrent {
    int idx = 0;
    for (int g = 0; g < _profileIndex; g++) {
      idx += _groups[g].length;
    }
    return idx + _storyIndexInProfile;
  }

  StoryModel? _flatStoryAt(int flatIndex) {
    if (flatIndex < 0 || flatIndex >= widget.stories.length) return null;
    return widget.stories[flatIndex];
  }

  Future<void> _loadCurrentStory() async {
    // Jeton de génération : si un chargement plus récent démarre
    // entre-temps (navigation rapide), ce chargement s'arrête
    // proprement au lieu de toucher un contrôleur disposé ailleurs.
    final token = ++_loadToken;

    _progressCtrl.stop();
    _progressCtrl.reset();

    final s = _currentStory;
    _markSeen(s);

    if (s.isVideo) {
      VideoPlayerController? ctrl = _videoCache[s.id];

      if (ctrl == null && Get.isRegistered<HomeController>()) {
        // Réutilise un contrôleur déjà préchargé par HomeController
        // au lieu d'en recréer un et de retélécharger la vidéo.
        ctrl = Get.find<HomeController>().takeCachedVideoController(s.id);
        if (ctrl != null) _videoCache[s.id] = ctrl;
      }

      bool alreadyInitialized = ctrl?.value.isInitialized ?? false;

      if (ctrl == null) {
        ctrl = VideoPlayerController.networkUrl(Uri.parse(s.mediaUrl));
        _videoCache[s.id] = ctrl;
      }

      if (!alreadyInitialized) {
        try {
          await initialiserUneFois(ctrl);
        } catch (e) {
          debugPrint('_loadCurrentStory video init error: $e');
        }
      }

      // Ce chargement est-il encore pertinent ?
      if (token != _loadToken || !mounted) return;

      _pruneVideoCache();

      if (!mounted) return;
      setState(() {
        _videoCtrl = ctrl;
        _videoReady = ctrl!.value.isInitialized;
      });

      if (_videoReady) {
        ctrl.setLooping(false);
        // Vidéo raccourcie dans l'éditeur : seul le passage choisi est joué
        // (la barre de progression dure le temps du passage).
        final debut = s.videoDebut ?? Duration.zero;
        final fin = s.videoFin ?? ctrl.value.duration;
        ctrl.seekTo(debut);
        ctrl.play();
        final passage = fin - debut;
        _progressCtrl.duration =
            passage > Duration.zero ? passage : ctrl.value.duration;
      } else {
        // fallback si la vidéo n'a pas pu s'initialiser
        _progressCtrl.duration = _imageDuration;
      }
    } else {
      _pruneVideoCache();
      if (!mounted) return;
      setState(() {
        _videoCtrl = null;
        _videoReady = false;
      });
      _progressCtrl.duration = _imageDuration;
    }

    if (token != _loadToken || !mounted) return;

    _progressCtrl.forward();
    _loadLikes(s);
    _preloadAdjacent();
  }

  // ✅ Marque comme vue CHAQUE story réellement affichée (tap, fin de
  // minuterie, swipe vers un autre profil) — auparavant seule la 1ère
  // story du profil ouvert l'était. Une seule fois par story, et jamais
  // pour mes propres stories (sinon je m'ajoute à mes propres vues).
  final Set<String> _markedSeenIds = {};

  void _markSeen(StoryModel s) {
    if (s.id.isEmpty || s.userId == _myUid) return;
    if (!_markedSeenIds.add(s.id)) return;
    // ✅ Après la frame : appelé depuis initState, la mise à jour de la
    // liste réactive reconstruisait la rangée de l'accueil pendant le build
    // (« setState() called during build »).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Get.isRegistered<HomeController>()) {
        Get.find<HomeController>().markStoryAsSeen(s.id);
      }
    });
  }

  /// Garde uniquement les contrôleurs vidéo de la story courante et
  /// de ses voisines immédiates (dans l'ordre plat global — donc
  /// potentiellement la dernière story du profil précédent ou la
  /// première du profil suivant) ; dispose tout le reste.
  void _pruneVideoCache() {
    final keep = <String>{_currentStory.id};
    final prev = _flatStoryAt(_flatIndexOfCurrent - 1);
    final next = _flatStoryAt(_flatIndexOfCurrent + 1);
    if (prev != null) keep.add(prev.id);
    if (next != null) keep.add(next.id);

    final toRemove =
        _videoCache.keys.where((id) => !keep.contains(id)).toList();
    for (final id in toRemove) {
      final removed = _videoCache.remove(id);
      if (removed != _videoCtrl) {
        removed?.dispose();
      }
    }
  }

  /// Précharge la story suivante et précédente dans l'ordre plat
  /// global (même si elles appartiennent au profil suivant ou
  /// précédent), pour rendre la transition quasi instantanée.
  void _preloadAdjacent() {
    for (final s in [
      _flatStoryAt(_flatIndexOfCurrent + 1),
      _flatStoryAt(_flatIndexOfCurrent - 1),
    ]) {
      if (s == null || s.isTextStory) continue;
      if (s.isVideo) {
        if (!_videoCache.containsKey(s.id)) {
          final ctrl = VideoPlayerController.networkUrl(Uri.parse(s.mediaUrl));
          _videoCache[s.id] = ctrl;
          initialiserUneFois(ctrl).catchError((e) {
            debugPrint('_preloadAdjacent video error: $e');
          });
        }
      } else {
        if (_precachedImages.add(s.id) && mounted) {
          precacheImage(CachedNetworkImageProvider(s.mediaUrl), context)
              .catchError((e) {
            debugPrint('_preloadAdjacent image error: $e');
          });
        }
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  NAVIGATION
  //  TAP  → story suivante/précédente DU MÊME PROFIL ; une fois
  //         épuisées, bascule sur le profil suivant/précédent.
  //  SWIPE (PageView) → change directement de PROFIL, quelle que
  //         soit la story affichée (voir _onPageChanged).
  // ══════════════════════════════════════════════════════════════

  void _advance() {
    if (_storyIndexInProfile < _currentGroup.length - 1) {
      setState(() => _storyIndexInProfile++);
      _loadCurrentStory();
    } else if (_profileIndex < _groups.length - 1) {
      _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      Get.back();
    }
  }

  void _retreat() {
    if (_storyIndexInProfile > 0) {
      setState(() => _storyIndexInProfile--);
      _loadCurrentStory();
    } else if (_profileIndex > 0) {
      _pageCtrl.previousPage(
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  /// Appelé aussi bien par un balayage manuel de l'utilisateur que
  /// par les appels programmatiques nextPage()/previousPage() de
  /// _advance()/_retreat() une fois un profil épuisé. En avançant,
  /// on démarre à la 1ère story du nouveau profil ; en reculant, à
  /// sa dernière story.
  void _onPageChanged(int newProfileIndex) {
    final forward = newProfileIndex > _profileIndex;
    setState(() {
      _profileIndex = newProfileIndex;
      _storyIndexInProfile = forward ? 0 : _groups[newProfileIndex].length - 1;
    });
    _loadCurrentStory();
  }

  void _pause() {
    if (_paused) return;
    _paused = true;
    _progressCtrl.stop();
    _videoCtrl?.pause();
  }

  void _resume() {
    if (!_paused) return;
    _paused = false;
    _progressCtrl.forward();
    _videoCtrl?.play();
  }

  // ✅ Vrai quand le menu d'options se ferme pour ouvrir aussitôt une
  // autre feuille/dialogue (vues, suppression) : la lecture ne doit
  // PAS reprendre entre les deux.
  bool _chainingModal = false;

  // ✅ Reprend la lecture après fermeture d'une feuille/dialogue, mais
  // seulement si le viewer est de nouveau l'écran visible. Si un autre
  // écran a été ouvert entre-temps depuis la feuille (ex: profil d'un
  // spectateur), on attend d'y être revenu — sinon la minuterie
  // continuait et Get.back() en fin de story fermait le mauvais écran.
  void _resumeWhenVisible() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || route.isCurrent) {
      _resume();
      return;
    }
    final anim = route.secondaryAnimation;
    if (anim == null) return;
    late final AnimationStatusListener listener;
    listener = (status) {
      if (status != AnimationStatus.dismissed) return;
      anim.removeStatusListener(listener);
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
        _resume();
      }
    };
    anim.addStatusListener(listener);
  }

  Future<void> _likeStory(StoryModel story) async {
    if (story.userId == _myUid) return;
    final uid = _myUid;
    if (uid == null) return;
    final alreadyLiked = _likedStoryIds.contains(story.id);
    setState(() {
      if (alreadyLiked) {
        _likedStoryIds.remove(story.id);
      } else {
        _likedStoryIds.add(story.id);
      }
    });
    try {
      // ✅ RPC : la RLS n'autorise l'update de stories qu'au propriétaire
      // (le like n'était jamais enregistré), et l'ajout est atomique.
      await Supabase.instance.client.rpc('set_story_like',
          params: {'p_story_id': story.id, 'p_like': !alreadyLiked});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (alreadyLiked) {
          _likedStoryIds.add(story.id);
        } else {
          _likedStoryIds.remove(story.id);
        }
      });
      debugPrint('_likeStory error: $e');
    }
  }

  Future<void> _loadLikes(StoryModel story) async {
    final uid = _myUid;
    if (uid == null) return;
    try {
      final row = await Supabase.instance.client
          .from('stories')
          .select('liked_by')
          .eq('id', story.id)
          .maybeSingle();
      if (row == null) return;
      final List<String> liked = List<String>.from(row['liked_by'] ?? []);
      if (liked.contains(uid) && mounted)
        setState(() => _likedStoryIds.add(story.id));
    } catch (_) {}
  }

  Future<void> _openProfile(StoryModel story) async {
    if (_replyFocused) return;
    if (story.userId == _myUid) return;

    // ✅ Coupe la vidéo/la progression AVANT de quitter vers le
    // profil — sinon le son continue de jouer en arrière-plan tant
    // que cet écran reste monté sous l'écran de profil.
    final wasAlreadyPaused = _paused;
    _pause();

    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', story.userId)
          .maybeSingle();
      if (data == null) return;
      final user = profilComplet(data);
      // ✅ On attend le retour de l'écran de profil pour savoir
      // quand relancer la lecture.
      await Get.toNamed('/profile/view', arguments: user);
    } catch (e) {
      debugPrint('_openProfile from story error: $e');
    } finally {
      // ✅ Ne relance que si ce n'était pas déjà en pause manuelle
      // (ex: appui long) avant d'ouvrir le profil.
      if (mounted && !wasAlreadyPaused) {
        _resume();
      }
    }
  }

  Future<void> _deleteStory(StoryModel story) async {
    _chainingModal = false;
    if (story.userId != _myUid) {
      _resumeWhenVisible();
      return;
    }
    // ✅ Lecture en pause pendant la confirmation : sinon la minuterie
    // avançait (ou Get.back() fermait le dialogue au lieu du viewer).
    _pause();
    final confirmed = await Get.dialog<bool>(AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Supprimer cette story ?',
          style: TextStyle(
              color: Colors.white,
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              fontSize: 17)),
      content: Text('Cette story sera définitivement supprimée.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('Annuler',
                style: TextStyle(
                    color: AppColors.textMuted, fontWeight: FontWeight.w600))),
        GestureDetector(
          onTap: () => Get.back(result: true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(12)),
            child: const Text('Supprimer',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    ));
    if (confirmed != true) {
      _resumeWhenVisible();
      return;
    }
    try {
      await Supabase.instance.client
          .from('stories')
          .delete()
          .eq('id', story.id);
      if (Get.isRegistered<HomeController>()) {
        await Get.find<HomeController>().loadStories();
      }
      if (mounted) {
        Get.back();
        Get.snackbar('Story supprimée', '',
            snackPosition: SnackPosition.TOP,
            backgroundColor: AppColors.surface,
            colorText: Colors.white,
            duration: const Duration(seconds: 2));
      }
    } catch (e) {
      debugPrint('_deleteStory error: $e');
      if (mounted) {
        Get.snackbar('Erreur', "Impossible de supprimer la story",
            snackPosition: SnackPosition.TOP,
            backgroundColor: AppColors.surface,
            colorText: Colors.white);
        _resumeWhenVisible(); // ✅ la story reste affichée : on reprend
      }
    }
  }

  // Story d'un autre : signalement. Une story signalée est masquée ;
  // on ferme alors le viewer (sa liste de stories est figée).
  Future<void> _reportStory(StoryModel story) async {
    final reported = await showStoryReportSheet(story);
    if (!mounted) return;
    if (reported) {
      Get.back();
    } else {
      _resumeWhenVisible();
    }
  }

  void _showStoryOptions(StoryModel story) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 8),
          _OptionTile(
            icon: Icons.remove_red_eye_rounded,
            label:
                '${story.viewedBy.length} vue${story.viewedBy.length != 1 ? 's' : ''}',
            color: Colors.white,
            onTap: () {
              _chainingModal = true; // ✅ pas de reprise entre les 2 feuilles
              Get.back();
              Future.delayed(const Duration(milliseconds: 200), () {
                if (mounted) {
                  _showViewers(story);
                } else {
                  _chainingModal = false;
                }
              });
            },
          ),
          const _OptionDivider(),
          _OptionTile(
            icon: Icons.delete_outline_rounded,
            label: 'Supprimer',
            color: Colors.red,
            onTap: () {
              _chainingModal = true; // ✅ pas de reprise avant le dialogue
              Get.back();
              Future.delayed(const Duration(milliseconds: 200), () {
                if (mounted) {
                  _deleteStory(story);
                } else {
                  _chainingModal = false;
                }
              });
            },
          ),
        ]),
      ),
    ).then((_) {
      // ✅ Si une autre feuille/dialogue prend le relais, c'est elle
      // qui relancera la lecture à sa fermeture.
      if (_chainingModal) return;
      _resumeWhenVisible();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_groups.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.photo_library_outlined,
                color: Colors.white38, size: 48),
            const SizedBox(height: 12),
            const Text('Aucune story',
                style: TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Get.back(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(20)),
                child: const Text('Retour',
                    style: TextStyle(color: Colors.white70)),
              ),
            ),
          ]),
        ),
      );
    }

    final s = _currentStory;
    final bool isOwner = s.userId == _myUid;
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    final h = MediaQuery.of(context).size.height;
    final bas = (_dragY > 0 ? _dragY : 0.0).clamp(0.0, h);
    final avance = (bas / (h * 0.6)).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        // Fond noir qui s'efface : l'écran d'origine réapparaît derrière
        Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(
                color: Colors.black.withValues(alpha: 1 - avance * 0.9)),
          ),
        ),
        Transform.translate(
          offset: Offset(0, _dragY > 0 ? bas : _dragY * 0.25),
          child: Transform.scale(
            scale: 1 - avance * 0.3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(avance > 0 ? 24 : 0),
              child: _lecteur(context, s, isOwner, keyboardH, bottomPad),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _lecteur(BuildContext context, StoryModel s, bool isOwner,
      double keyboardH, double bottomPad) {
    return ColoredBox(
      color: Colors.black,
      child: GestureDetector(
        onLongPressStart: (_) {
          _pause();
          setState(() => _longPressing = true);
        },
        onLongPressEnd: (_) {
          _resume();
          setState(() => _longPressing = false);
        },
        // Glisser : ↓ la story suit le doigt puis se ferme, ↑ répondre
        onVerticalDragStart: (_) {
          if (_replyFocused) return;
          _drague = true;
          _retourCtrl.stop();
          _pause();
        },
        onVerticalDragUpdate: (d) {
          if (!_drague) return;
          setState(() => _dragY += d.delta.dy);
        },
        onVerticalDragEnd: (d) {
          if (!_drague) return;
          _drague = false;
          final v = d.primaryVelocity ?? 0;
          if (_dragY > 140 || v > 900) {
            Get.back();
            return;
          }
          final versLeHaut = _dragY < -70 || v < -700;
          _retourDepuis = _dragY;
          _retourCtrl.forward(from: 0);
          if (versLeHaut) {
            if (isOwner) {
              _showViewers(s); // reprend la lecture à sa fermeture
            } else {
              setState(() => _demandeClavier++);
            }
            return;
          }
          _resume();
        },
        onTapUp: (d) {
          if (_replyFocused) {
            FocusScope.of(context).unfocus();
            setState(() => _replyFocused = false);
            return;
          }
          final x = d.globalPosition.dx;
          final w = MediaQuery.of(context).size.width;
          if (x < w * 0.35) {
            _retreat();
          } else {
            _advance();
          }
        },
        child: Stack(fit: StackFit.expand, children: [
          // ── La story : zone à part, coins arrondis en bas (Snapchat) ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: _hauteurBarre + bottomPad,
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(18)),
              child: Stack(fit: StackFit.expand, children: [
          PageView.builder(
            controller: _pageCtrl,
            // ✅ Chaque PAGE = un PROFIL entier (pas une story isolée).
            // Le balayage manuel change donc directement de profil ;
            // seul le tap avance story par story (voir onTapUp).
            physics: _replyFocused
                ? const NeverScrollableScrollPhysics()
                : const BouncingScrollPhysics(),
            itemCount: _groups.length,
            onPageChanged: _onPageChanged,
            // ✅ Effet cube 3D entre deux profils (comme WhatsApp)
            itemBuilder: (_, profileIdx) => AnimatedBuilder(
              animation: _pageCtrl,
              child: _buildProfilePage(profileIdx),
              builder: (_, child) {
                var page = _profileIndex.toDouble();
                if (_pageCtrl.hasClients &&
                    _pageCtrl.position.haveDimensions) {
                  page = _pageCtrl.page ?? page;
                }
                final delta = profileIdx - page; // -1 … 1 pendant le geste
                if (delta == 0 || delta.abs() >= 1) return child!;
                return Transform(
                  alignment: delta < 0
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateY(-pi / 2 * delta),
                  child: child,
                );
              },
            ),
          ),
          // ✅ IgnorePointer : un DecoratedBox à dégradé « attrape » les
          // touchers. Ces deux voiles (moitié haute + 200 px du bas)
          // empêchaient le PageView de recevoir le balayage : il fallait
          // viser le milieu de l'écran ou taper pour changer de story.
          const IgnorePointer(
            child: DecoratedBox(
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.center,
                        colors: [Color(0xCC000000), Colors.transparent]))),
          ),
          const IgnorePointer(
            child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                    height: 200,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.center,
                                colors: [
                          Color(0xBB000000),
                          Colors.transparent
                        ]))))),
          ),
          // ✅ Barre de progression — un segment par story DU PROFIL
          // COURANT UNIQUEMENT (se réinitialise à chaque changement
          // de profil), façon WhatsApp/Instagram.
          if (!_longPressing)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: Row(
                children: List.generate(_currentGroup.length, (i) {
              return Expanded(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: i == _storyIndexInProfile
                              ? AnimatedBuilder(
                                  animation: _progressCtrl,
                                  builder: (_, __) => LinearProgressIndicator(
                                      value: _progressCtrl.value,
                                      backgroundColor: Colors.white30,
                                      valueColor: const AlwaysStoppedAnimation(
                                          Colors.white),
                                      minHeight: 2.5))
                              : LinearProgressIndicator(
                                  value: i < _storyIndexInProfile ? 1.0 : 0.0,
                                  backgroundColor: Colors.white30,
                                  valueColor: const AlwaysStoppedAnimation(
                                      Colors.white),
                                  minHeight: 2.5))));
            })),
          ),
          if (!_longPressing)
          Positioned(
            top: MediaQuery.of(context).padding.top + 20,
            left: 12,
            right: 12,
            child: Row(children: [
              GestureDetector(
                  onTap: () => _openProfile(s),
                  child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2)),
                      child: ClipOval(
                          child: s.userPhotoUrl != null &&
                                  s.userPhotoUrl!.isNotEmpty
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
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16))))))),
              const SizedBox(width: 10),
              Expanded(
                  child: GestureDetector(
                      onTap: () => _openProfile(s),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(s.userName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700)),
                                ),
                                if (s.visibility == 'amis') ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0A84FF),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text('👥 Amis',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ],
                                if (s.visibility == 'friends') ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.online,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.star_rounded,
                                              size: 11, color: Colors.white),
                                          SizedBox(width: 2),
                                          Text('Amis proches',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight:
                                                      FontWeight.w700)),
                                        ]),
                                  ),
                                ],
                              ],
                            ),
                            Text(_ago(s.createdAt),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 11)),
                          ]))),
              ...[
                GestureDetector(
                  onTap: () {
                    _pause();
                    if (isOwner) {
                      _showStoryOptions(s);
                    } else {
                      _reportStory(s);
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.more_horiz_rounded,
                        color: Colors.white, size: 26,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 6)]),
                  ),
                ),
              ],
            ]),
          ),
          if (!_longPressing && !_replyFocused)
            CoucheStickers(s.stickers),
          if (!_longPressing)
            // Légende placée par l'auteur (éditeur façon Snap)
            if (s.legendePlacee &&
                (s.caption ?? '').isNotEmpty &&
                !_replyFocused)
              LegendePlacee(
                texte: s.caption!,
                x: s.legendeX!,
                y: s.legendeY!,
                echelle: s.legendeEchelle ?? 1,
              ),
          // Légende classique (non placée) en bas de la story
          if (s.caption != null &&
              s.caption!.isNotEmpty &&
              !s.legendePlacee &&
              !_replyFocused &&
              !_longPressing)
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: IgnorePointer(
                child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(s.caption!,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14, height: 1.4))),
              ),
            ),
              ]),
            ),
          ),

          // ── Barre du bas, séparée de la story : répondre / vues ──
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            left: 0,
            right: 0,
            bottom: keyboardH,
            child: GestureDetector(
              // un toucher dans la barre ne fait pas avancer la story
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              onVerticalDragEnd: (_) {},
              child: Container(
                color: Colors.black,
                padding: EdgeInsets.fromLTRB(
                    12, 8, 12, keyboardH > 0 ? 8 : bottomPad + 8),
                child: isOwner
                    ? _barreProprietaire(s)
                    : BarreReponseStory(
                        key: ValueKey('reponse_${s.id}'),
                        story: s,
                        aime: _likedStoryIds.contains(s.id),
                        demandeClavier: _demandeClavier,
                        onLike: () => _likeStory(s),
                        onFocusChanged: (focused) {
                          setState(() => _replyFocused = focused);
                          if (focused) {
                            _pause();
                          } else {
                            _resume();
                          }
                        }),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  /// Hauteur de la barre du bas (hors marge système).
  static const double _hauteurBarre = 60;

  /// Ma story : nombre de vues (→ liste) à la place de la réponse.
  Widget _barreProprietaire(StoryModel s) => SizedBox(
        height: 44,
        child: Row(children: [
          GestureDetector(
            onTap: () => _showViewers(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.remove_red_eye_outlined,
                    color: Colors.white, size: 17),
                const SizedBox(width: 7),
                Text(
                    '${s.viewedBy.length} vue${s.viewedBy.length != 1 ? 's' : ''}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded,
                    color: Colors.white54, size: 18),
              ]),
            ),
          ),
        ]),
      );

  /// Construit la page pour le profil `profileIndex`. Seule la page
  /// du profil ACTUELLEMENT AFFICHÉ montre la story interactive
  /// (vidéo qui joue, liée à la barre de progression) ; les pages
  /// voisines (visibles brièvement pendant un glissement en cours)
  /// affichent un simple aperçu statique de leur première story.
  Widget _buildProfilePage(int profileIndex) {
    if (profileIndex != _profileIndex) {
      return _buildStaticPreview(_groups[profileIndex].first);
    }
    return _buildMedia(_currentStory);
  }

  Widget _buildStaticPreview(StoryModel s) {
    if (s.isTextStory) {
      return _buildTextStoryContent(s);
    }
    if (s.isVideo) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Icon(Icons.play_circle_outline_rounded,
              color: Colors.white38, size: 48),
        ),
      );
    }
    return CachedNetworkImage(
        imageUrl: s.mediaUrl,
        fit: BoxFit.contain,
        placeholder: (_, __) => const Center(
            child:
                CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
        errorWidget: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image_outlined,
                color: Colors.white38, size: 48)));
  }

  Widget _buildMedia(StoryModel s) {
    if (s.isTextStory) {
      return _buildTextStoryContent(s);
    }
    if (s.isVideo) {
      if (!_videoReady || _videoCtrl == null) {
        return const Center(
            child:
                CircularProgressIndicator(color: Colors.white, strokeWidth: 2));
      }
      return Center(
          child: AspectRatio(
              aspectRatio: _videoCtrl!.value.aspectRatio,
              child: VideoPlayer(_videoCtrl!)));
    }
    return CachedNetworkImage(
        imageUrl: s.mediaUrl,
        fit: BoxFit.contain,
        placeholder: (_, __) => const Center(
            child:
                CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
        errorWidget: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image_outlined,
                color: Colors.white38, size: 48)));
  }

  Widget _buildTextStoryContent(StoryModel s) {
    return Container(
      color: _colorFromHex(s.bgColor ?? '#7B2FFF'),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        s.textContent ?? '',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          height: 1.3,
        ),
      ),
    );
  }

  void _showViewers(StoryModel s) {
    _chainingModal = false;
    if (s.userId != _myUid) {
      _resumeWhenVisible();
      return;
    }
    // ✅ Pause pendant que la liste des vues est ouverte : sinon la
    // minuterie avançait sous la feuille et, sur la dernière story,
    // Get.back() fermait la feuille au lieu du viewer.
    _pause();
    final viewers = s.viewedBy;
    final storyId = s.id;
    final freeCount = viewers.length.clamp(0, _freeViewersLimit);
    final lockedCount = (viewers.length - _freeViewersLimit).clamp(0, 999);

    Get.bottomSheet(Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(Get.context!).size.height * 0.65),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              Icon(Icons.remove_red_eye_outlined,
                  color: AppColors.textMuted, size: 18),
              const SizedBox(width: 8),
              Text('${viewers.length} vue${viewers.length != 1 ? 's' : ''}',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 12),
            if (viewers.isEmpty)
              Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child: Text("Personne n'a encore vu cette story",
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 14))))
            else
              Flexible(
                  child: ListView(shrinkWrap: true, children: [
                ...viewers.take(freeCount).map((uid) => _ViewerTileWithLike(
                    uid: uid, storyId: storyId, key: ValueKey(uid))),
                if (lockedCount > 0) ...[
                  const SizedBox(height: 8),
                  Stack(children: [
                    Column(
                        children: List.generate(
                            lockedCount.clamp(0, 3),
                            (_) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Row(children: [
                                  Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppColors.surface2
                                              .withOpacity(0.5))),
                                  const SizedBox(width: 10),
                                  Container(
                                      width: 120,
                                      height: 12,
                                      decoration: BoxDecoration(
                                          color: AppColors.surface2
                                              .withOpacity(0.5),
                                          borderRadius:
                                              BorderRadius.circular(6))),
                                ])))),
                    Positioned.fill(
                        child: Container(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                            Colors.transparent,
                            AppColors.surface.withOpacity(0.9),
                            AppColors.surface
                          ])),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: AppColors.gradientPink),
                                child: const Icon(Icons.lock_rounded,
                                    color: Colors.white, size: 22)),
                            const SizedBox(height: 10),
                            Text(
                                '+$lockedCount profil${lockedCount > 1 ? 's' : ''} masqué${lockedCount > 1 ? 's' : ''}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                            const SizedBox(height: 6),
                            Text('Passe en Premium pour tout voir',
                                style: TextStyle(
                                    color: AppColors.textMuted, fontSize: 12)),
                            const SizedBox(height: 14),
                            GestureDetector(
                                onTap: () {
                                  Get.back();
                                  Get.snackbar(
                                      '⭐ Premium', 'Bientôt disponible !',
                                      snackPosition: SnackPosition.TOP,
                                      backgroundColor: AppColors.surface,
                                      colorText: Colors.white);
                                },
                                child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 10),
                                    decoration: BoxDecoration(
                                        gradient: AppColors.gradientPink,
                                        borderRadius:
                                            BorderRadius.circular(20)),
                                    child: const Text('Débloquer',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13)))),
                          ]),
                    )),
                  ]),
                ],
              ])),
          ]),
    )).then((_) => _resumeWhenVisible());
  }

  String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 0) return 'il y a ${diff.inDays}j';
    if (diff.inHours > 0) return 'il y a ${diff.inHours}h';
    if (diff.inMinutes > 0) return 'il y a ${diff.inMinutes}min';
    return "à l'instant";
  }
}

// ─── OPTION TILE ─────────────────────────────────────────────────

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 16),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

class _OptionDivider extends StatelessWidget {
  const _OptionDivider();
  @override
  Widget build(BuildContext context) {
    return const Divider(
        height: 1, color: Colors.white10, indent: 20, endIndent: 20);
  }
}

// ─── TUILE VIEWER ────────────────────────────────────────────────

class _ViewerTile extends StatefulWidget {
  final String uid;
  const _ViewerTile({required this.uid, super.key});
  @override
  State<_ViewerTile> createState() => _ViewerTileState();
}

class _ViewerTileState extends State<_ViewerTile> {
  String _name = '';
  String? _photoUrl;
  bool _loading = true;
  Map<String, dynamic>? _fullData;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', widget.uid)
          .maybeSingle();
      if (mounted && data != null) {
        setState(() {
          _name = data['name'] ?? 'Utilisateur';
          _photoUrl = data['photo_url'];
          _fullData = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openProfile() {
    if (_fullData == null) return;
    Get.back();
    final user = profilComplet(_fullData!);
    Get.toNamed('/profile/view', arguments: user);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _loading ? null : _openProfile,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, gradient: AppColors.gradientPink),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : ClipOval(
                      child: _photoUrl != null
                          ? CachedNetworkImage(
                              imageUrl: _photoUrl!, fit: BoxFit.cover)
                          : Center(
                              child: Text(
                                  _name.isNotEmpty
                                      ? _name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16))))),
          const SizedBox(width: 12),
          Expanded(
              child: _loading
                  ? Container(
                      height: 10,
                      decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(5)))
                  : Text(_name,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600))),
          if (!_loading)
            Icon(Icons.arrow_forward_ios_rounded,
                color: AppColors.textMuted, size: 14),
        ]),
      ),
    );
  }
}

// ─── TUILE VIEWER AVEC LIKE ───────────────────────────────────────

class _ViewerTileWithLike extends StatefulWidget {
  final String uid;
  final String storyId;
  const _ViewerTileWithLike(
      {required this.uid, required this.storyId, super.key});
  @override
  State<_ViewerTileWithLike> createState() => _ViewerTileWithLikeState();
}

class _ViewerTileWithLikeState extends State<_ViewerTileWithLike> {
  String _name = '';
  String? _photoUrl;
  bool _loading = true;
  bool _hasLiked = false;
  Map<String, dynamic>? _fullData;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', widget.uid)
            .maybeSingle(),
        Supabase.instance.client
            .from('stories')
            .select('liked_by')
            .eq('id', widget.storyId)
            .maybeSingle(),
      ]);
      final profileData = results[0];
      final storyData = results[1];
      if (mounted) {
        final liked = List<String>.from(storyData?['liked_by'] ?? []);
        setState(() {
          if (profileData != null) {
            _name = profileData['name'] ?? 'Utilisateur';
            _photoUrl = profileData['photo_url'];
            _fullData = profileData;
          }
          _hasLiked = liked.contains(widget.uid);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openProfile() {
    if (_fullData == null) return;
    Get.back();
    final user = profilComplet(_fullData!);
    Get.toNamed('/profile/view', arguments: user);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _loading ? null : _openProfile,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, gradient: AppColors.gradientPink),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : ClipOval(
                      child: _photoUrl != null
                          ? CachedNetworkImage(
                              imageUrl: _photoUrl!, fit: BoxFit.cover)
                          : Center(
                              child: Text(
                                  _name.isNotEmpty
                                      ? _name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16))))),
          const SizedBox(width: 12),
          Expanded(
              child: _loading
                  ? Container(
                      height: 10,
                      decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(5)))
                  : Text(_name,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600))),
          if (!_loading && _hasLiked) ...[
            const Text('❤️', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
          ],
          if (!_loading)
            Icon(Icons.arrow_forward_ios_rounded,
                color: AppColors.textMuted, size: 14),
        ]),
      ),
    );
  }
}

// ─── REPLY BAR ────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────
//  ADD STORY SCREEN
//  Publication façon Snapchat/TikTok : on quitte l'écran
//  immédiatement, l'upload continue en tâche de fond via
//  HomeController.publishStory() (controller persistant).
// ─────────────────────────────────────────────────────────────────

class AddStoryScreen extends StatefulWidget {
  const AddStoryScreen({super.key});
  @override
  State<AddStoryScreen> createState() => _AddStoryScreenState();
}

class _AddStoryScreenState extends State<AddStoryScreen> {
  final _picker = ImagePicker();
  String? _previewPath;
  bool _isVideo = false;
  final _captionCtrl = TextEditingController();

  // ── Éditeur façon Snap ──
  // Photo : zoom / cadrage (pincer, glisser), capturé à la publication.
  final _photoKey = GlobalKey();
  final _cadrage = TransformationController();
  // Légende : position (centre, fraction de l'écran) et taille.
  bool _editionLegende = false;
  Offset _legendePos = const Offset(0.5, 0.72);
  double _legendeEchelle = 1.0;
  double _echelleAuDepart = 1.0;
  // Vidéo : passage gardé (secondes), 30 s maximum.
  static const _dureeMaxStory = 30.0;
  Duration _dureeVideo = Duration.zero;
  RangeValues? _decoupe;
  bool _preparation = false; // découpe en cours avant l'envoi

  double _durationHours = 24;
  String _visibility = 'public';
  Future<int>? _nbAmisProches; // compteur de la liste, chargé une fois
  Future<int>? _nbMasques;
  // Stickers / emoji / GIF posés sur la story
  final List<StickerStory> _stickers = [];
  // Identifiant fixe de chaque sticker (sinon Flutter recrée le widget à
  // chaque mouvement et le geste en cours est perdu)
  final List<int> _stickerIds = [];
  int _prochainStickerId = 0;
  bool _deplacementSticker = false;
  int? _texteEdite; // index du texte modifié, -1 = nouveau, null = aucun
  bool _surCorbeille = false;

  bool _textMode = false;
  final _textCtrl = TextEditingController();
  Color _selectedBgColor = _textBgColors.first;

  static const List<Color> _textBgColors = [
    Color(0xFF7B2FFF),
    Color(0xFFFF3CAC),
    Color(0xFF2E63FF),
    Color(0xFF00B894),
    Color(0xFFFFA500),
    Color(0xFFE53935),
    Color(0xFF0A0A0F),
  ];

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(() => setState(() {}));
  }

  // Selfie : photo montrée (et publiée) comme dans le miroir de la caméra
  bool _miroir = false;
  // Story rattachée à l'événement en cours (« 📸 Stories de l'événement »)
  bool _avecEvenement = false;

  EvenementModel? get _evenementEnCours =>
      Get.isRegistered<EvenementsController>()
          ? EvenementsController.to.evenementEnCoursPourMoi
          : null;

  void _setMedia(String chemin, bool video, [bool miroir = false]) =>
      setState(() {
        CameraStory.memoriserDernierMedia(chemin, video);
        _miroir = miroir && !video;
        _stickers.clear();
        _stickerIds.clear();
        _previewPath = chemin;
        _isVideo = video;
        _cadrage.value = Matrix4.identity();
        _dureeVideo = Duration.zero;
        _decoupe = null;
      });

  static final _extVideo = RegExp(r'\.(mp4|mov|3gp|mkv|webm|avi|m4v)$',
      caseSensitive: false);

  /// Vidéo ? Par l'extension, le type MIME, sinon l'en-tête du fichier
  /// (certaines galeries renvoient un fichier sans extension).
  static Future<bool> _estVideo(XFile f) async {
    if (_extVideo.hasMatch(f.path)) return true;
    final mime = f.mimeType ?? '';
    if (mime.startsWith('video/')) return true;
    if (mime.startsWith('image/')) return false;
    try {
      final raf = await File(f.path).open();
      final h = await raf.read(12);
      await raf.close();
      if (h.length < 12) return false;
      // MP4 / MOV / 3GP : « ftyp » à l'octet 4 (sauf HEIC / AVIF = images)
      if (String.fromCharCodes(h.sublist(4, 8)) == 'ftyp') {
        final marque = String.fromCharCodes(h.sublist(8, 12));
        return !const {'heic', 'heix', 'mif1', 'msf1', 'avif', 'hevc'}
            .contains(marque);
      }
      // MKV / WEBM
      return h[0] == 0x1A && h[1] == 0x45 && h[2] == 0xDF && h[3] == 0xA3;
    } catch (_) {
      return false;
    }
  }

  /// Galerie : photo OU vidéo dans le même sélecteur.
  Future<void> _pickGalerie() async {
    try {
      final file = await _picker.pickMedia(
          maxWidth: 1080, maxHeight: 1920, imageQuality: 85);
      if (file == null) return;
      _setMedia(file.path, await _estVideo(file));
    } catch (_) {
      _snack('Erreur lors de la sélection');
    }
  }

  Future<void> _publish() async {
    if (_previewPath == null) return;

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      _snack('Tu dois être connecté');
      return;
    }

    final file = File(_previewPath!);
    if (!await file.exists()) {
      _snack('Fichier introuvable');
      return;
    }

    final ext = _previewPath!.split('.').last.toLowerCase();
    const allowedImg = ['jpg', 'jpeg', 'png', 'webp', 'heic'];
    const allowedVid = ['mp4', 'mov', 'avi', 'mkv'];
    if (!(_isVideo ? allowedVid : allowedImg).contains(ext)) {
      _snack('Format non supporté');
      return;
    }

    final caption = _captionCtrl.text.trim();
    final safeCaption = caption.isNotEmpty
        ? caption.substring(0, caption.length.clamp(0, 200))
        : null;

    // Photo zoomée / recadrée : on publie exactement ce qui est à l'écran.
    var fichier = file;
    // Recadrée ou selfie en miroir : on publie exactement ce qui est affiché
    if (!_isVideo && (!_cadrage.value.isIdentity() || _miroir)) {
      fichier = await _capturerCadrage() ?? file;
    }

    final evenement = _avecEvenement ? _evenementEnCours : null;
    final edition = <String, dynamic>{
      if (evenement != null) 'evenement_id': evenement.id,
      if (_stickers.isNotEmpty)
        'stickers': _stickers.map((s) => s.toJson()).toList(),
      if (safeCaption != null) ...{
        'legende_x': _legendePos.dx,
        'legende_y': _legendePos.dy,
        'legende_echelle': _legendeEchelle,
      },
    };
    final decoupe = _decoupe;
    if (_isVideo && decoupe != null && _dureeVideo > Duration.zero) {
      final debut = (decoupe.start * 1000).round();
      final fin = (decoupe.end * 1000).round();
      // Seulement si la vidéo a vraiment été raccourcie
      if (debut > 0 || fin < _dureeVideo.inMilliseconds - 300) {
        setState(() => _preparation = true);
        final coupe = await _decouperVideo(file.path, debut, fin);
        if (mounted) setState(() => _preparation = false);
        if (coupe != null) {
          // ✅ Comme WhatsApp : seul le passage choisi est envoyé
          fichier = coupe;
        } else {
          // Découpe impossible sur ce téléphone : vidéo entière, mais le
          // lecteur ne joue que le passage choisi.
          edition['video_debut_ms'] = debut;
          edition['video_fin_ms'] = fin;
        }
      }
    }

    if (!mounted) return;
    if (!Get.isRegistered<HomeController>()) {
      Get.put(HomeController(), permanent: true);
    }
    final homeCtrl = Get.find<HomeController>();

    // ✅ Retour immédiat façon Snapchat/TikTok — on ne bloque pas l'utilisateur
    Get.back(result: true);

    // ✅ Upload en tâche de fond, piloté par HomeController (persistant).
    // Le cercle "Toi" sur l'accueil / la page Story affiche la progression.
    homeCtrl.publishStory(
      file: fichier,
      isVideo: _isVideo,
      caption: safeCaption,
      durationHours: _durationHours,
      visibility: _visibility,
      edition: edition,
    );
  }

  static const _canalVideo = MethodChannel('zamu/video');

  /// Copie du passage [debutMs, finMs] (MainActivity.kt, sans réencodage).
  Future<File?> _decouperVideo(String chemin, int debutMs, int finMs) async {
    try {
      final sortie = await _canalVideo.invokeMethod<String>('decouper', {
        'chemin': chemin,
        'debutMs': debutMs,
        'finMs': finMs,
      });
      if (sortie == null) return null;
      final f = File(sortie);
      return await f.exists() && await f.length() > 0 ? f : null;
    } catch (e) {
      debugPrint('Découpe vidéo impossible : $e');
      return null;
    }
  }

  /// Image de la photo telle que cadrée à l'écran (JPEG ~1080 px de large).
  Future<File?> _capturerCadrage() async {
    try {
      final boundary = _photoKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final ratio = 1080 / boundary.size.width;
      final image = await boundary.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      final jpg = await compute(_encoderJpeg, {
        'w': image.width,
        'h': image.height,
        'rgba': data.buffer.asUint8List(),
      });
      final dir = await getTemporaryDirectory();
      final f = File(
          '${dir.path}/story_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await f.writeAsBytes(jpg);
      return f;
    } catch (e) {
      debugPrint('Cadrage de la photo impossible : $e');
      return null;
    }
  }

  Future<void> _publishText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      _snack('Tu dois être connecté');
      return;
    }

    if (!Get.isRegistered<HomeController>()) {
      Get.put(HomeController(), permanent: true);
    }
    final homeCtrl = Get.find<HomeController>();

    final bgHex =
        '#${_selectedBgColor.value.toRadixString(16).substring(2).toUpperCase()}';

    Get.back(result: true);

    homeCtrl.publishTextStory(
      text: text,
      bgColorHex: bgHex,
      durationHours: _durationHours,
      visibility: _visibility,
    );
  }

  void _snack(String msg) => Get.snackbar('Erreur', msg,
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface,
      colorText: Colors.white);

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: AppColors.surface2,
                              borderRadius: BorderRadius.circular(2))),
                    ),
                    const SizedBox(height: 20),
                    const Text('Durée de la story',
                        style: TextStyle(
                            fontFamily: 'Syne',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(_formatDuration(_durationHours),
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w900)),
                    Slider(
                      value: _durationHours,
                      min: 1,
                      max: 48,
                      divisions: 47,
                      activeColor: AppColors.accent,
                      inactiveColor: AppColors.border,
                      label: _formatDuration(_durationHours),
                      onChanged: (v) {
                        setSheetState(() => _durationHours = v);
                        setState(() => _durationHours = v);
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('1h',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.textMuted)),
                        Text('48h',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text('Qui peut voir cette story',
                        style: TextStyle(
                            fontFamily: 'Syne',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _VisibilityChip(
                            icon: Icons.public_rounded,
                            label: 'Publique',
                            selected: _visibility == 'public',
                            onTap: () {
                              setSheetState(() => _visibility = 'public');
                              setState(() => _visibility = 'public');
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _VisibilityChip(
                            icon: Icons.star_rounded,
                            label: 'Amis proches',
                            selected: _visibility == 'friends',
                            onTap: () {
                              setSheetState(() => _visibility = 'friends');
                              setState(() => _visibility = 'friends');
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Liste « Amis proches » : nombre + gestion
                    FutureBuilder<int>(
                      future: _nbAmisProches ??= nombreAmisProches(),
                      builder: (_, snap) {
                        final n = snap.data;
                        final vide = n == 0 && _visibility == 'friends';
                        return GestureDetector(
                          onTap: () async {
                            await Get.to(() => const EcranAmisProches());
                            _nbAmisProches = nombreAmisProches();
                            setSheetState(() {}); // recompte
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: vide
                                      ? AppColors.error
                                      : AppColors.border),
                            ),
                            child: Row(children: [
                              Icon(Icons.star_rounded,
                                  color: AppColors.online, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                    vide
                                        ? 'Ta liste est vide : personne ne verra cette story'
                                        : n == null
                                            ? 'Ma liste Amis proches'
                                            : 'Ma liste Amis proches ($n)',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: vide
                                            ? AppColors.error
                                            : AppColors.textPrimary)),
                              ),
                              Text('Gérer',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.accent)),
                            ]),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    // Masquer à : ne voient aucune de mes stories
                    GestureDetector(
                      onTap: () async {
                        await Get.to(() => const EcranAmisProches(
                            liste: ListeStory.masques));
                        _nbMasques = nombreDansListe(ListeStory.masques);
                        setSheetState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(children: [
                          Icon(Icons.block_rounded,
                              color: AppColors.error, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FutureBuilder<int>(
                              future: _nbMasques ??=
                                  nombreDansListe(ListeStory.masques),
                              builder: (_, snap) => Text(
                                  snap.data == null || snap.data == 0
                                      ? 'Masquer ma story à…'
                                      : 'Masquée à ${snap.data} personne${snap.data! > 1 ? 's' : ''}',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary)),
                            ),
                          ),
                          Text('Gérer',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.accent)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: AppColors.gradientPink,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text('OK',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatDuration(double hours) {
    if (hours < 1) return '${(hours * 60).round()} min';
    if (hours < 24) return '${hours.round()}h';
    final days = hours / 24;
    if (days == days.roundToDouble()) return '${days.round()}j';
    return '${hours.round()}h';
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _cadrage.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canPublishText = _textMode && _textCtrl.text.trim().isNotEmpty;

    // Caméra Zamu plein écran tant qu'aucun média n'est choisi
    if (!_textMode && _previewPath == null) {
      return CameraStory(
        onMedia: _setMedia,
        onGalerie: _pickGalerie,
        onTexte: () => setState(() => _textMode = true),
        onFermer: () => Get.back(result: false),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Nouvelle story',
            style: TextStyle(
                color: Colors.white,
                fontFamily: 'Syne',
                fontWeight: FontWeight.w800)),
        leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () {
              if (_textMode) {
                setState(() => _textMode = false);
              } else {
                Get.back(result: false);
              }
            }),
        actions: [
          if (canPublishText)
            GestureDetector(
                onTap: _preparation
                    ? null
                    : (_textMode ? _publishText : _publish),
                child: Container(
                    margin: const EdgeInsets.only(right: 16),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                        gradient: AppColors.gradientPink,
                        borderRadius: BorderRadius.circular(20)),
                    child: _preparation
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Publier',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14))))
        ],
      ),
      body: _textMode
          ? _buildTextComposer()
          : _buildPreview(),
    );
  }

  Widget _buildTextComposer() {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity;
        if (v == null) return;
        final idx = _textBgColors.indexOf(_selectedBgColor);
        setState(() {
          if (v < 0) {
            _selectedBgColor = _textBgColors[(idx + 1) % _textBgColors.length];
          } else if (v > 0) {
            _selectedBgColor = _textBgColors[
                (idx - 1 + _textBgColors.length) % _textBgColors.length];
          }
        });
      },
      child: Container(
        color: _selectedBgColor,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _textBgColors.map((c) {
                  final isSel = c == _selectedBgColor;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: isSel ? 12 : 8,
                    height: isSel ? 12 : 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  );
                }).toList(),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: TextField(
                      controller: _textCtrl,
                      autofocus: true,
                      maxLines: null,
                      maxLength: 200,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                      cursorColor: Colors.white,
                      buildCounter: (_,
                              {required currentLength,
                              required isFocused,
                              maxLength}) =>
                          null,
                      decoration: const InputDecoration(
                        hintText: 'Tape ton texte...',
                        hintStyle: TextStyle(color: Colors.white70),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: GestureDetector(
                  onTap: _showSettingsSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        Text(_formatDuration(_durationHours),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 10),
                        Icon(
                            _visibility == 'public'
                                ? Icons.public_rounded
                                : Icons.star_rounded,
                            color: Colors.white,
                            size: 16),
                        const SizedBox(width: 6),
                        Text(_visibility == 'public' ? 'Publique' : 'Amis proches',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() => LayoutBuilder(builder: (context, box) {
        final legende = _captionCtrl.text.trim();
        return Stack(fit: StackFit.expand, children: [
          // ── Média : photo zoomable / vidéo raccourcie ──
          if (_isVideo)
            _VideoPreview(
              path: _previewPath!,
              debut: _decoupe == null
                  ? null
                  : Duration(milliseconds: (_decoupe!.start * 1000).round()),
              fin: _decoupe == null
                  ? null
                  : Duration(milliseconds: (_decoupe!.end * 1000).round()),
              onDuree: (d) => setState(() {
                _dureeVideo = d;
                final sec = d.inMilliseconds / 1000;
                _decoupe ??= RangeValues(0, sec.clamp(0, _dureeMaxStory));
              }),
            )
          else
            RepaintBoundary(
              key: _photoKey,
              child: Container(
                color: Colors.black,
                child: InteractiveViewer(
                  transformationController: _cadrage,
                  minScale: 1,
                  maxScale: 5,
                  child: SizedBox.expand(
                      child:
                          Transform.flip(
                              flipX: _miroir,
                              child: Image.file(File(_previewPath!),
                                  fit: BoxFit.contain))),
                ),
              ),
            ),

          // ── Légende : glisser pour déplacer, pincer pour agrandir ──
          if (legende.isNotEmpty && !_editionLegende)
            Positioned(
              left: _legendePos.dx * box.maxWidth,
              top: _legendePos.dy * box.maxHeight,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -0.5),
                child: GestureDetector(
                  onTap: () => setState(() => _editionLegende = true),
                  onScaleStart: (_) => _echelleAuDepart = _legendeEchelle,
                  onScaleUpdate: (d) => setState(() {
                    _legendePos = Offset(
                      (_legendePos.dx + d.focalPointDelta.dx / box.maxWidth)
                          .clamp(0.08, 0.92),
                      (_legendePos.dy + d.focalPointDelta.dy / box.maxHeight)
                          .clamp(0.08, 0.92),
                    );
                    _legendeEchelle =
                        (_echelleAuDepart * d.scale).clamp(0.6, 3.0);
                  }),
                  child: BulleLegende(texte: legende, echelle: _legendeEchelle),
                ),
              ),
            ),

          // ── Saisie de la légende ──
          if (_editionLegende)
            GestureDetector(
              onTap: () => setState(() => _editionLegende = false),
              child: Container(
                color: Colors.black54,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  controller: _captionCtrl,
                  autofocus: true,
                  maxLength: 200,
                  maxLines: 4,
                  minLines: 1,
                  textAlign: TextAlign.center,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => setState(() => _editionLegende = false),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    hintText: 'Écris ta légende…',
                    hintStyle: TextStyle(color: Colors.white54),
                    border: InputBorder.none,
                    counterStyle: TextStyle(color: Colors.white38),
                  ),
                ),
              ),
            ),

          // ── Stickers : glisser, pincer pour agrandir / tourner ──
          if (!_editionLegende)
            for (var i = 0; i < _stickers.length; i++)
              if (_texteEdite != i)
              StickerEditable(
                key: ValueKey(_stickerIds[i]),
                sticker: _stickers[i],
                zone: Size(box.maxWidth, box.maxHeight),
                onChange: (n) => setState(() => _stickers[i] = n),
                onTap: _stickers[i].estTexte ? () => _ouvrirTexte(i) : null,
                onBouge: (enCours, doigt) {
                  if (!enCours) {
                    setState(() {
                      if (_surCorbeille && i < _stickers.length) {
                        _stickers.removeAt(i);
                        _stickerIds.removeAt(i);
                      }
                      _deplacementSticker = false;
                      _surCorbeille = false;
                    });
                    return;
                  }
                  // Corbeille : en bas au centre de l'écran
                  final ecran = MediaQuery.of(context).size;
                  final sur = doigt != null &&
                      (doigt - Offset(ecran.width / 2, ecran.height - 80))
                              .distance <
                          60;
                  if (!_deplacementSticker || sur != _surCorbeille) {
                    setState(() {
                      _deplacementSticker = true;
                      _surCorbeille = sur;
                    });
                  }
                },
              ),
          if (_deplacementSticker)
            Positioned(
              left: 0,
              right: 0,
              bottom: 50,
              child: Center(
                  child: IgnorePointer(
                      child: CorbeilleSticker(survolee: _surCorbeille))),
            ),

          // ── Aide ──
          if (!_editionLegende && !_deplacementSticker)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Text(
                    _isVideo
                        ? 'Choisis le passage à garder en bas'
                        : 'Pince pour zoomer · glisse pour cadrer',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        shadows: [Shadow(blurRadius: 4)])),
              ),
            ),

          // ── Saisie d'un texte (gras, fond, couleur) ──
          if (_texteEdite != null)
            Positioned.fill(
              child: EditeurTexteStory(
                initial: (_texteEdite! >= 0 && _texteEdite! < _stickers.length)
                    ? _stickers[_texteEdite!]
                    : null,
                onValider: _validerTexte,
              ),
            ),

          // ── Barre du bas ──
          if (!_editionLegende && !_deplacementSticker && _texteEdite == null)
            Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                    top: false,
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_isVideo && _decoupe != null) _barreDecoupe(),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(children: [
                              _BoutonEditeur(
                                icon: Icons.text_fields_rounded,
                                label: 'Texte',
                                actif: _stickers.any((s) => s.estTexte),
                                onTap: _ouvrirTexte,
                              ),
                              const SizedBox(width: 8),
                              _BoutonEditeur(
                                icon: Icons.emoji_emotions_rounded,
                                label: 'Stickers',
                                actif: _stickers.isNotEmpty,
                                onTap: _ajouterSticker,
                              ),
                              if (!_isVideo &&
                                  !_cadrage.value.isIdentity()) ...[
                                const SizedBox(width: 8),
                                _BoutonEditeur(
                                  icon: Icons.crop_free_rounded,
                                  label: 'Recadrer',
                                  onTap: () => setState(() =>
                                      _cadrage.value = Matrix4.identity()),
                                ),
                              ],
                              const SizedBox(width: 8),
                              _BoutonEditeur(
                                icon: Icons.refresh_rounded,
                                label: 'Reprendre',
                                onTap: () =>
                                    setState(() => _previewPath = null),
                              ),
                            ])),
                            if (_evenementEnCours != null) ...[
                              const SizedBox(height: 10),
                              _puceEvenement(_evenementEnCours!),
                            ],
                            const SizedBox(height: 12),
                            _barrePublication(),
                          ],
                        )))),
        ]);
      });

  void _ouvrirTexte([int index = -1]) =>
      setState(() => _texteEdite = index);

  void _validerTexte(String texte, bool gras, int couleur, int fond) {
    final i = _texteEdite;
    setState(() {
      _texteEdite = null;
      if (i == null) return;
      if (texte.isEmpty) {
        // Texte vidé : on le retire
        if (i >= 0 && i < _stickers.length) {
          _stickers.removeAt(i);
          _stickerIds.removeAt(i);
        }
        return;
      }
      if (i >= 0 && i < _stickers.length) {
        _stickers[i] = _stickers[i]
            .copyWith(valeur: texte, gras: gras, couleur: couleur, fond: fond);
      } else if (_stickers.length < 20) {
        final decalage = (_stickers.length % 5) * 0.05;
        _stickers.add(StickerStory(
            type: 'texte',
            valeur: texte,
            x: 0.5,
            y: 0.3 + decalage,
            gras: gras,
            couleur: couleur,
            fond: fond));
        _stickerIds.add(_prochainStickerId++);
      }
    });
  }

  Future<void> _ajouterSticker() async {
    if (_stickers.length >= 20) {
      _snack('20 stickers maximum par story');
      return;
    }
    final c = await choisirSticker(context, emojis: emojiStory);
    if (c == null || !mounted) return;
    final StickerStory s;
    if (c.emoji != null) {
      s = StickerStory(type: 'emoji', valeur: c.emoji!);
    } else if (estUrlGiphy(c.url)) {
      s = StickerStory(type: 'giphy', valeur: c.url);
    } else {
      return;
    }
    // Décalé un peu à chaque ajout pour ne pas empiler au même endroit
    final decalage = (_stickers.length % 5) * 0.04;
    setState(() {
      _stickers.add(s.copyWith(x: 0.5 + decalage, y: 0.38 + decalage));
      _stickerIds.add(_prochainStickerId++);
    });
  }

  /// « 📍 Ajouter à <événement> » : la story apparaît aussi sur la page
  /// de l'événement (Stories de l'événement).
  Widget _puceEvenement(EvenementModel ev) => GestureDetector(
        onTap: () => setState(() => _avecEvenement = !_avecEvenement),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _avecEvenement ? AppColors.online : Colors.black54,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: _avecEvenement ? Colors.transparent : Colors.white24),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                _avecEvenement
                    ? Icons.check_circle_rounded
                    : Icons.add_circle_outline_rounded,
                size: 16,
                color: Colors.white),
            const SizedBox(width: 6),
            Flexible(
              child: Text('${ev.emoji} Ajouter à « ${ev.titre} »',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      );

  /// Bas de l'éditeur façon Snap : à qui (Publique / ⭐ Amis proches),
  /// combien de temps, et Publier — sans ouvrir de menu.
  Widget _barrePublication() {
    Widget audience(String valeur, IconData icon, String label) {
      final actif = _visibility == valeur;
      return GestureDetector(
        onTap: () async {
          setState(() => _visibility = valeur);
          if (valeur != 'friends') return;
          final n = await (_nbAmisProches ??= nombreAmisProches());
          if (n == 0 && mounted) {
            Get.snackbar('Ta liste Amis proches est vide',
                'Ajoute des personnes, sinon personne ne verra cette story',
                snackPosition: SnackPosition.TOP,
                backgroundColor: AppColors.surface,
                colorText: Colors.white,
                mainButton: TextButton(
                  onPressed: () async {
                    await Get.to(() => const EcranAmisProches());
                    _nbAmisProches = nombreAmisProches();
                  },
                  child: Text('Gérer',
                      style: TextStyle(color: AppColors.accent)),
                ));
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: actif
                ? (valeur == 'friends' ? AppColors.online : Colors.white)
                : Colors.black54,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: actif ? Colors.transparent : Colors.white24),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: 15,
                color: actif && valeur != 'friends'
                    ? Colors.black
                    : Colors.white),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: actif && valeur != 'friends'
                        ? Colors.black
                        : Colors.white)),
          ]),
        ),
      );
    }

    return Row(children: [
      // Rétrécit sur les petits écrans plutôt que de déborder
      Expanded(
          child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(children: [
      audience('public', Icons.public_rounded, 'Publique'),
      const SizedBox(width: 6),
      audience('amis', Icons.group_rounded, 'Amis'),
      const SizedBox(width: 6),
      audience('friends', Icons.star_rounded, 'Proches'),
      const SizedBox(width: 6),
      // Durée (et liste Amis proches) : menu détaillé
      GestureDetector(
        onTap: _showSettingsSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.timer_outlined, size: 15, color: Colors.white),
            const SizedBox(width: 4),
            Text(_formatDuration(_durationHours),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ]),
        ),
      ),
              ]))),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: _preparation ? null : _publish,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: AppColors.gradientPink,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Center(
            child: _preparation
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Publier',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                    SizedBox(width: 6),
                    Icon(Icons.send_rounded, color: Colors.white, size: 16),
                  ]),
          ),
        ),
      ),
    ]);
  }

  /// Curseur à deux poignées : début et fin du passage gardé (30 s max).
  Widget _barreDecoupe() {
    final d = _decoupe!;
    final total = _dureeVideo.inMilliseconds / 1000;
    String mmss(double sec) {
      final t = sec.round();
      return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24)),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.content_cut_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text('${mmss(d.start)} – ${mmss(d.end)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('${(d.end - d.start).round()} s',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
        RangeSlider(
          values: d,
          min: 0,
          max: total <= 0 ? 1 : total,
          activeColor: AppColors.accent,
          inactiveColor: Colors.white24,
          onChanged: (v) => setState(() {
            var debut = v.start, fin = v.end;
            // 30 s maximum : on décale l'autre poignée
            if (fin - debut > _dureeMaxStory) {
              if (debut != d.start) {
                fin = debut + _dureeMaxStory;
              } else {
                debut = fin - _dureeMaxStory;
              }
            }
            if (fin - debut < 1) return; // 1 s minimum
            _decoupe = RangeValues(debut, fin);
          }),
        ),
      ]),
    );
  }
}

// ─── BOUTON DE L'ÉDITEUR ──────────────────────────────────────────

class _BoutonEditeur extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool actif;
  final VoidCallback onTap;
  const _BoutonEditeur(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.actif = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: actif ? AppColors.accent.withOpacity(0.2) : Colors.black54,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: actif ? AppColors.accent : Colors.white24)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// Encodage JPEG hors du fil principal (pas de saccade à la publication).
List<int> _encoderJpeg(Map<String, Object> m) {
  final image = img.Image.fromBytes(
    width: m['w'] as int,
    height: m['h'] as int,
    bytes: (m['rgba'] as Uint8List).buffer,
    numChannels: 4,
  );
  return img.encodeJpg(image, quality: 85);
}

// ─── PUCE DE VISIBILITÉ ───────────────────────────────────────────

class _VisibilityChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _VisibilityChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.gradientPink : null,
          color: selected ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? Colors.transparent : AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 20, color: selected ? Colors.white : AppColors.textMuted),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

// ─── VIDEO PREVIEW ────────────────────────────────────────────────

class _VideoPreview extends StatefulWidget {
  final String path;
  final Duration? debut, fin; // passage joué en boucle
  final ValueChanged<Duration>? onDuree;
  const _VideoPreview(
      {required this.path, this.debut, this.fin, this.onDuree});
  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ctrl = VideoPlayerController.file(File(widget.path));
    _ctrl = ctrl;
    try {
      await ctrl.initialize();
    } catch (e) {
      debugPrint('Aperçu vidéo impossible : $e');
      return;
    }
    if (!mounted) return;
    ctrl.setLooping(true);
    ctrl.addListener(_boucler);
    ctrl.play();
    setState(() => _ready = true);
    widget.onDuree?.call(ctrl.value.duration);
  }

  // Reboucle sur le passage choisi
  void _boucler() {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;
    final debut = widget.debut ?? Duration.zero;
    final fin = widget.fin;
    final pos = c.value.position;
    if ((fin != null && pos >= fin) || pos < debut - const Duration(milliseconds: 300)) {
      c.seekTo(debut);
    }
  }

  @override
  void didUpdateWidget(covariant _VideoPreview old) {
    super.didUpdateWidget(old);
    // Poignée « début » déplacée : on montre tout de suite ce passage
    if (old.debut != widget.debut && widget.debut != null) {
      _ctrl?.seekTo(widget.debut!);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _ctrl == null) {
      return const Center(
          child:
              CircularProgressIndicator(color: Colors.white, strokeWidth: 2));
    }
    return GestureDetector(
      onTap: () {
        if (_ctrl!.value.isPlaying) {
          _ctrl!.pause();
        } else {
          _ctrl!.play();
        }
        setState(() {});
      },
      child: Stack(fit: StackFit.expand, children: [
        Center(
            child: AspectRatio(
                aspectRatio: _ctrl!.value.aspectRatio,
                child: VideoPlayer(_ctrl!))),
        if (!_ctrl!.value.isPlaying)
          const Center(
              child: Icon(Icons.play_circle_filled_rounded,
                  color: Colors.white54, size: 72)),
      ]),
    );
  }
}

// ─── WIDGETS UTILITAIRES ─────────────────────────────────────────
