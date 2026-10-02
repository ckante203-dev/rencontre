import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/services/revenue_cat_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/core/utils/app_routes.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/home/widget/stories_row.dart';
import 'package:rencontre/features/premium/view/boost_sheet.dart';
import 'package:rencontre/features/notifications/controller/notification_controller.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
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
      final convData = await _sb
          .from('conversations')
          .select('id')
          .or('user1_id.eq.$myId,user2_id.eq.$myId');
      final convIds = (convData as List).map((c) => c['id'] as String).toList();

      if (convIds.isEmpty) {
        unreadByUser.clear();
        return;
      }

      final data = await _sb
          .from('messages')
          .select('sender_id')
          .inFilter('conversation_id', convIds)
          .neq('sender_id', myId)
          .eq('is_read', false);

      final Map<String, int> counts = {};
      for (final msg in (data as List)) {
        final senderId = msg['sender_id'] as String;
        counts[senderId] = (counts[senderId] ?? 0) + 1;
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
        .channel('public:messages:unread:$myId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (payload) => _scheduleLoadUnread(),
        )
        .subscribe();
  }

  // ✅ Anti-rebond : chaque événement messages déclenchait 2 requêtes ;
  // une rafale de messages ne provoque plus qu'un seul rechargement.
  Timer? _reloadDebounce;

  void _scheduleLoadUnread() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 1500), () {
      _reloadDebounce = null;
      loadUnread();
    });
  }

  int unreadFrom(String userId) => unreadByUser[userId] ?? 0;

  @override
  void onClose() {
    _reloadDebounce?.cancel();
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
    if (!Get.isRegistered<NotificationController>()) {
      Get.put(NotificationController(), permanent: true);
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
          GestureDetector(
            onTap: showBoostSheet,
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
              child: Stack(clipBehavior: Clip.none, children: [
                const Center(
                    child: Icon(Icons.bolt_rounded,
                        color: Colors.white, size: 24)),
                // Point vert : Boost en cours
                Obx(() => (controller.myProfile?.estBooste ?? false)
                    ? Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.online,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.bg, width: 2),
                          ),
                        ),
                      )
                    : const SizedBox.shrink()),
              ]),
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

// ─── FILTRES (avec curseur animé qui glisse vers l'onglet actif) ──

class _FilterItem {
  final String mode, label, icon;
  const _FilterItem(
      {required this.mode, required this.label, required this.icon});
}

const _filterItems = [
  _FilterItem(mode: 'all', label: 'Tous', icon: '⚡'),
  _FilterItem(mode: 'online', label: 'En ligne', icon: '🟢'),
  _FilterItem(mode: 'nearby', label: 'Proches', icon: '📍'),
  _FilterItem(mode: 'new', label: 'Nouveaux', icon: '✨'),
];

class _FilterChips extends StatefulWidget {
  const _FilterChips();

  @override
  State<_FilterChips> createState() => _FilterChipsState();
}

class _FilterChipsState extends State<_FilterChips> {
  final HomeController controller = Get.find<HomeController>();

  final GlobalKey _stackKey = GlobalKey();
  final Map<String, GlobalKey> _chipKeys = {
    for (final f in _filterItems) f.mode: GlobalKey(),
  };

  Rect? _indicatorRect;
  String? _lastMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateIndicator());
  }

  void _updateIndicator() {
    final mode = controller.filterMode.value;
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final chipBox =
        _chipKeys[mode]?.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || chipBox == null || !stackBox.attached) return;

    final chipOffset = chipBox.localToGlobal(Offset.zero, ancestor: stackBox);
    final rect = Rect.fromLTWH(
      chipOffset.dx,
      chipOffset.dy,
      chipBox.size.width,
      chipBox.size.height,
    );

    if (_indicatorRect != rect || _lastMode != mode) {
      setState(() {
        _indicatorRect = rect;
        _lastMode = mode;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Obx(() {
        WidgetsBinding.instance.addPostFrameCallback((_) => _updateIndicator());
        final activeMode = controller.filterMode.value;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Stack(
            key: _stackKey,
            clipBehavior: Clip.none,
            children: [
              if (_indicatorRect != null)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  left: _indicatorRect!.left,
                  top: _indicatorRect!.top,
                  width: _indicatorRect!.width,
                  height: _indicatorRect!.height,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withOpacity(0.4),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),
              Row(
                children: [
                  for (final f in _filterItems) ...[
                    _Chip(
                      key: _chipKeys[f.mode],
                      label: f.label,
                      icon: f.icon,
                      isActive: activeMode == f.mode,
                      onTap: () => controller.setFilter(f.mode),
                    ),
                    const SizedBox(width: 8),
                  ],
                  const _AdvancedFilterBtn(),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ─── BOUTON FILTRES AVANCÉS ──

class _AdvancedFilterBtn extends GetView<HomeController> {
  const _AdvancedFilterBtn();

  void _openAdvancedFilters(BuildContext context) {
    Get.bottomSheet(
      const _AdvancedFilterSheet(),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final hasActiveFilters = controller.filterGender.value != 'tous' ||
          controller.filterDistance.value < 50;
      return GestureDetector(
        onTap: () => _openAdvancedFilters(context),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: hasActiveFilters
                ? AppColors.accent.withOpacity(0.1)
                : AppColors.surface2,
            border: Border.all(
                color: hasActiveFilters ? AppColors.accent : AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
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

// ─── BOTTOM SHEET FILTRES AVANCÉS (genre + distance) ──

class _AdvancedFilterSheet extends StatefulWidget {
  const _AdvancedFilterSheet();

  @override
  State<_AdvancedFilterSheet> createState() => _AdvancedFilterSheetState();
}

class _AdvancedFilterSheetState extends State<_AdvancedFilterSheet> {
  final HomeController controller = Get.find<HomeController>();

  late String _gender;
  late double _distance;

  static const _genders = [
    {'value': 'tous', 'label': 'Tous', 'icon': '👥'},
    {'value': 'homme', 'label': 'Hommes', 'icon': '👨'},
    {'value': 'femme', 'label': 'Femmes', 'icon': '👩'},
  ];

  @override
  void initState() {
    super.initState();
    _gender = controller.filterGender.value;
    _distance = controller.filterDistance.value;
  }

  void _reset() {
    setState(() {
      _gender = 'tous';
      _distance = 50.0;
    });
  }

  void _apply() {
    controller.filterGender.value = _gender;
    controller.filterDistance.value = _distance;
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Filtres avancés',
                style: TextStyle(
                  fontFamily: 'Syne',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              TextButton(
                onPressed: _reset,
                child: Text(
                  'Réinitialiser',
                  style: TextStyle(color: AppColors.accent, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'JE VEUX VOIR',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: _genders.map((g) {
              final isActive = _gender == g['value'];
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _gender = g['value']!),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.accent.withOpacity(0.15)
                          : AppColors.surface2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isActive ? AppColors.accent : AppColors.border,
                        width: isActive ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(g['icon']!, style: const TextStyle(fontSize: 20)),
                        const SizedBox(height: 4),
                        Text(
                          g['label']!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isActive
                                ? AppColors.accent
                                : AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DISTANCE MAXIMALE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                _distance >= 50 ? '50+ km' : '${_distance.round()} km',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.border,
              thumbColor: AppColors.accent,
              overlayColor: AppColors.accent.withOpacity(0.2),
              trackHeight: 4,
            ),
            child: Slider(
              value: _distance,
              min: 1,
              max: 50,
              divisions: 49,
              onChanged: (v) => setState(() => _distance = v),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _apply,
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                gradient: AppColors.gradientPink,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'Appliquer les filtres',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
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

// ─── GRILLE UTILISATEURS ─────────────────────────────────────────
// ✅ Façon Grindr : au-delà de `unlockedProfileCount` (HomeController),
// les profils sont visibles (silhouette générique, pas la vraie
// photo) mais un tap dessus ouvre le paywall Premium au lieu de
// naviguer. Une bannière animée sépare les deux zones.

class _UsersGridScrollable extends GetView<HomeController> {
  final ScrollController scrollCtrl;
  const _UsersGridScrollable({required this.scrollCtrl});

  bool get _isPremium => Get.isRegistered<ControleurProfil>()
      ? Get.find<ControleurProfil>().isPremium.value
      : false;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoadingUsers.value) return _buildShimmer();
      final users = controller.filteredUsers;
      if (users.isEmpty) return _buildEmpty();

      final isPremium = _isPremium;
      // ✅ Lire trialActiveUntil.value ici (même indirectement, via
      // unlockedProfileCount) permet à Obx() de réagir automatiquement
      // dès que l'essai gratuit démarre.
      final unlockedCount = controller.unlockedProfileCount;
      final hasLockedSection = !isPremium && users.length > unlockedCount;

      final unlockedUsers =
          hasLockedSection ? users.sublist(0, unlockedCount) : users;
      final lockedUsers =
          hasLockedSection ? users.sublist(unlockedCount) : <UserModel>[];

      return RefreshIndicator(
        onRefresh: controller.loadProfiles,
        color: AppColors.accent,
        child: CustomScrollView(
          controller: scrollCtrl,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, hasLockedSection ? 0 : 100),
              sliver: _buildGridSliver(
                  users: unlockedUsers, context: context, locked: false),
            ),
            if (hasLockedSection) ...[
              SliverToBoxAdapter(
                child: _PremiumUnlockBanner(
                  hiddenCount: lockedUsers.length,
                  sampleName: lockedUsers.first.name,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 100),
                sliver: _buildGridSliver(
                    users: lockedUsers, context: context, locked: true),
              ),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildGridSliver({
    required List<UserModel> users,
    required BuildContext context,
    required bool locked,
  }) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.75,
      ),
      delegate: SliverChildBuilderDelegate(
        (_, i) {
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
              locked: locked,
              onTap: () {
                if (locked) {
                  showProfileLimitPaywall(context);
                  return;
                }
                controller.openProfile(user);
              },
            );
          });
        },
        childCount: users.length,
      ),
    );
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
              style: TextStyle(
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

// ─── BANNIÈRE HORIZONTALE "DÉBLOQUER PLUS DE PROFILS" ────────────
// ✅ Badge "🔥" avec pulsation légère pour attirer l'œil dans une
// grille de photos, et message personnalisé avec le prénom du
// premier profil verrouillé.

class _PremiumUnlockBanner extends StatefulWidget {
  final int hiddenCount;
  final String sampleName;
  const _PremiumUnlockBanner(
      {required this.hiddenCount, required this.sampleName});

  @override
  State<_PremiumUnlockBanner> createState() => _PremiumUnlockBannerState();
}

class _PremiumUnlockBannerState extends State<_PremiumUnlockBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.hiddenCount == 1
        ? '${widget.sampleName} t\'attend'
        : '${widget.sampleName} et ${widget.hiddenCount - 1} autre${widget.hiddenCount - 1 > 1 ? 's' : ''} à découvrir';

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: GestureDetector(
        onTap: () => showProfileLimitPaywall(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: AppColors.gradientPink,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: AppColors.accent.withOpacity(0.35), blurRadius: 14),
            ],
          ),
          child: Row(
            children: [
              ScaleTransition(
                scale: Tween(begin: 0.9, end: 1.15).animate(CurvedAnimation(
                    parent: _pulseCtrl, curve: Curves.easeInOut)),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle),
                  child: const Center(
                      child: Text('🔥', style: TextStyle(fontSize: 20))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    const Text('Passe Premium pour tous les débloquer',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── PAYWALL — bottom sheet quand un profil verrouillé est tapé ──
// ✅ Propose l'essai gratuit de 30 minutes en premier (une seule fois par
// appareil), avec l'offre Premium en option secondaire. Affiche
// l'échéance de "l'offre de lancement" pour créer de l'urgence.

void showProfileLimitPaywall(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ProfileLimitPaywallSheet(),
  );
}

class _ProfileLimitPaywallSheet extends StatelessWidget {
  const _ProfileLimitPaywallSheet();

  String _formatCountdown(Duration d) {
    if (d.isNegative) return '0h 00min';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}min';
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<HomeController>();
    final canTrial = !controller.hasUsedTrial && !controller.hasActiveTrial;
    final remaining = controller.offerDeadline.difference(DateTime.now());

    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 28, 24, 32 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2))),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                  gradient: AppColors.gradientPink, shape: BoxShape.circle),
              child: const Icon(Icons.workspace_premium_rounded,
                  color: Colors.white, size: 30),
            ),
            const SizedBox(height: 16),
            Text('Débloque tous les profils',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Passe Premium pour voir jusqu\'à 600 profils au lieu de 15.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),

            // ── Bandeau d'urgence "offre de lancement" ──────────────
            if (!remaining.isNegative) ...[
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined,
                        size: 14, color: Colors.orange),
                    const SizedBox(width: 6),
                    Text(
                        'Offre de lancement — encore ${_formatCountdown(remaining)}',
                        style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── CTA principal : essai gratuit si disponible ─────────
            if (canTrial)
              GestureDetector(
                onTap: () async {
                  await controller.startFreeTrial();
                  if (context.mounted) {
                    Get.back();
                    Get.snackbar(
                      '🎉 Essai activé',
                      'Tu profites de Premium gratuitement pendant 30 minutes',
                      snackPosition: SnackPosition.TOP,
                      backgroundColor: AppColors.surface,
                      colorText: Colors.white,
                      duration: const Duration(seconds: 3),
                    );
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                      gradient: AppColors.gradientPink,
                      borderRadius: BorderRadius.circular(16)),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Essayer gratuitement 30 minutes',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                      SizedBox(height: 2),
                      Text('Sans engagement, une seule fois',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            if (canTrial) const SizedBox(height: 10),

            // ── CTA secondaire (ou principal si essai déjà utilisé) ─
            GestureDetector(
              onTap: () {
                Get.back();
                Get.toNamed(AppRoutes.paywall);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: canTrial ? AppColors.surface2 : null,
                  gradient: canTrial ? null : AppColors.gradientPink,
                  borderRadius: BorderRadius.circular(16),
                  border: canTrial ? Border.all(color: AppColors.border) : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Passer Premium',
                        style: TextStyle(
                            color:
                                canTrial ? AppColors.textPrimary : Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                        (Get.isRegistered<RevenueCatService>()
                                ? Get.find<RevenueCatService>()
                                    .libellePrixCourant
                                : null) ??
                            'Voir les offres',
                        style: TextStyle(
                            color: canTrial
                                ? AppColors.textMuted
                                : Colors.white.withOpacity(0.85),
                            fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Get.back(),
              child: Text('Plus tard',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
          ],
        ),
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
  final bool locked;

  const _UserCard({
    required this.user,
    required this.onTap,
    this.unreadCount = 0,
    this.hasActiveStory = false,
    this.storyIsSeen = false,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasUnread = unreadCount > 0 && !locked;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: hasUnread
              ? Border.all(color: const Color(0xFFFFD700), width: 2)
              : null,
          boxShadow: hasUnread
              ? [
                  BoxShadow(
                      color: const Color(0xFFFFD700).withOpacity(0.3),
                      blurRadius: 8)
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Photo : vraie photo floutée si verrouillé ──────
              // (montrer le vrai visage flouté donne plus envie
              // qu'un pictogramme générique — le flou empêche
              // seulement de distinguer les traits précis)
              locked
                  ? _LockedBlurredPhoto(
                      photoUrl: user.photoUrl, name: user.name)
                  : (user.photoUrl != null && user.photoUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: user.photoUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              _GradientAvatar(name: user.name),
                          errorWidget: (_, __, ___) =>
                              _GradientAvatar(name: user.name),
                        )
                      : _GradientAvatar(name: user.name)),

              // ── Gradient bas ───────────────────────────────
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(locked ? 0.5 : 0.8)
                      ],
                      stops: const [0.5, 1.0],
                    ),
                  ),
                ),
              ),

              if (!locked) ...[
                // ── Nom + distance ─────────────────────────────
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          user.showBirthdate
                              ? '${user.name}, ${user.age}'
                              : user.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis),
                      if (user.distanceMeters != null && user.showDistance)
                        Text(HomeController.formatDistance(user.distanceMeters),
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 9)),
                    ],
                  ),
                ),

                // ── Dot en ligne ─────────────────────────────────
                if (user.isOnline)
                  Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: Colors.green, shape: BoxShape.circle))),

                // ── Badge Boost ⚡ ───────────────────────────────
                if (user.estBooste)
                  Positioned(
                    top: hasUnread ? 30 : 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFFA500)]),
                      ),
                      child: const Icon(Icons.bolt_rounded,
                          size: 12, color: Colors.white),
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

              // ── Verrou Premium avec effet doré scintillant ────
              if (locked)
                Positioned.fill(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Shimmer.fromColors(
                          baseColor: Colors.amber.shade200,
                          highlightColor: Colors.white,
                          period: const Duration(milliseconds: 1400),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                                color: Colors.amber, shape: BoxShape.circle),
                            child: const Icon(Icons.lock_rounded,
                                color: Colors.white, size: 18),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text('Premium',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ✅ Vraie photo floutée pour les profils verrouillés — le flou
// empêche de distinguer les traits précis mais laisse deviner un
// visage, ce qui donne davantage envie de débloquer qu'un
// pictogramme générique.
class _LockedBlurredPhoto extends StatelessWidget {
  final String? photoUrl;
  final String name;
  const _LockedBlurredPhoto({required this.photoUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
      child: hasPhoto
          ? CachedNetworkImage(
              imageUrl: photoUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => _GradientAvatar(name: name),
              errorWidget: (_, __, ___) => _GradientAvatar(name: name),
            )
          : _GradientAvatar(name: name),
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
  const _Chip({
    super.key,
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? Colors.transparent : AppColors.surface2,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
    );
  }
}
