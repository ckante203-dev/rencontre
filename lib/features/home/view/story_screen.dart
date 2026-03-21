import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/shared/models/story_model.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/chat/model/message_model.dart';

class StoryViewerScreen extends StatefulWidget {
  final List<StoryModel> stories;
  final int initialIndex;

  const StoryViewerScreen(
      {super.key, required this.stories, this.initialIndex = 0});

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late int _current;
  late AnimationController _progressCtrl;
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;
  final String? _myUid = Supabase.instance.client.auth.currentUser?.id;
  bool _replyFocused = false;
  bool _paused = false;
  bool _longPressing = false;
  final Set<String> _likedStoryIds = {};

  static const Duration _imageDuration = Duration(seconds: 5);
  static const int _freeViewersLimit = 10;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    // ✅ FIX CRASH : protection liste vide
    _current = widget.stories.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.stories.length - 1);
    _progressCtrl = AnimationController(vsync: this);
    _progressCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _next();
    });
    if (widget.stories.isNotEmpty) {
      _loadStory(_current);
    }
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  Future<void> _loadStory(int index) async {
    _progressCtrl.stop();
    _progressCtrl.reset();
    await _videoCtrl?.dispose();
    _videoCtrl = null;
    if (mounted) setState(() => _videoReady = false);

    final s = widget.stories[index];
    if (s.isVideo) {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(s.mediaUrl));
      _videoCtrl = ctrl;
      await ctrl.initialize();
      if (!mounted) return;
      setState(() => _videoReady = true);
      ctrl.play();
      _progressCtrl.duration = ctrl.value.duration;
    } else {
      _progressCtrl.duration = _imageDuration;
    }
    _progressCtrl.forward();
    if (mounted) setState(() {});
    _loadLikes(s);
  }

  void _next() {
    if (_current < widget.stories.length - 1) {
      setState(() => _current++);
      _loadStory(_current);
    } else {
      Get.back();
    }
  }

  void _prev() {
    if (_current > 0) {
      setState(() => _current--);
      _loadStory(_current);
    }
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
      final row = await Supabase.instance.client
          .from('stories')
          .select('liked_by')
          .eq('id', story.id)
          .maybeSingle();
      if (row == null) return;
      final List<String> liked = List<String>.from(row['liked_by'] ?? []);
      if (alreadyLiked) {
        liked.remove(uid);
      } else if (!liked.contains(uid)) {
        liked.add(uid);
      }
      await Supabase.instance.client
          .from('stories')
          .update({'liked_by': liked}).eq('id', story.id);
    } catch (e) {
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
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', story.userId)
          .maybeSingle();
      if (data == null) return;
      int age = 0;
      final birthdate = data['birthdate'] ?? data['birth_date'];
      if (birthdate != null) {
        try {
          DateTime birth;
          if (birthdate.toString().contains('/')) {
            final parts = birthdate.toString().split('/');
            birth = DateTime(
                int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
          } else {
            birth = DateTime.parse(birthdate.toString());
          }
          final now = DateTime.now();
          age = now.year - birth.year;
          if (now.month < birth.month ||
              (now.month == birth.month && now.day < birth.day)) age--;
        } catch (_) {
          age = data['age'] ?? 0;
        }
      } else {
        age = data['age'] ?? 0;
      }
      final user = UserModel(
        id: data['id'] ?? story.userId,
        name: data['name'] ?? story.userName,
        age: age,
        bio: data['bio'],
        photoUrl: data['photo_url'] ?? story.userPhotoUrl,
        photoUrls: List<String>.from(data['photo_urls'] ?? []),
        interests: List<String>.from(data['interests'] ?? []),
        latitude: data['latitude']?.toDouble(),
        longitude: data['longitude']?.toDouble(),
        gender: data['gender'],
        lookingFor: data['looking_for'],
        isOnline: data['is_online'] ?? false,
        followersCount: data['followers_count'] ?? 0,
        followingCount: data['following_count'] ?? 0,
        matchesCount: data['matches_count'] ?? 0,
      );
      Get.toNamed('/profile/view', arguments: user);
    } catch (e) {
      debugPrint('_openProfile from story error: $e');
    }
  }

  Future<void> _deleteStory(StoryModel story) async {
    if (story.userId != _myUid) return;
    final confirmed = await Get.dialog<bool>(AlertDialog(
      backgroundColor: const Color(0xFF11111C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Supprimer cette story ?',
          style: TextStyle(
              color: Colors.white,
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              fontSize: 17)),
      content: const Text('Cette story sera définitivement supprimée.',
          style: TextStyle(color: Color(0xFF5A5A78), fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Annuler',
                style: TextStyle(
                    color: Color(0xFF5A5A78), fontWeight: FontWeight.w600))),
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
      _resume();
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
            backgroundColor: const Color(0xFF13131A),
            colorText: Colors.white,
            duration: const Duration(seconds: 2));
      }
    } catch (e) {
      debugPrint('_deleteStory error: $e');
      if (mounted) {
        Get.snackbar('Erreur', "Impossible de supprimer la story",
            snackPosition: SnackPosition.TOP,
            backgroundColor: const Color(0xFF13131A),
            colorText: Colors.white);
      }
    }
  }

  // ✅ NOUVEAU — Toggle épingler depuis le viewer
  Future<void> _togglePin(StoryModel story) async {
    final newVal = !story.isPinned;
    try {
      await Supabase.instance.client
          .from('stories')
          .update({'is_pinned': newVal}).eq('id', story.id);
      Get.snackbar(
        newVal ? '📌 Publiée sur ton profil' : '📌 Retirée du profil',
        '',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF13131A),
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      debugPrint('_togglePin error: $e');
      Get.snackbar('Erreur', 'Impossible de modifier',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white);
    }
  }

  // ✅ NOUVEAU — Menu style Telegram (3 points)
  void _showStoryOptions(StoryModel story) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle
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

          // ── Publier / retirer du profil ──────────────────
          _OptionTile(
            icon: story.isPinned
                ? Icons.push_pin_outlined
                : Icons.push_pin_rounded,
            label:
                story.isPinned ? 'Retirer du profil' : 'Publier sur le profil',
            color: story.isPinned ? Colors.red : Colors.white,
            onTap: () async {
              Get.back();
              await _togglePin(story);
              _resume();
            },
          ),
          const _OptionDivider(),

          // ── Vues ─────────────────────────────────────────
          _OptionTile(
            icon: Icons.remove_red_eye_rounded,
            label:
                '${story.viewedBy.length} vue${story.viewedBy.length != 1 ? 's' : ''}',
            color: Colors.white,
            onTap: () {
              Get.back();
              Future.delayed(
                  const Duration(milliseconds: 200), () => _showViewers(story));
            },
          ),
          const _OptionDivider(),

          // ── Supprimer ─────────────────────────────────────
          _OptionTile(
            icon: Icons.delete_outline_rounded,
            label: 'Supprimer',
            color: Colors.red,
            onTap: () {
              Get.back();
              Future.delayed(
                  const Duration(milliseconds: 200), () => _deleteStory(story));
            },
          ),
        ]),
      ),
    ).then((_) => _resume());
  }

  @override
  Widget build(BuildContext context) {
    // ✅ FIX CRASH : protection liste vide
    if (widget.stories.isEmpty) {
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

    final s = widget.stories[_current];
    final bool isOwner = s.userId == _myUid;
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        onLongPressStart: (_) {
          _pause();
          setState(() => _longPressing = true);
        },
        onLongPressEnd: (_) {
          _resume();
          setState(() => _longPressing = false);
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
            _prev();
          } else {
            _next();
          }
        },
        child: Stack(fit: StackFit.expand, children: [
          _buildMedia(s),
          const DecoratedBox(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.center,
                      colors: [Color(0xCC000000), Colors.transparent]))),
          const Align(
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

          // ── Barres de progression ──────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: Row(
                children: List.generate(widget.stories.length, (i) {
              return Expanded(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: i == _current
                              ? AnimatedBuilder(
                                  animation: _progressCtrl,
                                  builder: (_, __) => LinearProgressIndicator(
                                      value: _progressCtrl.value,
                                      backgroundColor: Colors.white30,
                                      valueColor: const AlwaysStoppedAnimation(
                                          Colors.white),
                                      minHeight: 2.5))
                              : LinearProgressIndicator(
                                  value: i < _current ? 1.0 : 0.0,
                                  backgroundColor: Colors.white30,
                                  valueColor: const AlwaysStoppedAnimation(
                                      Colors.white),
                                  minHeight: 2.5))));
            })),
          ),

          if (_paused)
            Center(
                child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24)),
                    child: const Icon(Icons.pause_rounded,
                        color: Colors.white, size: 36))),

          // ── Header ────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 20,
            left: 12,
            right: 12,
            child: Row(children: [
              // Avatar
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
              // Nom + heure
              Expanded(
                  child: GestureDetector(
                      onTap: () => _openProfile(s),
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
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 11)),
                          ]))),

              // ✅ Bouton ⋯ options (owner seulement) + bouton fermer
              if (isOwner) ...[
                GestureDetector(
                  onTap: () {
                    _pause();
                    _showStoryOptions(s);
                  },
                  child: Container(
                    width: 34,
                    height: 34,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                        color: Colors.black38,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24)),
                    child: const Icon(Icons.more_vert_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
              ],
              // Bouton fermer
              GestureDetector(
                  onTap: () => Get.back(),
                  child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                          color: Colors.black38,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24)),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 18))),
            ]),
          ),

          // ── Zone basse ────────────────────────────────────
          if (!_longPressing)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              bottom: keyboardH > 0 ? keyboardH + 8 : bottomPad + 52,
              left: 0,
              right: 0,
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (s.caption != null &&
                            s.caption!.isNotEmpty &&
                            !_replyFocused)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(12)),
                                  child: Text(s.caption!,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          height: 1.4)))),
                        if (isOwner && !_replyFocused) ...[
                          GestureDetector(
                              onTap: () => _showViewers(s),
                              child: Row(children: [
                                const Icon(Icons.remove_red_eye_outlined,
                                    color: Colors.white70, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                    '${s.viewedBy.length} vue${s.viewedBy.length != 1 ? 's' : ''}',
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500)),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right_rounded,
                                    color: Colors.white38, size: 16),
                              ])),
                          const SizedBox(height: 10),
                        ],
                        if (!isOwner)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              GestureDetector(
                                onTap: () => _likeStory(s),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: _likedStoryIds.contains(s.id)
                                        ? Colors.pink.withOpacity(0.3)
                                        : Colors.black54,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _likedStoryIds.contains(s.id)
                                          ? Colors.pink
                                          : Colors.white24,
                                      width: _likedStoryIds.contains(s.id)
                                          ? 1.5
                                          : 1,
                                    ),
                                  ),
                                  child: Center(
                                      child: Text(
                                    _likedStoryIds.contains(s.id) ? '❤️' : '🤍',
                                    style: const TextStyle(fontSize: 20),
                                  )),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: _ReplyBar(
                                      story: s,
                                      onFocusChanged: (focused) {
                                        setState(() => _replyFocused = focused);
                                        if (focused) {
                                          _pause();
                                        } else {
                                          _resume();
                                        }
                                      })),
                            ],
                          ),
                      ])),
            ),
        ]),
      ),
    );
  }

  Widget _buildMedia(StoryModel s) {
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

  void _showViewers(StoryModel s) {
    if (s.userId != _myUid) return;
    final viewers = s.viewedBy;
    final storyId = s.id;
    final freeCount = viewers.length.clamp(0, _freeViewersLimit);
    final lockedCount = (viewers.length - _freeViewersLimit).clamp(0, 999);

    Get.bottomSheet(Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(Get.context!).size.height * 0.65),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: const BoxDecoration(
          color: Color(0xFF11111C),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: const Color(0xFF252538),
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.remove_red_eye_outlined,
                  color: AppColors.textMuted, size: 18),
              const SizedBox(width: 8),
              Text('${viewers.length} vue${viewers.length != 1 ? 's' : ''}',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 12),
            if (viewers.isEmpty)
              const Padding(
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
                            const Color(0xFF11111C).withOpacity(0.9),
                            const Color(0xFF11111C)
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
                            const Text('Passe en Premium pour tout voir',
                                style: TextStyle(
                                    color: AppColors.textMuted, fontSize: 12)),
                            const SizedBox(height: 14),
                            GestureDetector(
                                onTap: () {
                                  Get.back();
                                  Get.snackbar(
                                      '⭐ Premium', 'Bientôt disponible !',
                                      snackPosition: SnackPosition.TOP,
                                      backgroundColor: const Color(0xFF13131A),
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
    )).then((_) => _resume());
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
    int age = 0;
    final birthdate = _fullData!['birthdate'] ?? _fullData!['birth_date'];
    if (birthdate != null) {
      try {
        DateTime birth;
        if (birthdate.toString().contains('/')) {
          final p = birthdate.toString().split('/');
          birth = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
        } else {
          birth = DateTime.parse(birthdate.toString());
        }
        final now = DateTime.now();
        age = now.year - birth.year;
        if (now.month < birth.month ||
            (now.month == birth.month && now.day < birth.day)) age--;
      } catch (_) {
        age = _fullData!['age'] ?? 0;
      }
    } else {
      age = _fullData!['age'] ?? 0;
    }
    final user = UserModel(
      id: _fullData!['id'] ?? widget.uid,
      name: _fullData!['name'] ?? 'Utilisateur',
      age: age,
      bio: _fullData!['bio'],
      photoUrl: _fullData!['photo_url'],
      photoUrls: List<String>.from(_fullData!['photo_urls'] ?? []),
      interests: List<String>.from(_fullData!['interests'] ?? []),
      latitude: _fullData!['latitude']?.toDouble(),
      longitude: _fullData!['longitude']?.toDouble(),
      gender: _fullData!['gender'],
      lookingFor: _fullData!['looking_for'],
      isOnline: _fullData!['is_online'] ?? false,
      followersCount: _fullData!['followers_count'] ?? 0,
      followingCount: _fullData!['following_count'] ?? 0,
      matchesCount: _fullData!['matches_count'] ?? 0,
    );
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
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600))),
          if (!_loading)
            const Icon(Icons.arrow_forward_ios_rounded,
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
      final profileData = results[0] as Map<String, dynamic>?;
      final storyData = results[1] as Map<String, dynamic>?;
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
    int age = 0;
    final birthdate = _fullData!['birthdate'] ?? _fullData!['birth_date'];
    if (birthdate != null) {
      try {
        DateTime birth;
        if (birthdate.toString().contains('/')) {
          final p = birthdate.toString().split('/');
          birth = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
        } else {
          birth = DateTime.parse(birthdate.toString());
        }
        final now = DateTime.now();
        age = now.year - birth.year;
        if (now.month < birth.month ||
            (now.month == birth.month && now.day < birth.day)) age--;
      } catch (_) {
        age = _fullData!['age'] ?? 0;
      }
    } else {
      age = _fullData!['age'] ?? 0;
    }
    final user = UserModel(
      id: _fullData!['id'] ?? widget.uid,
      name: _fullData!['name'] ?? 'Utilisateur',
      age: age,
      bio: _fullData!['bio'],
      photoUrl: _fullData!['photo_url'],
      photoUrls: List<String>.from(_fullData!['photo_urls'] ?? []),
      interests: List<String>.from(_fullData!['interests'] ?? []),
      latitude: _fullData!['latitude']?.toDouble(),
      longitude: _fullData!['longitude']?.toDouble(),
      gender: _fullData!['gender'],
      lookingFor: _fullData!['looking_for'],
      isOnline: _fullData!['is_online'] ?? false,
      followersCount: _fullData!['followers_count'] ?? 0,
      followingCount: _fullData!['following_count'] ?? 0,
      matchesCount: _fullData!['matches_count'] ?? 0,
    );
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
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600))),
          if (!_loading && _hasLiked) ...[
            const Text('❤️', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
          ],
          if (!_loading)
            const Icon(Icons.arrow_forward_ios_rounded,
                color: AppColors.textMuted, size: 14),
        ]),
      ),
    );
  }
}

// ─── REPLY BAR ────────────────────────────────────────────────────

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
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white);
      return;
    }
    setState(() => _sending = true);
    try {
      final res = await Supabase.instance.client
          .from('conversations')
          .select('id')
          .or('and(user1_id.eq.$uid,user2_id.eq.${widget.story.userId}),'
              'and(user1_id.eq.${widget.story.userId},user2_id.eq.$uid)')
          .maybeSingle();
      final String convId;
      if (res != null) {
        convId = res['id'] as String;
      } else {
        final created = await Supabase.instance.client
            .from('conversations')
            .insert({'user1_id': uid, 'user2_id': widget.story.userId})
            .select('id')
            .single();
        convId = created['id'] as String;
      }
      final storyData = StoryReplyData(
        storyId: widget.story.id,
        storyPreviewUrl: widget.story.mediaUrl,
        storyIsVideo: widget.story.isVideo,
        storyOwnerName: widget.story.userName,
      );
      final safeContent = text.substring(0, text.length.clamp(0, 500));
      if (Get.isRegistered<ConversationController>(tag: convId)) {
        await Get.find<ConversationController>(tag: convId).sendStoryReply(
          conversationId: convId,
          text: safeContent,
          storyData: storyData,
        );
      } else {
        bool sent = false;
        try {
          await Supabase.instance.client.from('messages').insert({
            'conversation_id': convId,
            'sender_id': uid,
            'type': 'text',
            'content': safeContent,
            'status': 'sent',
            'story_id': widget.story.id,
            'story_preview_url': widget.story.mediaUrl,
            'story_is_video': widget.story.isVideo,
            'topic': '📸 Story de ${widget.story.userName}',
          });
          sent = true;
        } catch (_) {}
        if (!sent) {
          await Supabase.instance.client.from('messages').insert({
            'conversation_id': convId,
            'sender_id': uid,
            'type': 'text',
            'content': safeContent,
            'status': 'sent',
          });
        }
        await Supabase.instance.client.from('conversations').update(
            {'updated_at': DateTime.now().toIso8601String()}).eq('id', convId);
      }
      _ctrl.clear();
      _focus.unfocus();
      widget.onFocusChanged(false);
      if (mounted) {
        Get.snackbar('Réponse envoyée ✓', '',
            snackPosition: SnackPosition.TOP,
            backgroundColor: const Color(0xFF13131A),
            colorText: Colors.white,
            duration: const Duration(seconds: 2));
      }
    } catch (e) {
      debugPrint('replyStory error: $e');
      if (mounted) {
        Get.snackbar('Erreur', "Impossible d'envoyer le message",
            snackPosition: SnackPosition.TOP,
            backgroundColor: const Color(0xFF13131A),
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

// ─────────────────────────────────────────────────────────────────
//  ADD STORY SCREEN
// ─────────────────────────────────────────────────────────────────

class AddStoryScreen extends StatefulWidget {
  const AddStoryScreen({super.key});
  @override
  State<AddStoryScreen> createState() => _AddStoryScreenState();
}

class _AddStoryScreenState extends State<AddStoryScreen> {
  final _picker = ImagePicker();
  bool _uploading = false;
  double _progress = 0;
  String? _previewPath;
  bool _isVideo = false;
  final _captionCtrl = TextEditingController();
  bool _showCaption = false;

  Future<void> _pickMedia(ImageSource source, {bool video = false}) async {
    try {
      XFile? file;
      if (video) {
        file = await _picker.pickVideo(
            source: source, maxDuration: const Duration(seconds: 30));
      } else {
        file = await _picker.pickImage(
            source: source, maxWidth: 1080, maxHeight: 1920, imageQuality: 85);
      }
      if (file == null) return;
      setState(() {
        _previewPath = file!.path;
        _isVideo = video;
      });
    } catch (_) {
      _snack('Erreur lors de la sélection');
    }
  }

  Future<void> _publish() async {
    if (_previewPath == null) return;
    setState(() {
      _uploading = true;
      _progress = 0;
    });
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) {
        _snack('Tu dois être connecté');
        setState(() => _uploading = false);
        return;
      }
      final file = File(_previewPath!);
      if (!await file.exists()) {
        _snack('Fichier introuvable');
        setState(() => _uploading = false);
        return;
      }
      final ext = _previewPath!.split('.').last.toLowerCase();
      const allowedImg = ['jpg', 'jpeg', 'png', 'webp', 'heic'];
      const allowedVid = ['mp4', 'mov', 'avi', 'mkv'];
      if (!(_isVideo ? allowedVid : allowedImg).contains(ext)) {
        _snack('Format non supporté');
        setState(() => _uploading = false);
        return;
      }
      final fileName = '${uid}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final storagePath = 'stories/$uid/$fileName';
      setState(() => _progress = 0.2);
      await Supabase.instance.client.storage.from('stories').upload(
          storagePath, file,
          fileOptions: const FileOptions(upsert: true));
      setState(() => _progress = 0.65);
      final mediaUrl = Supabase.instance.client.storage
          .from('stories')
          .getPublicUrl(storagePath);
      final caption = _captionCtrl.text.trim();
      final safeCaption = caption.isNotEmpty
          ? caption.substring(0, caption.length.clamp(0, 200))
          : null;
      await Supabase.instance.client.from('stories').insert({
        'user_id': uid,
        'media_url': mediaUrl,
        'is_video': _isVideo,
        'caption': safeCaption,
        'created_at': DateTime.now().toIso8601String(),
        'expires_at':
            DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
        'viewed_by': [],
      });
      setState(() => _progress = 1.0);
      await Future.delayed(const Duration(milliseconds: 300));
      if (Get.isRegistered<HomeController>())
        await Get.find<HomeController>().loadStories();
      Get.back(result: true);
      Get.snackbar('Story publiée ✓', 'Visible pendant 24h',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white,
          duration: const Duration(seconds: 2));
    } catch (e) {
      debugPrint('publish story error: $e');
      _snack('Erreur lors de la publication : $e');
      setState(() => _uploading = false);
    }
  }

  void _snack(String msg) => Get.snackbar('Erreur', msg,
      snackPosition: SnackPosition.TOP,
      backgroundColor: const Color(0xFF13131A),
      colorText: Colors.white);

  void _showSourcePicker({required bool video}) {
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      decoration: BoxDecoration(
                          color: const Color(0xFF11111C),
                          borderRadius: BorderRadius.circular(16)),
                      child: Column(children: [
                        _SourceOption(
                            icon: Icons.camera_alt_rounded,
                            label: video
                                ? 'Filmer une vidéo'
                                : 'Prendre une photo',
                            onTap: () {
                              Navigator.pop(ctx);
                              _pickMedia(ImageSource.camera, video: video);
                            },
                            showDivider: true),
                        _SourceOption(
                            icon: Icons.photo_library_rounded,
                            label: 'Choisir dans la galerie',
                            onTap: () {
                              Navigator.pop(ctx);
                              _pickMedia(ImageSource.gallery, video: video);
                            },
                            showDivider: false),
                      ])),
                  const SizedBox(height: 10),
                  GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                              color: const Color(0xFF11111C),
                              borderRadius: BorderRadius.circular(16)),
                          child: const Text('Annuler',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)))),
                ]))));
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            onPressed: () => Get.back(result: false)),
        actions: [
          if (_previewPath != null && !_uploading)
            GestureDetector(
                onTap: _publish,
                child: Container(
                    margin: const EdgeInsets.only(right: 16),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                        gradient: AppColors.gradientPink,
                        borderRadius: BorderRadius.circular(20)),
                    child: const Text('Publier',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14))))
        ],
      ),
      body: _uploading
          ? _buildUploading()
          : _previewPath == null
              ? _buildPicker()
              : _buildPreview(),
    );
  }

  Widget _buildPicker() => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
                gradient: AppColors.gradientPink, shape: BoxShape.circle),
            child: const Icon(Icons.add_a_photo_rounded,
                color: Colors.white, size: 40)),
        const SizedBox(height: 24),
        const Text('Ajouter une story',
            style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontFamily: 'Syne',
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Photo ou vidéo • Visible 24h',
            style: TextStyle(color: Colors.white54, fontSize: 14)),
        const SizedBox(height: 48),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _BigBtn(
              icon: Icons.photo_library_rounded,
              label: 'Photo',
              onTap: () => _showSourcePicker(video: false)),
          const SizedBox(width: 16),
          _BigBtn(
              icon: Icons.videocam_rounded,
              label: 'Vidéo',
              onTap: () => _showSourcePicker(video: true)),
        ]),
      ]));

  Widget _buildPreview() => Stack(fit: StackFit.expand, children: [
        _isVideo
            ? _VideoPreview(path: _previewPath!)
            : Image.file(File(_previewPath!), fit: BoxFit.contain),
        if (_showCaption)
          Positioned(
              bottom: 110,
              left: 16,
              right: 16,
              child: Container(
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24)),
                  child: TextField(
                      controller: _captionCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      maxLines: 3,
                      maxLength: 200,
                      autofocus: true,
                      buildCounter: (_,
                              {required currentLength,
                              required isFocused,
                              maxLength}) =>
                          Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Text('$currentLength/200',
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 10))),
                      decoration: const InputDecoration(
                          hintText: 'Ajouter une légende...',
                          hintStyle: TextStyle(color: Colors.white38),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(14))))),
        Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
                top: false,
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Row(children: [
                      GestureDetector(
                          onTap: () =>
                              setState(() => _showCaption = !_showCaption),
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                  color: _showCaption
                                      ? AppColors.accent.withOpacity(0.2)
                                      : Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: _showCaption
                                          ? AppColors.accent
                                          : Colors.white24)),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.text_fields_rounded,
                                        color: _showCaption
                                            ? AppColors.accent
                                            : Colors.white,
                                        size: 16),
                                    const SizedBox(width: 6),
                                    Text('Légende',
                                        style: TextStyle(
                                            color: _showCaption
                                                ? AppColors.accent
                                                : Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                  ]))),
                      const Spacer(),
                      GestureDetector(
                          onTap: () => setState(() => _previewPath = null),
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white24)),
                              child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.refresh_rounded,
                                        color: Colors.white, size: 16),
                                    SizedBox(width: 6),
                                    Text('Changer',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                  ]))),
                    ])))),
      ]);

  Widget _buildUploading() => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
                gradient: AppColors.gradientPink, shape: BoxShape.circle),
            child: const Icon(Icons.cloud_upload_rounded,
                color: Colors.white, size: 36)),
        const SizedBox(height: 24),
        const Text('Publication en cours...',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 24),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(AppColors.accent),
                    minHeight: 4))),
      ]));
}

// ─── VIDEO PREVIEW ────────────────────────────────────────────────

class _VideoPreview extends StatefulWidget {
  final String path;
  const _VideoPreview({required this.path});
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
    await ctrl.initialize();
    if (!mounted) return;
    ctrl.setLooping(true);
    ctrl.play();
    setState(() => _ready = true);
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

class _BigBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _BigBtn({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          width: 130,
          height: 56,
          decoration: BoxDecoration(
              gradient: AppColors.gradientPink,
              borderRadius: BorderRadius.circular(16)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ])));
}

class _SourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool showDivider;
  const _SourceOption(
      {required this.icon,
      required this.label,
      required this.onTap,
      required this.showDivider});
  @override
  Widget build(BuildContext context) => Column(children: [
        GestureDetector(
            onTap: onTap,
            child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                child: Row(children: [
                  Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(width: 14),
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500))
                ]))),
        if (showDivider)
          const Divider(
              height: 1, color: Color(0xFF252538), indent: 20, endIndent: 20),
      ]);
}
