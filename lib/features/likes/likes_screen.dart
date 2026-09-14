import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/home/view/story_screen.dart';
import 'package:rencontre/features/follow/controller/follow_controller.dart';
import 'package:rencontre/shared/models/story_model.dart';
import 'package:rencontre/features/home/view/discover_feed_viewer.dart';
import 'package:rencontre/features/annonces/controller/annonces_controller.dart';

// ══════════════════════════════════════════════════════════════════
//  STORY SCREEN — structure façon Snapchat :
//  Amis·es (cercles) / Comptes suivis (rectangles) / Découvrir (grille)
// ══════════════════════════════════════════════════════════════════

class LikesScreen extends StatelessWidget {
  const LikesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<HomeController>()) {
      Get.put(HomeController(), permanent: true);
    }
    if (!Get.isRegistered<FollowController>()) {
      Get.put(FollowController(), permanent: true);
    }
    if (!Get.isRegistered<AnnoncesController>()) {
      Get.put(AnnoncesController(), permanent: true);
    }
    final controller = Get.find<HomeController>();
    final annoncesCtrl = Get.find<AnnoncesController>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Obx(() {
          final friends = controller.friendsStories;
          final following = controller.followingStories;
          final discoverStories = controller.discoverStories;
          final annonces = annoncesCtrl.annonces; // lu ici pour la réactivité
          final annonceGroups = groupAnnoncesByUser(annonces);
          final discoverCards =
              buildDiscoverCards(discoverStories, annonceGroups);
          final myStory = controller.myActiveStory;
          final uploading = controller.isUploadingStory.value;

          if (friends.isEmpty &&
              following.isEmpty &&
              discoverCards.isEmpty &&
              myStory == null &&
              !uploading) {
            return Column(
              children: [
                _buildHeader(controller),
                Expanded(child: _buildEmptyState()),
              ],
            );
          }

          return RefreshIndicator(
            onRefresh: controller.loadStories,
            color: AppColors.accent,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(controller)),
                SliverToBoxAdapter(
                  child: _AmisSection(
                    friends: friends,
                    myStory: myStory,
                    controller: controller,
                  ),
                ),
                if (following.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _ComptesSuivisSection(
                      following: following,
                      controller: controller,
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Text(
                      'Découvrir',
                      style: TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                if (discoverCards.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('Rien à découvrir pour le moment',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.textMuted)),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio:
                            0.72, // ✅ toutes les cartes ont le même ratio, façon Snapchat
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final card = discoverCards[i];
                          final flat = flattenDiscoverCards(discoverCards);
                          final startIdx = startIndexForCard(discoverCards, i);
                          return card.isStory
                              ? _StoryRectangleCard(
                                  story: card.story!,
                                  isMine: false,
                                  height: double.infinity,
                                  onTap: () => Get.to(
                                    () => DiscoverFeedViewerScreen(
                                      items: flat,
                                      initialIndex: startIdx,
                                    ),
                                    transition: Transition.fadeIn,
                                  ),
                                )
                              : _AnnonceRectangleCard(
                                  group: card.annonceGroup!,
                                  height: double.infinity,
                                  onTap: () => Get.to(
                                    () => DiscoverFeedViewerScreen(
                                      items: flat,
                                      initialIndex: startIdx,
                                    ),
                                    transition: Transition.fadeIn,
                                  ),
                                );
                        },
                        childCount: discoverCards.length,
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

  Widget _buildHeader(HomeController controller) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (b) => AppColors.gradientPink.createShader(b),
            child: const Text(
              'Story',
              style: TextStyle(
                fontFamily: 'Syne',
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: controller.loadStories,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(Icons.refresh_rounded,
                  size: 18, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📸', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text(
            'Aucune story pour le moment',
            style: TextStyle(
              fontFamily: 'Syne',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Reviens plus tard ou publie\nla première story !',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  static void _openStory(HomeController controller, StoryModel story) {
    final userStories = controller.storiesForUser(story.userId);
    if (userStories.isEmpty) return;
    Get.to(
      () => StoryViewerScreen(stories: userStories, initialIndex: 0),
      transition: Transition.fadeIn,
    );
    controller.markStoryAsSeen(userStories.first.id);
  }
}

// ══════════════════════════════════════════════════════════════════
//  SECTION AMIS·ES (cercles avec anneau, comme Snapchat)
// ══════════════════════════════════════════════════════════════════

class _AmisSection extends StatelessWidget {
  final List<StoryModel> friends;
  final StoryModel? myStory;
  final HomeController controller;

  const _AmisSection({
    required this.friends,
    required this.myStory,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final uploading = controller.isUploadingStory.value; // ✅ NOUVEAU
      if (friends.isEmpty && myStory == null && !uploading) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Amis·es',
              style: TextStyle(
                fontFamily: 'Syne',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                // ✅ NOUVEAU — cercle "Toi" avec anneau de progression pendant l'envoi
                if (uploading)
                  _UploadingStoryCircle(controller: controller)
                else if (myStory != null)
                  _StoryCircle(
                    story: myStory,
                    isMine: true,
                    onTap: () => LikesScreen._openStory(controller, myStory!),
                  ),
                ...friends.map((s) => _StoryCircle(
                      story: s,
                      isMine: false,
                      onTap: () => LikesScreen._openStory(controller, s),
                    )),
              ],
            ),
          ),
        ],
      );
    });
  }
}

// ✅ NOUVEAU — cercle "Toi" affiché pendant l'envoi (façon Snapchat/TikTok)
class _UploadingStoryCircle extends StatelessWidget {
  final HomeController controller;
  const _UploadingStoryCircle({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          Obx(() {
            final progress = controller.storyUploadProgress.value;
            final path = controller.storyUploadPreviewPath.value;
            final isVideo = controller.storyUploadIsVideo.value;
            return SizedBox(
              width: 62,
              height: 62,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 62,
                    height: 62,
                    child: CircularProgressIndicator(
                      value: progress > 0 && progress < 1 ? progress : null,
                      strokeWidth: 2.5,
                      backgroundColor: AppColors.border,
                      valueColor: AlwaysStoppedAnimation(AppColors.accent),
                    ),
                  ),
                  Container(
                    width: 52,
                    height: 52,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: AppColors.bg),
                    child: ClipOval(
                      child: path == null
                          ? Container(color: AppColors.surface2)
                          : isVideo
                              ? Container(
                                  color: AppColors.surface2,
                                  child: const Icon(Icons.videocam_rounded,
                                      color: Colors.white54, size: 20),
                                )
                              : Image.file(File(path), fit: BoxFit.cover),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
          Text(
            'Envoi...',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _StoryCircle extends StatelessWidget {
  final StoryModel? story;
  final bool isMine;
  final VoidCallback onTap;
  const _StoryCircle(
      {required this.story, required this.isMine, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = story;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient:
                    (s == null || s.isSeen) ? null : AppColors.gradientPink,
                color: (s == null || s.isSeen) ? AppColors.border : null,
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: AppColors.bg),
                child: ClipOval(
                  child: s?.userPhotoUrl != null && s!.userPhotoUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: s.userPhotoUrl!, fit: BoxFit.cover)
                      : Container(
                          color: AppColors.surface2,
                          child: Center(
                            child: Text(
                              (s?.userName.isNotEmpty ?? false)
                                  ? s!.userName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: Colors.white54,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isMine ? 'Toi' : (s?.userName.split(' ').first ?? ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  SECTION COMPTES SUIVIS (rectangles compacts, comme Snapchat)
// ══════════════════════════════════════════════════════════════════

class _ComptesSuivisSection extends StatelessWidget {
  final List<StoryModel> following;
  final HomeController controller;

  const _ComptesSuivisSection(
      {required this.following, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            'Comptes suivis',
            style: TextStyle(
              fontFamily: 'Syne',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        SizedBox(
          height: 150,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: following.length,
            itemBuilder: (_, i) {
              final s = following[i];
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: 110,
                  child: _StoryRectangleCard(
                    story: s,
                    isMine: false,
                    height: 150,
                    onTap: () => LikesScreen._openStory(controller, s),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Carte façon "Découvrir" (Snapchat) ────────────────────────────

class _StoryRectangleCard extends StatelessWidget {
  final StoryModel story;
  final bool isMine;
  final double height;
  final VoidCallback onTap;

  const _StoryRectangleCard({
    required this.story,
    required this.isMine,
    required this.height,
    required this.onTap,
  });

  static const _gradients = [
    [Color(0xFFFF3CAC), Color(0xFF7B2FFF)],
    [Color(0xFF7B2FFF), Color(0xFF00F5D4)],
    [Color(0xFFFF6B6B), Color(0xFFFF3CAC)],
    [Color(0xFFFFD700), Color(0xFFFFA500)],
    [Color(0xFF00B894), Color(0xFF00F5D4)],
    [Color(0xFF00B4DB), Color(0xFF7B2FFF)],
    [Color(0xFFFF9F43), Color(0xFFEE5A24)],
    [Color(0xFFA29BFE), Color(0xFF6C5CE7)],
  ];

  @override
  Widget build(BuildContext context) {
    final idx = story.userName.isNotEmpty
        ? story.userName.codeUnitAt(0) % _gradients.length
        : 0;
    final colors = _gradients[idx];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: story.isSeen
                ? AppColors.border
                : AppColors.accent.withOpacity(0.9),
            width: story.isSeen ? 1 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: story.isSeen
                  ? Colors.black.withOpacity(0.25)
                  : AppColors.accent.withOpacity(0.35),
              blurRadius: story.isSeen ? 8 : 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(19),
          child: Stack(
            fit: StackFit.expand,
            children: [
              story.isVideo
                  ? _VideoThumbnail(url: story.mediaUrl, fallback: colors)
                  : _buildImage(colors),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.05),
                        Colors.transparent,
                        Colors.black.withOpacity(0.75),
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
              if (story.isVideo)
                Center(
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.35),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.8), width: 1.5),
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 26),
                  ),
                ),
              if (story.isPremium)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                      ),
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 12, color: Colors.white),
                  ),
                ),
              if (isMine)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: AppColors.gradientPink,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.accent.withOpacity(0.5),
                            blurRadius: 6)
                      ],
                    ),
                    child: const Text(
                      'Toi',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (!story.isSeen && !isMine)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.gradientPink,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              Positioned(
                bottom: 10,
                left: 10,
                right: 10,
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: ClipOval(
                        child: story.userPhotoUrl != null &&
                                story.userPhotoUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: story.userPhotoUrl!,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: AppColors.accent2,
                                child: Center(
                                  child: Text(
                                    story.userName.isNotEmpty
                                        ? story.userName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isMine ? 'Ma story' : story.userName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (story.distanceKm != null)
                            Text(
                              _formatDistance(story.distanceKm!),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white.withOpacity(0.75),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage(List<Color> colors) {
    if (story.mediaUrl.isEmpty) return _buildGradientFallback(colors, null);
    return CachedNetworkImage(
      imageUrl: story.mediaUrl,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 250),
      placeholder: (_, __) => _buildGradientFallback(colors, null),
      errorWidget: (_, __, ___) =>
          _buildGradientFallback(colors, Icons.image_not_supported_rounded),
    );
  }

  static Widget _buildGradientFallback(List<Color> colors, IconData? icon) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: icon != null
          ? Center(
              child: Icon(icon, color: Colors.white.withOpacity(0.7), size: 32))
          : null,
    );
  }

  String _formatDistance(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }
}

// ── Miniature vidéo réelle (première frame) ───────────────────────

class _VideoThumbnail extends StatefulWidget {
  final String url;
  final List<Color> fallback;
  const _VideoThumbnail({required this.url, required this.fallback});

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _ThumbCache {
  static final Map<String, Uint8List> _cache = {};
  static Uint8List? get(String url) => _cache[url];
  static void set(String url, Uint8List bytes) => _cache[url] = bytes;
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final cached = _ThumbCache.get(widget.url);
    if (cached != null) {
      _bytes = cached;
    } else {
      _generate();
    }
  }

  Future<void> _generate() async {
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: widget.url,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 400,
        quality: 70,
      );
      if (bytes != null) {
        _ThumbCache.set(widget.url, bytes);
        if (mounted) setState(() => _bytes = bytes);
      } else if (mounted) {
        setState(() => _failed = true);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return Image.memory(_bytes!, fit: BoxFit.cover);
    }
    if (_failed) {
      return _StoryRectangleCard._buildGradientFallback(
          widget.fallback, Icons.videocam_rounded);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        _StoryRectangleCard._buildGradientFallback(widget.fallback, null),
        const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white70,
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  CARTE ANNONCE (façon "Découvrir") — regroupe toutes les annonces
//  d'un même auteur sous une seule carte, avec badge de compteur.
// ══════════════════════════════════════════════════════════════════

class _AnnonceRectangleCard extends StatelessWidget {
  final AnnonceGroup group;
  final double height;
  final VoidCallback onTap;

  const _AnnonceRectangleCard({
    required this.group,
    required this.height,
    required this.onTap,
  });

  static const _gradients = [
    [Color(0xFF2E63FF), Color(0xFF00C2FF)],
    [Color(0xFFFF3CAC), Color(0xFF7B2FFF)],
    [Color(0xFFFFD700), Color(0xFFFF8A00)],
    [Color(0xFF00D68F), Color(0xFF00B894)],
  ];

  @override
  Widget build(BuildContext context) {
    final annonce = group.cover;
    final String userName = annonce.userName;
    final String titre = annonce.titre;
    final String? mediaUrl = annonce.mediaUrl;
    final String? userPhotoUrl = annonce.userPhotoUrl;
    final bool hasMedia = mediaUrl != null && mediaUrl.isNotEmpty;

    final idx =
        userName.isNotEmpty ? userName.codeUnitAt(0) % _gradients.length : 0;
    final colors = _gradients[idx];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: AppColors.accent2.withOpacity(0.6), width: 2),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent2.withOpacity(0.3),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(19),
          child: Stack(
            fit: StackFit.expand,
            children: [
              hasMedia
                  ? CachedNetworkImage(
                      imageUrl: mediaUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _fallback(colors),
                      errorWidget: (_, __, ___) => _fallback(colors),
                    )
                  : _fallback(colors, title: titre),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.05),
                        Colors.transparent,
                        Colors.black.withOpacity(0.75),
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: colors),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.campaign_rounded, color: Colors.white, size: 10),
                    SizedBox(width: 3),
                    Text('Annonce',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ]),
                ),
              ),
              // ✅ Badge de compteur si l'auteur a plusieurs annonces
              if (group.count > 1)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white38),
                    ),
                    child: Text('${group.count}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                ),
              Positioned(
                bottom: 10,
                left: 10,
                right: 10,
                child: Row(children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: ClipOval(
                      child: userPhotoUrl != null && userPhotoUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: userPhotoUrl, fit: BoxFit.cover)
                          : Container(
                              color: AppColors.accent2,
                              child: Center(
                                child: Text(
                                    userName.isNotEmpty
                                        ? userName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11)),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasMedia ? userName : titre,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallback(List<Color> colors, {String? title}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
      ),
      child: title != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
              ),
            )
          : null,
    );
  }
}
