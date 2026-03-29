import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/features/likes/like_controller.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:rencontre/core/services/supabase_service.dart';

// ══════════════════════════════════════════════════════════════════
//  LIKES SCREEN
// ══════════════════════════════════════════════════════════════════

class LikesScreen extends StatefulWidget {
  const LikesScreen({super.key});

  @override
  State<LikesScreen> createState() => _LikesScreenState();
}

class _LikesScreenState extends State<LikesScreen>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _likesCtrl = Get.find<LikeController>();

  final RxList<UserModel> _whoLikedMe = <UserModel>[].obs;
  final RxList<UserModel> _myMatches = <UserModel>[].obs;
  final RxBool _isLoading = true.obs;

  // ✅ Simule le premium — à brancher sur ton vrai système plus tard
  final bool _isPremium = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    _isLoading.value = true;
    await Future.wait([_loadWhoLikedMe(), _loadMatches()]);
    _isLoading.value = false;
  }

  Future<void> _loadWhoLikedMe() async {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) return;
    try {
      final data = await Supabase.instance.client
          .from('likes')
          .select('from_user_id, profiles!likes_from_user_id_fkey('
              'id, name, photo_url, photo_urls, birthdate, gender, bio, '
              'interests, is_online, latitude, longitude, '
              'followers_count, following_count, matches_count'
              ')')
          .eq('to_user_id', myId)
          .order('created_at', ascending: false);

      _whoLikedMe.value = (data as List).map((row) {
        final p = row['profiles'] as Map<String, dynamic>;
        return _profileToUser(p);
      }).toList();
    } catch (e) {
      debugPrint('_loadWhoLikedMe error: $e');
    }
  }

  Future<void> _loadMatches() async {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) return;
    try {
      final data = await Supabase.instance.client
          .from('matches')
          .select('user1_id, user2_id, created_at')
          .or('user1_id.eq.$myId,user2_id.eq.$myId')
          .order('created_at', ascending: false);

      final otherIds = (data as List).map((r) {
        final u1 = r['user1_id'] as String;
        final u2 = r['user2_id'] as String;
        return u1 == myId ? u2 : u1;
      }).toList();

      if (otherIds.isEmpty) {
        _myMatches.value = [];
        return;
      }

      final profiles = await Supabase.instance.client
          .from('profiles')
          .select('id, name, photo_url, photo_urls, birthdate, gender, bio, '
              'interests, is_online, latitude, longitude, '
              'followers_count, following_count, matches_count')
          .inFilter('id', otherIds);

      _myMatches.value =
          (profiles as List).map((p) => _profileToUser(p)).toList();
    } catch (e) {
      debugPrint('_loadMatches error: $e');
    }
  }

  UserModel _profileToUser(Map<String, dynamic> p) {
    return UserModel(
      id: p['id'] ?? '',
      name: p['name'] ?? 'Utilisateur',
      age: _calcAge(p['birthdate']),
      bio: p['bio'],
      photoUrl: p['photo_url'],
      photoUrls: List<String>.from(p['photo_urls'] ?? []),
      interests: List<String>.from(p['interests'] ?? []),
      gender: p['gender'],
      isOnline: p['is_online'] ?? false,
      latitude: (p['latitude'] as num?)?.toDouble(),
      longitude: (p['longitude'] as num?)?.toDouble(),
      followersCount: p['followers_count'] ?? 0,
      followingCount: p['following_count'] ?? 0,
      matchesCount: p['matches_count'] ?? 0,
    );
  }

  int _calcAge(dynamic birthdate) {
    if (birthdate == null) return 18;
    try {
      final birth = DateTime.parse(birthdate as String);
      final now = DateTime.now();
      int age = now.year - birth.year;
      if (now.month < birth.month ||
          (now.month == birth.month && now.day < birth.day)) age--;
      return age < 0 ? 18 : age;
    } catch (_) {
      return 18;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            _buildHeader(),

            // ── Tabs ──
            _buildTabs(),

            // ── Contenu ──
            Expanded(
              child: Obx(() {
                if (_isLoading.value) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  );
                }
                return TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _buildWhoLikedMe(),
                    _buildMatches(),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (b) => AppColors.gradientPink.createShader(b),
            child: const Text(
              'Likes',
              style: TextStyle(
                fontFamily: 'Syne',
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const Spacer(),
          // Bouton refresh
          GestureDetector(
            onTap: _loadData,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.refresh_rounded,
                  size: 18, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Obx(() {
        final likesCount = _whoLikedMe.length;
        final matchesCount = _myMatches.length;
        return Container(
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: TabBar(
            controller: _tabCtrl,
            indicator: BoxDecoration(
              gradient: AppColors.gradientPink,
              borderRadius: BorderRadius.circular(12),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textMuted,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.favorite_rounded, size: 15),
                    const SizedBox(width: 6),
                    Text('M\'ont liké ($likesCount)'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.favorite_rounded, size: 15),
                    const Icon(Icons.favorite_rounded, size: 15),
                    const SizedBox(width: 6),
                    Text('Matchs ($matchesCount)'),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ── Onglet "Qui m'a liké" ──────────────────────────────────────

  Widget _buildWhoLikedMe() {
    return Obx(() {
      final list = _whoLikedMe;

      if (list.isEmpty) {
        return _buildEmptyState(
          icon: '💔',
          title: 'Pas encore de likes',
          subtitle:
              'Complète ton profil et sois actif\npour recevoir plus de likes',
        );
      }

      return Column(
        children: [
          // Bannière premium si pas premium
          if (!_isPremium) _buildPremiumBanner(),

          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final user = list[i];
                final isBlurred = !_isPremium && i >= 2;
                return _LikeCard(
                  user: user,
                  isBlurred: isBlurred,
                  isMatch: false,
                  onTap:
                      isBlurred ? _showPremiumDialog : () => _voirProfil(user),
                  onMessage: isBlurred ? null : () => _ouvrirChat(user),
                );
              },
            ),
          ),
        ],
      );
    });
  }

  // ── Onglet "Matchs" ───────────────────────────────────────────

  Widget _buildMatches() {
    return Obx(() {
      final list = _myMatches;

      if (list.isEmpty) {
        return _buildEmptyState(
          icon: '💫',
          title: 'Pas encore de matchs',
          subtitle: 'Like des profils pour créer\ndes matchs mutuels',
        );
      }

      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.72,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final user = list[i];
          return _LikeCard(
            user: user,
            isBlurred: false,
            isMatch: true,
            onTap: () => _voirProfil(user),
            onMessage: () => _ouvrirChat(user),
          );
        },
      );
    });
  }

  Widget _buildPremiumBanner() {
    return GestureDetector(
      onTap: _showPremiumDialog,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.accent.withOpacity(0.15),
              AppColors.accent2.withOpacity(0.15),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.accent.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: AppColors.gradientPink,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('👑', style: TextStyle(fontSize: 20)),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Voir tous tes likes',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Passe en Premium pour voir qui t\'a liké',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: AppColors.gradientPink,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Premium',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required String icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(icon, style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Syne',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  void _showPremiumDialog() {
    Get.dialog(
      Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFFA500)]),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                    child: Text('👑', style: TextStyle(fontSize: 30))),
              ),
              const SizedBox(height: 16),
              const Text(
                'SnapMeet Premium',
                style: TextStyle(
                  fontFamily: 'Syne',
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Vois exactement qui t\'a liké,\nsans attendre un match !',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              // Avantages
              _AvantageItem(icon: '👁️', text: 'Voir tous tes likes'),
              const SizedBox(height: 8),
              _AvantageItem(icon: '⚡', text: 'Swipes illimités'),
              const SizedBox(height: 8),
              _AvantageItem(icon: '🚀', text: 'Boost de profil quotidien'),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  Get.back();
                  Get.snackbar(
                    '👑 Premium',
                    'Bientôt disponible !',
                    snackPosition: SnackPosition.TOP,
                    backgroundColor: AppColors.surface,
                    colorText: Colors.white,
                  );
                },
                child: Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFFA500)]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'Passer Premium 👑',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Get.back(),
                child: const Text(
                  'Plus tard',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _voirProfil(UserModel user) {
    Get.toNamed('/profile/view', arguments: user);
  }

  Future<void> _ouvrirChat(UserModel user) async {
    try {
      final service = SupabaseService();
      final convId = await service.getOrCreateConversation(user.id);
      Get.toNamed('/chat/conversation',
          arguments: ConversationModel(
            id: convId,
            userId: user.id,
            userName: user.name,
            userPhotoUrl: user.photoUrl,
            isOnline: user.isOnline,
            unreadCount: 0,
          ));
    } catch (_) {
      Get.snackbar('Erreur', "Impossible d'ouvrir la conversation",
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white);
    }
  }
}

// ── Carte Like ────────────────────────────────────────────────────

class _LikeCard extends StatelessWidget {
  final UserModel user;
  final bool isBlurred;
  final bool isMatch;
  final VoidCallback onTap;
  final VoidCallback? onMessage;

  const _LikeCard({
    required this.user,
    required this.isBlurred,
    required this.isMatch,
    required this.onTap,
    this.onMessage,
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
    final idx =
        user.name.isNotEmpty ? user.name.codeUnitAt(0) % _gradients.length : 0;
    final colors = _gradients[idx];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color:
                isMatch ? AppColors.accent.withOpacity(0.5) : AppColors.border,
            width: isMatch ? 1.5 : 1,
          ),
          boxShadow: isMatch
              ? [
                  BoxShadow(
                    color: AppColors.accent.withOpacity(0.15),
                    blurRadius: 12,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Photo ou avatar dégradé ──
              _buildPhoto(colors),

              // ── Flou si pas premium ──
              if (isBlurred)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.bg.withOpacity(0.1),
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                ),

              // ── Overlay bas ──
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 20, 10, 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.85),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: isBlurred ? _buildBlueBadge() : _buildUserInfo(),
                ),
              ),

              // ── Badge match ──
              if (isMatch && !isBlurred)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: AppColors.gradientPink,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '💘 Match',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

              // ── Badge en ligne ──
              if (user.isOnline && !isBlurred)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.online,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),

              // ── Bouton cadenas si flou ──
              if (isBlurred)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_rounded, color: Colors.white, size: 32),
                      SizedBox(height: 8),
                      Text(
                        'Premium',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
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

  Widget _buildPhoto(List<Color> colors) {
    if (user.photoUrl != null && user.photoUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: user.photoUrl!,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _buildGradientAvatar(colors),
      );
    }
    return _buildGradientAvatar(colors);
  }

  Widget _buildGradientAvatar(List<Color> colors) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 52,
          ),
        ),
      ),
    );
  }

  Widget _buildUserInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${user.name}, ${user.age}',
          style: const TextStyle(
            fontFamily: 'Syne',
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (user.gender != null) ...[
          const SizedBox(height: 2),
          Text(
            user.gender!,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
        ],
        if (onMessage != null) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onMessage,
            child: Container(
              width: double.infinity,
              height: 32,
              decoration: BoxDecoration(
                gradient: AppColors.gradientPink,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'Message',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBlueBadge() {
    return const Center(
      child: Text(
        'Débloquer',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ── Widget avantage ───────────────────────────────────────────────

class _AvantageItem extends StatelessWidget {
  final String icon;
  final String text;
  const _AvantageItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
