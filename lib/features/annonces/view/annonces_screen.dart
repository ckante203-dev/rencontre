// lib/features/annonces/view/annonces_screen.dart
// ✅ VERSION PRO — Follow, vidéo barre visible, double-tap ❤️, améliorations UX

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/annonces/controller/annonces_controller.dart';
import 'package:rencontre/features/annonces/controller/annonce_comment_controller.dart';
import 'package:rencontre/features/annonces/model/annonce_model.dart';
import 'package:rencontre/features/annonces/model/annonce_comment_model.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/features/chat/model/message_model.dart';

// ══════════════════════════════════════════════════════════════════
//  ECRAN PRINCIPAL
// ══════════════════════════════════════════════════════════════════

class AnnoncesScreen extends StatelessWidget {
  const AnnoncesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<AnnoncesController>()) {
      Get.put(AnnoncesController(), permanent: true);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.find<AnnoncesController>().refreshSilent();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.find<AnnoncesController>().markAnnoncesAsSeen();
    });
    return const _AnnoncesView();
  }
}

// ══════════════════════════════════════════════════════════════════
//  VUE PRINCIPALE
// ══════════════════════════════════════════════════════════════════

class _AnnoncesView extends GetView<AnnoncesController> {
  const _AnnoncesView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ── Feed TikTok ──────────────────────────────────────
          Obx(() {
            if (controller.isLoading.value && controller.annonces.isEmpty) {
              return const _TikTokSkeleton();
            }
            final list = controller.filtered;
            if (list.isEmpty) return _buildEmptyState();

            return RefreshIndicator(
              color: AppColors.accent,
              backgroundColor: const Color(0xFF13131A),
              onRefresh: controller.loadAnnonces,
              child: PageView.builder(
                scrollDirection: Axis.vertical,
                physics: const BouncingScrollPhysics(),
                itemCount: list.length + (controller.hasMore.value ? 1 : 0),
                onPageChanged: (i) {
                  if (i >= list.length - 2) controller.loadMore();
                },
                itemBuilder: (_, i) {
                  if (i >= list.length) {
                    return  Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accent, strokeWidth: 2),
                    );
                  }
                  return _TikTokCard(annonce: list[i]);
                },
              ),
            );
          }),

          // ── Header flottant ──────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _FloatingHeader(),
          ),
        ],
      ),
      floatingActionButton: _PublierFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildEmptyState() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ShaderMask(
              shaderCallback: (b) => AppColors.gradientPink.createShader(b),
              child: const Icon(Icons.campaign_rounded,
                  size: 80, color: Colors.white),
            ),
            const SizedBox(height: 20),
            const Text('Aucune annonce',
                style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
            const SizedBox(height: 8),
            const Text('Sois le premier à publier !',
                style: TextStyle(fontSize: 14, color: Colors.white60)),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  HEADER FLOTTANT
// ══════════════════════════════════════════════════════════════════

class _FloatingHeader extends GetView<AnnoncesController> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 8, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.75),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Obx(() => SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      'toutes',
                      'rencontre',
                      'amitie',
                      'sortie',
                      'voyage',
                    ].map((cat) {
                      final sel = controller.filterCategorie.value == cat;
                      return GestureDetector(
                        onTap: () => controller.filterCategorie.value = cat,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: sel ? AppColors.gradientPink : null,
                            color: sel ? null : Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: sel
                                ? null
                                : Border.all(
                                    color: Colors.white.withOpacity(0.3)),
                          ),
                          child: Text(
                            _catLabel(cat),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: sel
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                )),
          ),
          GestureDetector(
            onTap: () => _showMesAnnonces(context),
            child: Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: const Icon(Icons.person_outline_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  String _catLabel(String cat) {
    const m = {
      'toutes': '🔥 Toutes',
      'rencontre': '💕 Rencontre',
      'amitie': '🤝 Amitié',
      'sortie': '🎉 Sortie',
      'voyage': '✈️ Voyage',
    };
    return m[cat] ?? cat;
  }

  void _showMesAnnonces(BuildContext context) {
    Get.find<AnnoncesController>().loadMesAnnonces();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _MesAnnoncesSheet(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  FAB PUBLIER
// ══════════════════════════════════════════════════════════════════

class _PublierFAB extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _PublierSheet(),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          gradient: AppColors.gradientPink,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withOpacity(0.5),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 20),
            SizedBox(width: 6),
            Text('Publier',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  CARTE TIKTOK — PLEIN ÉCRAN
// ══════════════════════════════════════════════════════════════════

class _TikTokCard extends GetView<AnnoncesController> {
  final AnnonceModel annonce;
  const _TikTokCard({required this.annonce});

  String get _emoji {
    const m = {
      'rencontre': '💕',
      'amitie': '🤝',
      'sortie': '🎉',
      'voyage': '✈️',
    };
    return m[annonce.categorie] ?? '📢';
  }

  String get _ago {
    final d = DateTime.now().difference(annonce.createdAt);
    if (d.inDays > 0) return '${d.inDays}j';
    if (d.inHours > 0) return '${d.inHours}h';
    if (d.inMinutes > 0) return '${d.inMinutes}min';
    return 'maintenant';
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.marquerVue(annonce);
    });

    return VisibilityDetector(
      key: Key('tiktok_${annonce.id}'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.8) controller.marquerVue(annonce);
      },
      child: _DoubleTapLike(
        onDoubleTap: () {
          HapticFeedback.mediumImpact();
          controller.toggleReaction(annonce, '❤️');
        },
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildBackground(),
              _buildOverlay(),
              // ── Actions droite ────────────────────────────
              Positioned(
                right: 12,
                bottom: 120,
                child: _ActionsSidebar(annonce: annonce),
              ),
              // ── Infos bas gauche ──────────────────────────
              Positioned(
                left: 16,
                right: 80,
                bottom: 80,
                child: _AnnonceInfo(annonce: annonce, emoji: _emoji, ago: _ago),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackground() {
    if (annonce.mediaUrl != null) {
      if (annonce.isVideo) {
        return _TikTokVideoPlayer(
            url: annonce.mediaUrl!, annonceId: annonce.id);
      } else {
        return CachedNetworkImage(
          imageUrl: annonce.mediaUrl!,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(color: Colors.black),
          errorWidget: (_, __, ___) => _buildColorBg(),
        );
      }
    }
    return _buildColorBg();
  }

  Widget _buildColorBg() {
    final gradients = {
      'rencontre': [const Color(0xFF1a0a2e), const Color(0xFF4a1a5e)],
      'amitie': [const Color(0xFF0a1a2e), const Color(0xFF1a3a5e)],
      'sortie': [const Color(0xFF1a1a0a), const Color(0xFF3a3a0a)],
      'voyage': [const Color(0xFF0a1a1a), const Color(0xFF0a3a3a)],
    };
    final colors = gradients[annonce.categorie] ??
        [const Color(0xFF0a0a1a), const Color(0xFF1a1a3a)];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$_emoji', style: const TextStyle(fontSize: 80)),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(annonce.titre,
                  style: const TextStyle(
                      fontFamily: 'Syne',
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.2),
                  textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.4, 0.7, 1.0],
            colors: [
              Colors.black.withOpacity(0.35),
              Colors.transparent,
              Colors.black.withOpacity(0.3),
              Colors.black.withOpacity(0.88),
            ],
          ),
        ),
      ),
    );
  }
}

// ✅ Widget double tap avec animation cœur style TikTok
class _DoubleTapLike extends StatefulWidget {
  final Widget child;
  final VoidCallback onDoubleTap;
  const _DoubleTapLike({required this.child, required this.onDoubleTap});

  @override
  State<_DoubleTapLike> createState() => _DoubleTapLikeState();
}

class _DoubleTapLikeState extends State<_DoubleTapLike>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  Offset _tapPosition = Offset.zero;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _scaleAnim = TweenSequence([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.3)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 40),
    ]).animate(_ctrl);
    _fadeAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_ctrl);
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        if (mounted) setState(() => _show = false);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => setState(() => _tapPosition = d.localPosition),
      onDoubleTap: () {
        widget.onDoubleTap();
        setState(() => _show = true);
        _ctrl.forward(from: 0);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          // ✅ Cœur flottant — icône Flutter + dégradé TikTok
          if (_show)
            Positioned(
              left: _tapPosition.dx - 60,
              top: _tapPosition.dy - 60,
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => Opacity(
                  opacity: _fadeAnim.value,
                  child: Transform.scale(
                    scale: _scaleAnim.value,
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          Color(0xFFFF2D55),
                          Color(0xFFFF6B8A),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: const Icon(
                        Icons.favorite_rounded,
                        size: 120,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  SIDEBAR ACTIONS
// ══════════════════════════════════════════════════════════════════

class _ActionsSidebar extends GetView<AnnoncesController> {
  final AnnonceModel annonce;
  const _ActionsSidebar({required this.annonce});

  @override
  Widget build(BuildContext context) {
    final myId = Supabase.instance.client.auth.currentUser?.id;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ✅ Avatar avec Follow/Unfollow
        _AvatarFollow(annonce: annonce),
        const SizedBox(height: 24),

        // ── Like ──────────────────────────────────────────
        _LikeAction(annonce: annonce),
        const SizedBox(height: 20),

        // ── Commentaire ───────────────────────────────────
        _SidebarAction(
          icon: Icons.chat_bubble_rounded,
          count: annonce.reponsesCount,
          label: 'Commenter',
          onTap: annonce.commentsEnabled
              ? () => AnnonceCommentsSheet.show(context, annonce: annonce)
              : null,
          disabled: !annonce.commentsEnabled,
        ),
        const SizedBox(height: 20),

        // ── Répondre en PV ────────────────────────────────
        _SidebarAction(
          icon: Icons.send_rounded,
          count: 0,
          label: 'Répondre',
          showCount: false,
          onTap: myId != annonce.userId
              ? () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _RepondreEnPVSheet(annonce: annonce))
              : null,
          disabled: myId == annonce.userId,
        ),
        const SizedBox(height: 20),

        // ── Boost ─────────────────────────────────────────
        _BoostSidebar(annonce: annonce),
      ],
    );
  }
}

// ✅ Avatar avec bouton Follow/Unfollow intégré
class _AvatarFollow extends StatefulWidget {
  final AnnonceModel annonce;
  const _AvatarFollow({required this.annonce});

  @override
  State<_AvatarFollow> createState() => _AvatarFollowState();
}

class _AvatarFollowState extends State<_AvatarFollow> {
  bool _isFollowing = false;
  bool _loading = false;
  final _myId = Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _checkFollow();
  }

  Future<void> _checkFollow() async {
    if (_myId == null || _myId == widget.annonce.userId) return;
    try {
      final row = await Supabase.instance.client
          .from('follows')
          .select('id')
          .eq('follower_id', _myId!)
          .eq('following_id', widget.annonce.userId)
          .maybeSingle();
      if (mounted) setState(() => _isFollowing = row != null);
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    if (_myId == null || _loading) return;
    setState(() => _loading = true);
    HapticFeedback.mediumImpact();
    try {
      if (_isFollowing) {
        await Supabase.instance.client
            .from('follows')
            .delete()
            .eq('follower_id', _myId!)
            .eq('following_id', widget.annonce.userId);
        if (mounted) setState(() => _isFollowing = false);
        Get.snackbar(
          'Abonnement retiré',
          'Tu ne suis plus ${widget.annonce.userName}',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
        );
      } else {
        await Supabase.instance.client.from('follows').insert({
          'follower_id': _myId,
          'following_id': widget.annonce.userId,
        });
        if (mounted) setState(() => _isFollowing = true);

        // ✅ Notification push au profil suivi
        _notifyFollow();

        Get.snackbar(
          '✅ Abonné !',
          'Tu suis ${widget.annonce.userName} · tu recevras ses annonces',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.accent.withOpacity(0.15),
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      debugPrint('toggleFollow error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _notifyFollow() async {
    try {
      final myProfile = await Supabase.instance.client
          .from('profiles')
          .select('name')
          .eq('id', _myId!)
          .maybeSingle();
      final myName = myProfile?['name'] ?? 'Quelqu\'un';

      final target = await Supabase.instance.client
          .from('profiles')
          .select('fcm_token')
          .eq('id', widget.annonce.userId)
          .maybeSingle();
      final token = target?['fcm_token'] as String?;
      if (token == null || token.isEmpty) return;

      await Supabase.instance.client.functions
          .invoke('send-notification', body: {
        'token': token,
        'title': '👥 Nouvel abonné',
        'body': '$myName s\'est abonné à ton profil !',
        'data': {'type': 'new_follower', 'userId': _myId},
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isMe = _myId == widget.annonce.userId;

    return GestureDetector(
      onTap: () => Get.toNamed('/profile/view',
          arguments: UserModel(
            id: widget.annonce.userId,
            name: widget.annonce.userName,
            age: widget.annonce.userAge,
            photoUrl: widget.annonce.userPhotoUrl,
            isOnline: false,
            interests: [],
          )),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Avatar ────────────────────────────────────
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _isFollowing ? null : AppColors.gradientPink,
              color: _isFollowing ? Colors.transparent : null,
              border: Border.all(
                color: _isFollowing ? AppColors.accent : Colors.white,
                width: _isFollowing ? 2.5 : 2,
              ),
            ),
            child: ClipOval(
              child: widget.annonce.isAnonyme
                  ? Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF6C3FC5), Color(0xFF3B1F7A)],
                        ),
                      ),
                      child: const Center(
                        child: Icon(Icons.person_outline_rounded,
                            color: Colors.white, size: 26),
                      ),
                    )
                  : (widget.annonce.userPhotoUrl != null
                      ? CachedNetworkImage(
                          imageUrl: widget.annonce.userPhotoUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _initials())
                      : _initials()),
            ),
          ),

          // ✅ Bouton +/✓ Follow
          if (!isMe)
            Positioned(
              bottom: -10,
              left: 0,
              right: 0,
              child: GestureDetector(
                onTap: _toggleFollow,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      gradient: _isFollowing ? null : AppColors.gradientPink,
                      color: _isFollowing ? const Color(0xFF252538) : null,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(4),
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 1.5))
                        : Icon(
                            _isFollowing
                                ? Icons.check_rounded
                                : Icons.add_rounded,
                            color: Colors.white,
                            size: 14),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _initials() => Container(
        decoration: BoxDecoration(gradient: AppColors.gradientPink),
        child: Center(
          child: Text(
            widget.annonce.userName.isNotEmpty
                ? widget.annonce.userName[0].toUpperCase()
                : '?',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22),
          ),
        ),
      );
}

class _LikeAction extends GetView<AnnoncesController> {
  final AnnonceModel annonce;
  const _LikeAction({required this.annonce});

  // ✅ Format TikTok : 1.2K, 3.4M
  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    // Détermine si une réaction non-❤️ est active
    final hasOtherReaction =
        annonce.myReaction.isNotEmpty && annonce.myReaction != '❤️';

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        controller.toggleReaction(annonce, '❤️');
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showReactionPicker(context);
      },
      child: Column(
        children: [
          // ✅ Vraie icône Flutter animée — plus d'emoji texte
          TweenAnimationBuilder<double>(
            key: ValueKey(annonce.isLiked),
            tween: Tween(
              begin: annonce.isLiked ? 0.7 : 1.0,
              end: 1.0,
            ),
            duration: const Duration(milliseconds: 350),
            curve: Curves.elasticOut,
            builder: (_, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: hasOtherReaction
                // Autre réaction (emoji) → on garde l'emoji
                ? Text(
                    annonce.myReaction,
                    style: const TextStyle(fontSize: 38),
                  )
                // ❤️ ou rien → icône Flutter propre
                : Icon(
                    annonce.isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: annonce.isLiked
                        ? const Color(0xFFFF2D55) // Rouge TikTok
                        : Colors.white,
                    size: 38,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 8)
                    ],
                  ),
          ),
          const SizedBox(height: 5),
          // ✅ Compteur formaté style TikTok
          Text(
            _formatCount(annonce.likes),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: annonce.isLiked ? const Color(0xFFFF2D55) : Colors.white,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
          // Mini réactions des autres
          if (annonce.reactionCounts.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: annonce.reactionCounts.entries
                    .where((e) => e.key != '❤️')
                    .take(2)
                    .map((e) =>
                        Text(e.key, style: const TextStyle(fontSize: 12)))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  void _showReactionPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        decoration: const BoxDecoration(
          color: Color(0xFF13131A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Text('Réagir',
                style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: AnnoncesController.reactions.map((emoji) {
                final isSelected = annonce.myReaction == emoji;
                final count = annonce.reactionCounts[emoji] ?? 0;
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    controller.toggleReaction(annonce, emoji);
                  },
                  child: Column(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.accent.withOpacity(0.2)
                            : Colors.white.withOpacity(0.08),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.accent
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Text(emoji,
                          style: TextStyle(fontSize: isSelected ? 30 : 26)),
                    ),
                    if (count > 0) ...[
                      const SizedBox(height: 4),
                      Text('$count',
                          style: TextStyle(
                              fontSize: 11,
                              color: isSelected
                                  ? AppColors.accent
                                  : Colors.white54,
                              fontWeight: FontWeight.w600)),
                    ],
                  ]),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarAction extends StatelessWidget {
  final IconData icon;
  final int count;
  final String label;
  final VoidCallback? onTap;
  final bool showCount;
  final bool disabled;

  const _SidebarAction({
    required this.icon,
    required this.count,
    required this.label,
    this.onTap,
    this.showCount = true,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: disabled
                  ? Colors.white.withOpacity(0.05)
                  : Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withOpacity(disabled ? 0.1 : 0.3)),
            ),
            child: Icon(icon,
                color: disabled ? Colors.white.withOpacity(0.3) : Colors.white,
                size: 22),
          ),
          if (showCount && count > 0) ...[
            const SizedBox(height: 4),
            Text('$count',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
          ],
        ],
      ),
    );
  }
}

class _BoostSidebar extends GetView<AnnoncesController> {
  final AnnonceModel annonce;
  const _BoostSidebar({required this.annonce});

  @override
  Widget build(BuildContext context) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId != annonce.userId) return const SizedBox.shrink();

    if (annonce.isBoosted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFD700).withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.5)),
        ),
        child: const Text('⚡', style: TextStyle(fontSize: 20)),
      );
    }

    return GestureDetector(
      onTap: () => _confirmBoost(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFFFFD700).withOpacity(0.4),
                blurRadius: 10),
          ],
        ),
        child: const Text('⚡', style: TextStyle(fontSize: 20)),
      ),
    );
  }

  void _confirmBoost(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF13131A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('⚡ Booster',
            style: TextStyle(
                fontFamily: 'Syne',
                fontWeight: FontWeight.w900,
                color: Colors.white)),
        content: const Text('Ton annonce apparaîtra en tête pendant 24h.',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler',
                  style: TextStyle(color: Colors.white38))),
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              controller.boosterAnnonce(annonce);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('⚡ Booster !',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  INFOS BAS GAUCHE
// ══════════════════════════════════════════════════════════════════

class _AnnonceInfo extends GetView<AnnoncesController> {
  final AnnonceModel annonce;
  final String emoji;
  final String ago;

  const _AnnonceInfo({
    required this.annonce,
    required this.emoji,
    required this.ago,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Auteur ────────────────────────────────────────
        GestureDetector(
          onTap: annonce.isAnonyme
              ? null
              : () => Get.toNamed('/profile/view',
                  arguments: UserModel(
                    id: annonce.userId,
                    name: annonce.userName,
                    age: annonce.userAge,
                    photoUrl: annonce.userPhotoUrl,
                    isOnline: false,
                    interests: [],
                  )),
          child: Row(children: [
            Text(
              annonce.isAnonyme ? '👤 Anonyme' : '@${annonce.userName}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
              ),
            ),
            const SizedBox(width: 8),
            if (annonce.isBoosted)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('⚡ BOOST',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
              ),
          ]),
        ),
        const SizedBox(height: 6),

        // ── Titre ─────────────────────────────────────────
        if (annonce.titre != '📸')
          Text(annonce.titre,
              style: const TextStyle(
                fontFamily: 'Syne',
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.2,
                shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),

        // ── Description ───────────────────────────────────
        if (annonce.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(annonce.description,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.85),
                height: 1.4,
                shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],

        const SizedBox(height: 10),

        // ── Tags ──────────────────────────────────────────
        Wrap(spacing: 6, runSpacing: 6, children: [
          _Tag('$emoji ${annonce.categorie}'),
          if (annonce.ville != null && !annonce.isAnonyme)
            _Tag('📍 ${annonce.ville!}'),
          _Tag('🕐 $ago'),
          _Tag('👁 ${annonce.viewsCount}'),
        ]),

        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _menu(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.more_horiz_rounded, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text('Plus',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _menu(BuildContext context) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: const BoxDecoration(
          color: Color(0xFF13131A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            if (myId == annonce.userId) ...[
              _MenuItem(Icons.delete_outline_rounded, 'Supprimer', Colors.red,
                  () {
                Navigator.pop(context);
                controller.supprimerAnnonce(annonce.id);
              }),
              const SizedBox(height: 8),
            ],
            _MenuItem(Icons.flag_outlined, 'Signaler', Colors.orange, () {
              Navigator.pop(context);
              _showSignalement(context);
            }),
            const SizedBox(height: 8),
            _MenuItem(Icons.close_rounded, 'Fermer', AppColors.textMuted,
                () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }

  void _showSignalement(BuildContext context) {
    final reasons = [
      '🔞 Contenu inapproprié',
      '🚫 Spam ou arnaque',
      '😡 Harcèlement',
      '❌ Fausses informations',
      '⚠️ Autre',
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        decoration: const BoxDecoration(
          color: Color(0xFF13131A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Text('Pourquoi signaler ?',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            const SizedBox(height: 16),
            ...reasons.map((r) => GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    controller.signalerAnnonce(annonce.id, r);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Text(r,
                        style:
                            const TextStyle(fontSize: 14, color: Colors.white)),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  ✅ VIDEO PLAYER — BARRE VISIBLE + SON CORRIGÉ
// ══════════════════════════════════════════════════════════════════

class _TikTokVideoPlayer extends StatefulWidget {
  final String url;
  final String annonceId;
  const _TikTokVideoPlayer({required this.url, required this.annonceId});

  @override
  State<_TikTokVideoPlayer> createState() => _TikTokVideoPlayerState();
}

class _TikTokVideoPlayerState extends State<_TikTokVideoPlayer> {
  late VideoPlayerController _ctrl;
  bool _initialized = false;
  bool _muted = true;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await _ctrl.initialize();
      if (mounted) {
        setState(() => _initialized = true);
        await _ctrl.setLooping(true);
        await _ctrl.setVolume(0);
        await _ctrl.play();
      }
    } catch (e) {
      debugPrint('Video init error: $e');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _ctrl.setVolume(_muted ? 0.0 : 1.0);
    HapticFeedback.lightImpact();
  }

  void _togglePlay() {
    setState(() => _paused = !_paused);
    _paused ? _ctrl.pause() : _ctrl.play();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return Container(
        color: Colors.black,
        child:  Center(
          child: CircularProgressIndicator(
              color: AppColors.accent, strokeWidth: 2),
        ),
      );
    }

    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Vidéo ──────────────────────────────────────
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _ctrl.value.size.width,
              height: _ctrl.value.size.height,
              child: VideoPlayer(_ctrl),
            ),
          ),

          // ── Pause overlay ──────────────────────────────
          if (_paused)
            Center(
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 40),
              ),
            ),

          // ── Bouton son ────────────────────────────────
          Positioned(
            top: 100,
            right: 16,
            child: GestureDetector(
              onTap: _toggleMute,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withOpacity(0.4), width: 1.5),
                ),
                child: Icon(
                  _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),

          // ✅ BARRE DE PROGRESSION BIEN VISIBLE — 4px, blanche
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _ctrl,
              builder: (_, value, __) {
                final duration = value.duration.inMilliseconds.toDouble();
                final position = value.position.inMilliseconds.toDouble();
                final progress =
                    duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;

                return GestureDetector(
                  onHorizontalDragUpdate: (d) {
                    if (duration <= 0) return;
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    final width = box.size.width;
                    final dx = d.globalPosition.dx / width;
                    final newPos = Duration(
                        milliseconds:
                            (dx * duration).toInt().clamp(0, duration.toInt()));
                    _ctrl.seekTo(newPos);
                  },
                  child: Container(
                    height: 22,
                    alignment: Alignment.bottomCenter,
                    color: Colors.transparent,
                    child: Stack(children: [
                      // Track fond
                      Container(
                        height: 3,
                        color: Colors.white.withOpacity(0.25),
                      ),
                      // Progress
                      FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            gradient: AppColors.gradientPink,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // Thumb
                      Positioned(
                        left: progress *
                                (MediaQuery.of(context).size.width - 10) -
                            5,
                        top: -3,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black45,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  SKELETON LOADING
// ══════════════════════════════════════════════════════════════════

class _TikTokSkeleton extends StatefulWidget {
  const _TikTokSkeleton();

  @override
  State<_TikTokSkeleton> createState() => _TikTokSkeletonState();
}

class _TikTokSkeletonState extends State<_TikTokSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 0.7)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.white.withOpacity(_anim.value * 0.05)),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.8),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 150,
              child: Column(
                children: List.generate(
                  3,
                  (i) => Container(
                    width: 50,
                    height: 50,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(_anim.value * 0.15),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              bottom: 80,
              right: 80,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: 120,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(_anim.value * 0.3),
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 18,
                    width: 200,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(_anim.value * 0.4),
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  SHEET PUBLIER
// ══════════════════════════════════════════════════════════════════

class _PublierSheet extends StatefulWidget {
  const _PublierSheet();

  @override
  State<_PublierSheet> createState() => _PublierSheetState();
}

class _PublierSheetState extends State<_PublierSheet> {
  final _titreCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _villeCtrl = TextEditingController();
  String _cat = 'rencontre';
  bool _loading = false;
  bool _anonyme = false;
  bool _commentsEnabled = true;
  XFile? _mediaFile;
  bool _isVideo = false;
  int _step = 0;

  @override
  void dispose() {
    _titreCtrl.dispose();
    _descCtrl.dispose();
    _villeCtrl.dispose();
    super.dispose();
  }

  String _catLabel(String c) {
    const m = {
      'rencontre': '💕',
      'amitie': '🤝',
      'sortie': '🎉',
      'voyage': '✈️',
    };
    return '${m[c]} $c';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D18),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  ShaderMask(
                    shaderCallback: (b) =>
                        AppColors.gradientPink.createShader(b),
                    child: const Text('Nouvelle annonce',
                        style: TextStyle(
                            fontFamily: 'Syne',
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text('${_step + 1}/2',
                        style:  TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: _step == 0 ? _buildStepMedia() : _buildStepDetails(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepMedia() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         Text('Ajoute une photo ou vidéo',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _mediaFile == null ? _pickImage : null,
          child: _mediaFile == null
              ? Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border:
                        Border.all(color: AppColors.accent.withOpacity(0.3)),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ShaderMask(
                          shaderCallback: (b) =>
                              AppColors.gradientPink.createShader(b),
                          child: const Icon(Icons.add_photo_alternate_rounded,
                              size: 48, color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                         Text('Appuie pour ajouter',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: _isVideo
                      ? Container(
                          height: 220,
                          color: AppColors.surface,
                          child:  Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.videocam_rounded,
                                    color: AppColors.accent, size: 48),
                                SizedBox(height: 8),
                                Text('Vidéo sélectionnée',
                                    style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        )
                      : Image.file(
                          File(_mediaFile!.path),
                          height: 220,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: _MediaButton(
              icon: Icons.photo_rounded,
              label: 'Photo',
              active: _mediaFile != null && !_isVideo,
              onTap: _pickImage,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MediaButton(
              icon: Icons.videocam_rounded,
              label: 'Vidéo',
              active: _mediaFile != null && _isVideo,
              onTap: _pickVideo,
            ),
          ),
          if (_mediaFile != null) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => setState(() => _mediaFile = null),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: const Icon(Icons.delete_outline_rounded,
                    color: Colors.red, size: 22),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => setState(() => _step = 1),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: AppColors.gradientPink,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: AppColors.accent.withOpacity(0.3), blurRadius: 16)
              ],
            ),
            child: const Center(
              child: Text('Suivant →',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _step = 0),
          child:  Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back_ios_rounded,
                  color: AppColors.textMuted, size: 14),
              SizedBox(width: 4),
              Text('Retour',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: ['rencontre', 'amitie', 'sortie', 'voyage']
                .map((c) => GestureDetector(
                      onTap: () => setState(() => _cat = c),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          gradient: _cat == c ? AppColors.gradientPink : null,
                          color: _cat == c ? null : AppColors.surface2,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _cat == c
                                  ? Colors.transparent
                                  : AppColors.border),
                        ),
                        child: Text(_catLabel(c),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _cat == c
                                    ? Colors.white
                                    : AppColors.textMuted)),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        _InputField(
            controller: _titreCtrl,
            hint: 'Titre (optionnel si photo/vidéo)',
            maxLines: 1),
        const SizedBox(height: 12),
        _InputField(
            controller: _descCtrl, hint: 'Décris ton annonce...', maxLines: 4),
        const SizedBox(height: 12),
        _InputField(
            controller: _villeCtrl, hint: '📍 Ville (optionnel)', maxLines: 1),
        const SizedBox(height: 16),
        _ToggleOption(
          icon: Icons.visibility_off_rounded,
          label: 'Anonyme',
          active: _anonyme,
          color: const Color(0xFF6C3FC5),
          onToggle: () => setState(() => _anonyme = !_anonyme),
        ),
        const SizedBox(height: 10),
        _ToggleOption(
          icon: _commentsEnabled
              ? Icons.chat_bubble_outline_rounded
              : Icons.comments_disabled_outlined,
          label: _commentsEnabled
              ? 'Commentaires activés'
              : 'Commentaires désactivés',
          active: !_commentsEnabled,
          color: Colors.orange,
          onToggle: () => setState(() => _commentsEnabled = !_commentsEnabled),
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: _loading ? null : _publier,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: AppColors.gradientPink,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: AppColors.accent.withOpacity(0.3), blurRadius: 16)
              ],
            ),
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    ),
                  )
                : const Center(
                    child: Text('🚀 Publier mon annonce',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickImage() async {
    final f = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (f != null)
      setState(() {
        _mediaFile = f;
        _isVideo = false;
      });
  }

  Future<void> _pickVideo() async {
    final f = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (f != null)
      setState(() {
        _mediaFile = f;
        _isVideo = true;
      });
  }

  Future<void> _publier() async {
    final hasMedia = _mediaFile != null;
    if (!hasMedia &&
        (_titreCtrl.text.trim().isEmpty || _descCtrl.text.trim().isEmpty)) {
      Get.snackbar('Champs requis',
          'Ajoute un titre et une description, ou une photo/vidéo',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.red.shade900,
          colorText: Colors.white);
      return;
    }
    setState(() => _loading = true);
    final ok = await Get.find<AnnoncesController>().publierAnnonce(
      titre: _titreCtrl.text.trim().isEmpty ? '📸' : _titreCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      categorie: _cat,
      ville: _villeCtrl.text.trim().isEmpty ? null : _villeCtrl.text.trim(),
      anonyme: _anonyme,
      mediaFile: _mediaFile,
      isVideo: _isVideo,
      commentsEnabled: _commentsEnabled,
    );
    setState(() => _loading = false);
    if (ok && mounted) {
      Navigator.pop(context);
      Get.snackbar('✅ Annonce publiée !', '',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white);
    }
  }
}

// ══════════════════════════════════════════════════════════════════
//  MES ANNONCES
// ══════════════════════════════════════════════════════════════════

class _MesAnnoncesSheet extends GetView<AnnoncesController> {
  const _MesAnnoncesSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D18),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text('Mes annonces',
                      style: TextStyle(
                          fontFamily: 'Syne',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child:  Icon(Icons.close_rounded,
                        color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Obx(() {
                if (controller.isLoadingMesAnnonces.value) {
                  return  Center(
                      child:
                          CircularProgressIndicator(color: AppColors.accent));
                }
                final list = controller.mesAnnonces;
                if (list.isEmpty) {
                  return  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.campaign_outlined,
                            size: 48, color: AppColors.textMuted),
                        SizedBox(height: 12),
                        Text('Aucune annonce publiée',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 15)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _MesAnnoncesItem(annonce: list[i]),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _MesAnnoncesItem extends GetView<AnnoncesController> {
  final AnnonceModel annonce;
  const _MesAnnoncesItem({required this.annonce});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          if (annonce.mediaUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: annonce.mediaUrl!,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _placeholder(),
              ),
            )
          else
            _placeholder(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  annonce.titre == '📸' ? 'Annonce photo' : annonce.titre,
                  style:  TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.favorite_rounded,
                      size: 12, color: Colors.red),
                  const SizedBox(width: 3),
                  Text('${annonce.likes}',
                      style:  TextStyle(
                          fontSize: 11, color: AppColors.textMuted)),
                  const SizedBox(width: 10),
                   Icon(Icons.chat_bubble_outline_rounded,
                      size: 12, color: AppColors.textMuted),
                  const SizedBox(width: 3),
                  Text('${annonce.reponsesCount}',
                      style:  TextStyle(
                          fontSize: 11, color: AppColors.textMuted)),
                  const SizedBox(width: 10),
                   Icon(Icons.visibility_outlined,
                      size: 12, color: AppColors.textMuted),
                  const SizedBox(width: 3),
                  Text('${annonce.viewsCount}',
                      style:  TextStyle(
                          fontSize: 11, color: AppColors.textMuted)),
                ]),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => controller.supprimerAnnonce(annonce.id),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: Colors.red, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child:  Center(
          child: Icon(Icons.campaign_rounded,
              color: AppColors.textMuted, size: 28),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════
//  RÉPONDRE EN PV (inchangé — copié tel quel)
// ══════════════════════════════════════════════════════════════════

class _RepondreEnPVSheet extends StatefulWidget {
  final AnnonceModel annonce;
  const _RepondreEnPVSheet({required this.annonce});

  @override
  State<_RepondreEnPVSheet> createState() => _RepondreEnPVSheetState();
}

class _RepondreEnPVSheetState extends State<_RepondreEnPVSheet> {
  final _msgCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  String get _catEmoji {
    const m = {
      'rencontre': '💕',
      'amitie': '🤝',
      'sortie': '🎉',
      'voyage': '✈️',
    };
    return m[widget.annonce.categorie] ?? '📢';
  }

  @override
  Widget build(BuildContext context) {
    final annonce = widget.annonce;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D18),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Répondre à l\'annonce',
                    style: TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.accent.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: AppColors.gradientPink,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text('$_catEmoji ',
                                style: const TextStyle(fontSize: 13)),
                            Text(
                              annonce.isAnonyme ? 'Anonyme' : annonce.userName,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.accent),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          Text(
                            annonce.titre == '📸'
                                ? 'Annonce photo'
                                : annonce.titre,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: _msgCtrl,
                  autofocus: true,
                  maxLines: 3,
                  minLines: 2,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration:  InputDecoration(
                    hintText: 'Écris ton message...',
                    hintStyle:
                        TextStyle(color: AppColors.textMuted, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: GestureDetector(
                onTap: _sending ? null : _envoyer,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientPink,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.accent.withOpacity(0.3),
                          blurRadius: 16)
                    ],
                  ),
                  child: _sending
                      ? const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          ),
                        )
                      : const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.send_rounded,
                                  color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text('Envoyer en privé',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _envoyer() async {
    final texte = _msgCtrl.text.trim();
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    setState(() => _sending = true);
    try {
      final annonce = widget.annonce;
      final existing = await Supabase.instance.client
          .from('conversations')
          .select('id')
          .or('and(user1_id.eq.$uid,user2_id.eq.${annonce.userId}),'
              'and(user1_id.eq.${annonce.userId},user2_id.eq.$uid)')
          .maybeSingle();

      String convId;
      if (existing != null) {
        convId = existing['id'] as String;
      } else {
        final created = await Supabase.instance.client
            .from('conversations')
            .insert({'user1_id': uid, 'user2_id': annonce.userId})
            .select('id')
            .single();
        convId = created['id'] as String;
      }

      final now = DateTime.now().toIso8601String();
      await Supabase.instance.client.from('messages').insert({
        'conversation_id': convId,
        'sender_id': uid,
        'type': 'annonce_reply',
        'content': texte.isEmpty ? '📢 A répondu à une annonce' : texte,
        'payload': {
          'annonceId': annonce.id,
          'annonceTitre':
              annonce.titre == '📸' ? 'Annonce photo' : annonce.titre,
          'annonceDescription': annonce.description.length > 100
              ? '${annonce.description.substring(0, 100)}...'
              : annonce.description,
          'annonceMediaUrl': annonce.mediaUrl,
          'annonceIsVideo': annonce.isVideo,
          'annonceAuteur': annonce.isAnonyme ? 'Anonyme' : annonce.userName,
          'annonceCategorie': annonce.categorie,
        },
        'status': 'sent',
        'created_at': now,
      });
      await Supabase.instance.client
          .from('conversations')
          .update({'updated_at': now}).eq('id', convId);

      if (mounted) {
        Navigator.pop(context);
        Get.toNamed('/chat/conversation',
            arguments: ConversationModel(
              id: convId,
              userId: annonce.userId,
              userName: annonce.isAnonyme ? 'Anonyme' : annonce.userName,
              userPhotoUrl: annonce.isAnonyme ? null : annonce.userPhotoUrl,
              isOnline: false,
              unreadCount: 0,
            ));
      }
    } catch (e) {
      debugPrint('_envoyer error: $e');
      Get.snackbar('Erreur', 'Impossible d\'envoyer',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.red.shade900,
          colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

// ══════════════════════════════════════════════════════════════════
//  COMMENTAIRES (inchangés)
// ══════════════════════════════════════════════════════════════════

class AnnonceCommentsSheet extends StatelessWidget {
  final AnnonceModel annonce;
  const AnnonceCommentsSheet({super.key, required this.annonce});

  static void show(BuildContext context, {required AnnonceModel annonce}) {
    if (!annonce.commentsEnabled) {
      Get.snackbar(
          'Commentaires désactivés', 'L\'auteur a désactivé les commentaires',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white);
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => AnnonceCommentsSheet(annonce: annonce),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tag = 'comments_${annonce.id}';
    final ctrl = Get.put(AnnonceCommentController(annonce: annonce), tag: tag);
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollCtrl) => _CommentsContent(
        annonce: annonce,
        ctrl: ctrl,
        tag: tag,
        scrollCtrl: scrollCtrl,
      ),
    );
  }
}

class _CommentsContent extends StatefulWidget {
  final AnnonceModel annonce;
  final AnnonceCommentController ctrl;
  final String tag;
  final ScrollController scrollCtrl;

  const _CommentsContent({
    required this.annonce,
    required this.ctrl,
    required this.tag,
    required this.scrollCtrl,
  });

  @override
  State<_CommentsContent> createState() => _CommentsContentState();
}

class _CommentsContentState extends State<_CommentsContent> {
  final FocusNode _focus = FocusNode();
  String? _myPhotoUrl;

  @override
  void initState() {
    super.initState();
    _loadMyPhoto();
  }

  Future<void> _loadMyPhoto() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('photo_url')
          .eq('id', uid)
          .maybeSingle();
      if (mounted) setState(() => _myPhotoUrl = data?['photo_url'] as String?);
    } catch (_) {}
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D18),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF2E2E4A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
            child: Row(
              children: [
                Obx(() {
                  final n = widget.ctrl.comments
                      .fold(0, (s, c) => s + 1 + c.replies.length);
                  return Text('Commentaires  $n',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Syne'));
                }),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    Get.delete<AnnonceCommentController>(tag: widget.tag);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                        color: Color(0xFF1E1E30), shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded,
                        color: Color(0xFF8080B0), size: 16),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: const Color(0xFF1E1E30)),
          Expanded(
            child: Obx(() {
              if (widget.ctrl.loading.value) {
                return  Center(
                  child: CircularProgressIndicator(
                      color: AppColors.accent, strokeWidth: 2),
                );
              }
              final comments = widget.ctrl.comments;
              final pinnedId = widget.annonce.pinnedCommentId;
              if (comments.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('💬', style: TextStyle(fontSize: 48)),
                      SizedBox(height: 12),
                      Text('Aucun commentaire',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      SizedBox(height: 6),
                      Text('Sois le premier à commenter',
                          style: TextStyle(
                              color: Color(0xFF6060A0), fontSize: 13)),
                    ],
                  ),
                );
              }
              AnnonceCommentModel? pinned;
              List<AnnonceCommentModel> others = [];
              for (final c in comments) {
                if (c.id == pinnedId)
                  pinned = c;
                else
                  others.add(c);
              }
              return ListView(
                controller: widget.scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  if (pinned != null) ...[
                    _PinnedBadge(),
                    const SizedBox(height: 4),
                    _CommentTile(
                        comment: pinned,
                        ctrl: widget.ctrl,
                        isReply: false,
                        isPinned: true),
                    Container(
                      height: 0.5,
                      color: const Color(0xFF1E1E30),
                      margin: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ],
                  ...others.map((c) => _CommentTile(
                      comment: c,
                      ctrl: widget.ctrl,
                      isReply: false,
                      isPinned: false)),
                ],
              );
            }),
          ),
          Obx(() {
            final name = widget.ctrl.replyingToName.value;
            if (name.isEmpty) return const SizedBox.shrink();
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF111120),
              child: Row(
                children: [
                  ShaderMask(
                    shaderCallback: (b) =>
                        AppColors.gradientPink.createShader(b),
                    child: const Icon(Icons.reply_rounded,
                        color: Colors.white, size: 14),
                  ),
                  const SizedBox(width: 8),
                  const Text('Répondre à ',
                      style: TextStyle(color: Color(0xFF8080B0), fontSize: 12)),
                  Text(name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.ctrl.cancelReply,
                    child: const Icon(Icons.close_rounded,
                        color: Color(0xFF6060A0), size: 15),
                  ),
                ],
              ),
            );
          }),
          Container(
            padding: EdgeInsets.only(
              left: 14,
              right: 14,
              top: 10,
              bottom: MediaQuery.of(context).viewInsets.bottom > 0
                  ? MediaQuery.of(context).viewInsets.bottom + 8
                  : MediaQuery.of(context).padding.bottom + 14,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF0D0D18),
              border: Border(top: BorderSide(color: Color(0xFF1E1E30))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  margin: const EdgeInsets.only(right: 10, bottom: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.accent.withOpacity(0.4), width: 1.5),
                  ),
                  child: ClipOval(
                    child: _myPhotoUrl != null
                        ? CachedNetworkImage(
                            imageUrl: _myPhotoUrl!, fit: BoxFit.cover)
                        : Container(
                            color: AppColors.accent.withOpacity(0.2),
                            child:  Icon(Icons.person_rounded,
                                color: AppColors.accent, size: 18),
                          ),
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF2A2A45)),
                    ),
                    child: TextField(
                      controller: widget.ctrl.textCtrl,
                      focusNode: _focus,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      maxLines: 4,
                      minLines: 1,
                      maxLength: 500,
                      buildCounter: (_,
                              {required currentLength,
                              required isFocused,
                              maxLength}) =>
                          null,
                      decoration: const InputDecoration(
                        hintText: 'Ajouter un commentaire...',
                        hintStyle:
                            TextStyle(color: Color(0xFF4A4A70), fontSize: 13),
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Obx(() => GestureDetector(
                      onTap: widget.ctrl.sending.value
                          ? null
                          : widget.ctrl.sendComment,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 38,
                        height: 38,
                        margin: const EdgeInsets.only(bottom: 2),
                        decoration: BoxDecoration(
                          gradient: widget.ctrl.sending.value
                              ? null
                              : AppColors.gradientPink,
                          color: widget.ctrl.sending.value
                              ? const Color(0xFF1E1E30)
                              : null,
                          shape: BoxShape.circle,
                        ),
                        child: widget.ctrl.sending.value
                            ? const Center(
                                child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              ))
                            : const Icon(Icons.send_rounded,
                                color: Colors.white, size: 17),
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PinnedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Row(children: [
        Icon(Icons.push_pin_rounded, size: 11, color: Color(0xFF8080B0)),
        SizedBox(width: 4),
        Text('Commentaire épinglé',
            style: TextStyle(
                fontSize: 11,
                color: Color(0xFF8080B0),
                fontWeight: FontWeight.w500)),
      ]);
}

class _CommentTile extends StatelessWidget {
  final AnnonceCommentModel comment;
  final AnnonceCommentController ctrl;
  final bool isReply;
  final bool isPinned;

  const _CommentTile({
    required this.comment,
    required this.ctrl,
    required this.isReply,
    required this.isPinned,
  });

  static String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays >= 365) return '${(diff.inDays / 365).floor()}a';
    if (diff.inDays >= 30) return '${(diff.inDays / 30).floor()}mo';
    if (diff.inDays >= 7) return '${(diff.inDays / 7).floor()}sem';
    if (diff.inDays >= 1) return '${diff.inDays}j';
    if (diff.inHours >= 1) return '${diff.inHours}h';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}min';
    return 'maintenant';
  }

  void _onLongPress(BuildContext context) {
    final myUid = Supabase.instance.client.auth.currentUser?.id;
    final isOwn = comment.userId == myUid;
    final isAnnonceOwner = ctrl.annonce.userId == myUid;
    if (!isOwn && !isAnnonceOwner) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D0D18),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: const Color(0xFF2E2E4A),
                  borderRadius: BorderRadius.circular(2)),
            ),
            if (isAnnonceOwner && !isReply)
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(
                    ctrl.annonce.pinnedCommentId == comment.id
                        ? Icons.push_pin_outlined
                        : Icons.push_pin_rounded,
                    color: AppColors.accent,
                    size: 18,
                  ),
                ),
                title: Text(
                  ctrl.annonce.pinnedCommentId == comment.id
                      ? 'Désépingler'
                      : 'Épingler',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14),
                ),
                onTap: () {
                  Navigator.pop(context);
                  ctrl.epinglerOuDesepingler(comment);
                },
              ),
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.delete_outline_rounded,
                    color: Colors.red, size: 18),
              ),
              title: Text(
                isAnnonceOwner && !isOwn
                    ? 'Supprimer (modération)'
                    : 'Supprimer',
                style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                    fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(context);
                ctrl.deleteComment(comment);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSending = comment.id.startsWith('temp_');
    final double avatarR = isReply ? 14 : 18;

    return Opacity(
      opacity: isSending ? 0.6 : 1.0,
      child: GestureDetector(
        onLongPress: isSending ? null : () => _onLongPress(context),
        child: Padding(
          padding: EdgeInsets.only(
            left: isReply ? 48 : 0,
            top: isReply ? 8 : 10,
            bottom: isReply ? 0 : 4,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  if (comment.isAnonyme) return;
                  Get.toNamed('/profile/view',
                      arguments: UserModel(
                        id: comment.userId,
                        name: comment.userName,
                        age: 18,
                        photoUrl: comment.userPhotoUrl,
                        isOnline: false,
                        interests: [],
                      ));
                },
                child: CircleAvatar(
                  radius: avatarR,
                  backgroundColor: const Color(0xFF1E1E30),
                  backgroundImage: comment.userPhotoUrl != null
                      ? CachedNetworkImageProvider(comment.userPhotoUrl!)
                      : null,
                  child: comment.userPhotoUrl == null
                      ? Icon(
                          comment.isAnonyme
                              ? Icons.person_outline_rounded
                              : Icons.person_rounded,
                          color: const Color(0xFF4A4A70),
                          size: avatarR)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(
                        comment.isAnonyme ? 'Anonyme' : comment.userName,
                        style: TextStyle(
                            color: comment.isAnonyme
                                ? const Color(0xFF6060A0)
                                : Colors.white,
                            fontSize: isReply ? 12 : 13,
                            fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 6),
                      Text(_ago(comment.createdAt),
                          style: const TextStyle(
                              color: Color(0xFF4A4A70), fontSize: 11)),
                      if (isPinned) ...[
                        const SizedBox(width: 6),
                         Icon(Icons.push_pin_rounded,
                            size: 10, color: AppColors.accent),
                      ],
                      if (isSending) ...[
                        const SizedBox(width: 6),
                         SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                              color: AppColors.accent, strokeWidth: 1.5),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Text(comment.texte,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.88),
                            fontSize: isReply ? 13 : 14,
                            height: 1.4)),
                    const SizedBox(height: 6),
                    if (!isReply)
                      GestureDetector(
                        onTap: () =>
                            ctrl.startReply(comment.id, comment.userName),
                        child: const Text('Répondre',
                            style: TextStyle(
                                color: Color(0xFF5050A0),
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                    if (comment.replies.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ...comment.replies.map((r) => _CommentTile(
                          comment: r,
                          ctrl: ctrl,
                          isReply: true,
                          isPinned: false)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (!isSending)
                GestureDetector(
                  onTap: () => ctrl.toggleLike(comment),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(scale: anim, child: child),
                        child: Icon(
                          comment.isLiked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          key: ValueKey(comment.isLiked),
                          color: comment.isLiked
                              ? const Color(0xFFFF3CAC)
                              : const Color(0xFF4A4A70),
                          size: isReply ? 14 : 16,
                        ),
                      ),
                      if (comment.likes > 0) ...[
                        const SizedBox(height: 2),
                        Text('${comment.likes}',
                            style: TextStyle(
                                color: comment.isLiked
                                    ? const Color(0xFFFF3CAC)
                                    : const Color(0xFF4A4A70),
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  WIDGETS UTILITAIRES
// ══════════════════════════════════════════════════════════════════

class _MediaButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _MediaButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color:
              active ? AppColors.accent.withOpacity(0.15) : AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: active ? AppColors.accent : AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: active ? AppColors.accent : AppColors.textMuted,
                size: 24),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active ? AppColors.accent : AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;

  const _InputField({
    required this.controller,
    required this.hint,
    required this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style:  TextStyle(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:  TextStyle(color: AppColors.textMuted),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}

class _ToggleOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onToggle;

  const _ToggleOption({
    required this.icon,
    required this.label,
    required this.active,
    required this.color,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.12) : AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? color : AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: active ? color.withOpacity(0.2) : AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 18, color: active ? color : AppColors.textMuted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: active ? color : AppColors.textPrimary)),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 24,
              decoration: BoxDecoration(
                color: active ? color : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: active ? color : AppColors.border),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment:
                    active ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MenuItem(this.icon, this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class BoostProfilWidget extends StatelessWidget {
  const BoostProfilWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _sheet(context),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: const Color(0xFFFFD700).withOpacity(0.4), blurRadius: 12)
          ],
        ),
        child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
      ),
    );
  }

  void _sheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFFFFD700).withOpacity(0.4),
                      blurRadius: 20)
                ],
              ),
              child:
                  const Icon(Icons.bolt_rounded, color: Colors.white, size: 42),
            ),
            const SizedBox(height: 20),
             Text('Booster ton profil',
                style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () async {
                Navigator.pop(context);
                if (!Get.isRegistered<AnnoncesController>())
                  Get.put(AnnoncesController());
                await Get.find<AnnoncesController>().boosterProfil();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Center(
                  child: Text('⚡ Activer le Boost',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
