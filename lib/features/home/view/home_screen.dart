import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/home/widget/stories_row.dart';
import 'package:rencontre/shared/models/user_model.dart';

// ─── CONTROLLER MESSAGES NON LUS ─────────────────────────────────

class UnreadMessagesController extends GetxController {
  final _sb = Supabase.instance.client;
  final RxMap<String, int> unreadByUser = <String, int>{}.obs;
  RealtimeChannel? _channel;

  @override
  void onInit() {
    super.onInit();
    loadUnread();
    _listenRealtime();
  }

  Future<void> loadUnread() async {
    final myId = _sb.auth.currentUser?.id;
    if (myId == null) return;
    try {
      final data = await _sb
          .from('messages')
          .select('sender_id')
          .eq('receiver_id', myId)
          .eq('is_read', false);

      final Map<String, int> counts = {};
      if (data != null) {
        for (final msg in (data as List)) {
          final senderId = msg['sender_id'] as String;
          counts[senderId] = (counts[senderId] ?? 0) + 1;
        }
      }
      unreadByUser.assignAll(counts);
    } catch (e) {
      debugPrint('loadUnread error: $e');
    }
  }

  void _listenRealtime() {
    final myId = _sb.auth.currentUser?.id;
    if (myId == null) return;
    _channel = _sb
        .channel('public:messages:unread')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: myId,
          ),
          callback: (payload) => loadUnread(),
        )
        .subscribe();
  }

  int unreadFrom(String userId) => unreadByUser[userId] ?? 0;

  @override
  void onClose() {
    _channel?.unsubscribe();
    super.onClose();
  }
}

// ─── ÉCRAN ACCUEIL ───────────────────────────────────────────────

class HomeScreen extends GetView<HomeController> {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<UnreadMessagesController>()) {
      Get.put(UnreadMessagesController(), permanent: true);
    }

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      statusBarColor: Colors.transparent,
    ));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(child: _HomeBody()),
    );
  }
}

class _HomeBody extends StatefulWidget {
  @override
  State<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<_HomeBody> {
  final ScrollController _scrollCtrl = ScrollController();
  bool _storiesVisible = true;
  bool _showScrollTop = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    final offset = _scrollCtrl.offset;
    final newStoriesVisible = offset < 80;
    final newShowTop = offset > 400;

    if (newStoriesVisible != _storiesVisible || newShowTop != _showScrollTop) {
      setState(() {
        _storiesVisible = newStoriesVisible;
        _showScrollTop = newShowTop;
      });
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            const _TopBar(),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: _storiesVisible ? 110 : 0,
              child: ClipRect(
                child: _storiesVisible
                    ? const StoriesRow()
                    : const SizedBox.shrink(),
              ),
            ),
            const _FilterChips(),
            const SizedBox(height: 8),
            Expanded(child: _UsersGridScrollable(scrollCtrl: _scrollCtrl)),
          ],
        ),
        if (_showScrollTop)
          Positioned(
            bottom: 20,
            right: 16,
            child: FloatingActionButton.small(
              onPressed: () => _scrollCtrl.animateTo(0,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.fastOutSlowIn),
              backgroundColor: AppColors.accent,
              child: const Icon(Icons.arrow_upward, color: Colors.white),
            ),
          ),
      ],
    );
  }
}

// ─── TOP BAR ─────────────────────────────────────────────────────

class _TopBar extends GetView<HomeController> {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (b) => AppColors.gradientPink.createShader(b),
            child: const Text('SnapMeet',
                style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.8)),
          ),
          const Spacer(),
          Obx(() => controller.locationError.value
              ? _IconBtn(
                  icon: Icons.location_off_rounded,
                  onTap: controller.openLocationSettings,
                  color: AppColors.accent.withOpacity(0.1),
                  iconColor: AppColors.accent,
                )
              : const SizedBox.shrink()),
          const SizedBox(width: 8),
          _IconBtn(icon: Icons.search_rounded, onTap: () {}),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              Get.snackbar('Boost', 'Profil boosté pour 30 minutes !',
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: Colors.orange,
                  colorText: Colors.white);
            },
            child: Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orangeAccent,
                    blurRadius: 10,
                    spreadRadius: 1,
                  )
                ],
              ),
              child:
                  const Icon(Icons.bolt_rounded, color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color, iconColor;
  const _IconBtn(
      {required this.icon, required this.onTap, this.color, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color ?? AppColors.surface2,
          border: Border.all(color: AppColors.border.withOpacity(0.5)),
        ),
        child: Icon(icon, size: 20, color: iconColor ?? AppColors.textPrimary),
      ),
    );
  }
}

// ─── FILTRES ─────────────────────────────────────────────────────

class _FilterChips extends GetView<HomeController> {
  const _FilterChips();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Obx(() => _Chip(
              label: 'Tous',
              icon: '⚡',
              isActive: controller.filterMode.value == 'all',
              onTap: () => controller.setFilter('all'))),
          const SizedBox(width: 8),
          Obx(() => _Chip(
              label: 'En ligne',
              icon: '🟢',
              isActive: controller.filterMode.value == 'online',
              onTap: () => controller.setFilter('online'))),
          const SizedBox(width: 8),
          Obx(() => _Chip(
              label: 'Proches',
              icon: '📍',
              isActive: controller.filterMode.value == 'nearby',
              onTap: () => controller.setFilter('nearby'))),
          const SizedBox(width: 8),
          Obx(() => _Chip(
              label: 'Nouveaux',
              icon: '✨',
              isActive: controller.filterMode.value == 'new',
              onTap: () => controller.setFilter('new'))),
          const SizedBox(width: 8),
          const _AdvancedFilterBtn(),
        ],
      ),
    );
  }
}

class _AdvancedFilterBtn extends GetView<HomeController> {
  const _AdvancedFilterBtn();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final hasActiveFilters = controller.filterGender.value != 'tous' ||
          controller.filterDistance.value < 50;
      return GestureDetector(
        onTap: () {},
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: hasActiveFilters
                ? AppColors.accent.withOpacity(0.1)
                : AppColors.surface2,
            border: Border.all(
                color: hasActiveFilters ? AppColors.accent : AppColors.border),
          ),
          child: Row(
            children: [
              Icon(Icons.tune_rounded,
                  size: 16,
                  color: hasActiveFilters
                      ? AppColors.accent
                      : AppColors.textMuted),
              const SizedBox(width: 6),
              Text('Filtres',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: hasActiveFilters
                          ? AppColors.accent
                          : AppColors.textMuted)),
            ],
          ),
        ),
      );
    });
  }
}

// ─── GRILLE UTILISATEURS ─────────────────────────────────────────

class _UsersGridScrollable extends GetView<HomeController> {
  final ScrollController scrollCtrl;
  const _UsersGridScrollable({required this.scrollCtrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoadingUsers.value) return _buildShimmer();
      final users = controller.filteredUsers;
      if (users.isEmpty) return _buildEmpty();

      return RefreshIndicator(
        onRefresh: controller.loadProfiles,
        color: AppColors.accent,
        child: GridView.builder(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 100),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.75,
          ),
          itemCount: users.length,
          itemBuilder: (_, i) {
            final user = users[i];
            return Obx(() {
              final unreadCount =
                  Get.find<UnreadMessagesController>().unreadFrom(user.id);
              final hasStory = controller.userHasActiveStory(user.id);
              final storyIsSeen = controller.userStoryIsSeen(user.id);

              return _UserCard(
                user: user,
                unreadCount: unreadCount,
                hasActiveStory: hasStory,
                storyIsSeen: storyIsSeen,
                onTap: () => controller.openProfile(user),
              );
            });
          },
        ),
      );
    });
  }

  Widget _buildShimmer() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.75),
      itemCount: 12,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: AppColors.surface2,
        highlightColor: AppColors.border,
        child: Container(
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12))),
      ),
    );
  }

  Widget _buildEmpty() {
    final filter = controller.filterMode.value;
    final msg = filter == 'new'
        ? 'Aucun nouveau membre'
        : filter == 'online'
            ? 'Personne en ligne'
            : filter == 'nearby'
                ? 'Personne à proximité'
                : 'Aucun profil disponible';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_search_rounded,
              size: 64, color: AppColors.textMuted.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(msg,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppColors.textPrimary)),
          TextButton(
              onPressed: controller.loadProfiles,
              child: const Text('Réessayer')),
        ],
      ),
    );
  }
}

// ─── CARTE UTILISATEUR ───────────────────────────────────────────

class _UserCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTap;
  final int unreadCount;
  final bool hasActiveStory;
  final bool storyIsSeen;

  const _UserCard({
    required this.user,
    required this.onTap,
    this.unreadCount = 0,
    this.hasActiveStory = false,
    this.storyIsSeen = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasUnread = unreadCount > 0;
    final bool showUnreadBorder = hasUnread;
    final bool showStoryBorder = !hasUnread && hasActiveStory;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: showUnreadBorder
              ? Border.all(color: const Color(0xFFFFD700), width: 2)
              : showStoryBorder
                  ? Border.all(
                      color: storyIsSeen ? AppColors.border : AppColors.accent,
                      width: 2)
                  : null,
          boxShadow: showUnreadBorder
              ? [
                  BoxShadow(
                      color: const Color(0xFFFFD700).withOpacity(0.3),
                      blurRadius: 8)
                ]
              : showStoryBorder && !storyIsSeen
                  ? [
                      BoxShadow(
                          color: AppColors.accent.withOpacity(0.35),
                          blurRadius: 10,
                          spreadRadius: 0)
                    ]
                  : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Photo ──────────────────────────────────────
              user.photoUrl != null && user.photoUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: user.photoUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _GradientAvatar(name: user.name),
                      errorWidget: (_, __, ___) =>
                          _GradientAvatar(name: user.name),
                    )
                  : _GradientAvatar(name: user.name),

              // ── Gradient bas ───────────────────────────────
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.8)
                      ],
                      stops: const [0.5, 1.0],
                    ),
                  ),
                ),
              ),

              // ── Nom + distance ─────────────────────────────
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${user.name}, ${user.age}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis),
                    if (user.distanceMeters != null)
                      Text(HomeController.formatDistance(user.distanceMeters),
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 9)),
                  ],
                ),
              ),

              // ── Badge "Nouveau" hors ligne ─────────────────
              if (user.isNewMember && !user.isOnline)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      // ✅ Même gradient que l'app (rose → violet)
                      gradient: AppColors.gradientPink,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Nouveau',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 7,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3),
                    ),
                  ),
                ),

              // ── Badge "Nouveau" + dot en ligne ────────────
              if (user.isNewMember && user.isOnline)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: Colors.green, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          // ✅ Même gradient que l'app (rose → violet)
                          gradient: AppColors.gradientPink,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Nouveau',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 7,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Dot online seul (sans badge nouveau) ───────
              if (user.isOnline && !user.isNewMember)
                Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: Colors.green, shape: BoxShape.circle))),

              // ── Icône story ────────────────────────────────
              if (hasActiveStory && !hasUnread)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 22,
                    height: 22,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: storyIsSeen
                          ? null
                          : const LinearGradient(
                              colors: [
                                AppColors.accent,
                                AppColors.accent2,
                                AppColors.accent3,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      color: storyIsSeen ? AppColors.border : null,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.3),
                      ),
                      child: const Icon(
                        Icons.play_circle_filled_rounded,
                        color: Colors.white,
                        size: 11,
                      ),
                    ),
                  ),
                ),

              // ── Badge messages non lus ─────────────────────
              if (hasUnread)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        color: Color(0xFFFFD700), shape: BoxShape.circle),
                    child: Text(unreadCount > 9 ? '9+' : '$unreadCount',
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 9,
                            fontWeight: FontWeight.w900)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── WIDGETS COMMUNS ─────────────────────────────────────────────

class _GradientAvatar extends StatelessWidget {
  final String name;
  const _GradientAvatar({required this.name});

  static const _palettes = [
    [Color(0xFFFF6B6B), Color(0xFFFECA57)],
    [Color(0xFF48DBFB), Color(0xFFFF9FF3)],
    [Color(0xFFFF9F43), Color(0xFFEE5A24)],
    [Color(0xFFA29BFE), Color(0xFF6C5CE7)],
    [Color(0xFFFD79A8), Color(0xFFE84393)],
    [Color(0xFF55EFC4), Color(0xFF00B894)],
    [Color(0xFFFF3CAC), Color(0xFF7B2FFF)],
    [Color(0xFF7B2FFF), Color(0xFF00F5D4)],
  ];

  @override
  Widget build(BuildContext context) {
    final idx = name.isNotEmpty ? name.codeUnitAt(0) % _palettes.length : 0;
    final colors = _palettes[idx];

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
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label, icon;
  final bool isActive;
  final VoidCallback onTap;
  const _Chip(
      {required this.label,
      required this.icon,
      required this.isActive,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isActive ? AppColors.accent : AppColors.surface2,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: isActive ? Colors.white : AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
