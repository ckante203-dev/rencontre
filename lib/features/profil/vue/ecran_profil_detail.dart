import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:rencontre/features/home/view/story_screen.dart';
import 'package:rencontre/features/likes/like_widgets.dart' show LikeButton;
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/shared/models/story_model.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
import 'package:rencontre/features/follow/controller/follow_controller.dart';

// ══════════════════════════════════════════════════════════════════
//  WRAPPER — gère le swipe HORIZONTAL entre plusieurs profils.
//  Le swipe VERTICAL (haut/bas) est réservé au défilement des
//  photos d'UN MÊME profil, façon Grindr (voir _VerticalPhotoPager
//  dans _ProfilDetailContent ci-dessous).
//
//  Arguments attendus via Get.arguments :
//    - Map { 'profiles': List<UserModel>, 'initialIndex': int }
//    - ou List<UserModel> (index de départ = 0)
//    - ou UserModel seul (rétro-compatibilité, liste à 1 élément)
// ══════════════════════════════════════════════════════════════════

class EcranProfilDetail extends StatefulWidget {
  const EcranProfilDetail({super.key});

  @override
  State<EcranProfilDetail> createState() => _EcranProfilDetailState();
}

class _EcranProfilDetailState extends State<EcranProfilDetail> {
  late List<UserModel> _profiles;
  late int _initialIndex;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;

    if (args is Map) {
      _profiles = List<UserModel>.from(args['profiles'] as List? ?? const []);
      _initialIndex = (args['initialIndex'] as int?) ?? 0;
    } else if (args is List) {
      _profiles = List<UserModel>.from(args);
      _initialIndex = 0;
    } else if (args is UserModel) {
      _profiles = [args];
      _initialIndex = 0;
    } else {
      _profiles = const [];
      _initialIndex = 0;
    }

    if (_profiles.isNotEmpty) {
      _initialIndex = _initialIndex.clamp(0, _profiles.length - 1);
    }

    _pageController = PageController(initialPage: _initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_profiles.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0D1A),
        body: Center(
          child: Text(
            'Profil introuvable',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.horizontal,
      physics: const PageScrollPhysics(),
      itemCount: _profiles.length,
      itemBuilder: (context, index) {
        return _ProfilDetailContent(
          key: ValueKey(_profiles[index].id),
          user: _profiles[index],
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  CONTENU D'UN PROFIL — ex-EcranProfilDetail, désormais paramétré
//  par `user` (reçu du PageView parent) au lieu de Get.arguments.
// ══════════════════════════════════════════════════════════════════

class _ProfilDetailContent extends StatefulWidget {
  final UserModel user;
  const _ProfilDetailContent({super.key, required this.user});

  @override
  State<_ProfilDetailContent> createState() => _ProfilDetailContentState();
}

class _ProfilDetailContentState extends State<_ProfilDetailContent>
    with SingleTickerProviderStateMixin {
  late UserModel user;
  bool _isLoadingMsg = false;
  StoryModel? _activeStory;
  bool _loadingStory = true;
  List<StoryModel> _stories = [];
  bool _loadingStories = true;
  late TabController _tabCtrl;
  int _currentPhotoIndex = 0;

  List<StoryModel> get _publications =>
      _stories.where((s) => s.isPinned).toList();

  List<String> get _allPhotos {
    final photos = <String>[];
    if (user.photoUrl != null && user.photoUrl!.isNotEmpty) {
      photos.add(user.photoUrl!);
    }
    for (final url in user.photoUrls) {
      if (url.isNotEmpty && !photos.contains(url)) photos.add(url);
    }
    return photos;
  }

  @override
  void initState() {
    super.initState();
    user = widget.user;
    _tabCtrl = TabController(length: 1, vsync: this);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    if (!Get.isRegistered<FollowController>()) {
      Get.put(FollowController(), permanent: true);
    }
    _loadActiveStory();
    _loadStories();
    _recordProfileView();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _recordProfileView() async {
    try {
      final myUid = Supabase.instance.client.auth.currentUser?.id;
      if (myUid == null || myUid == user.id) return;
      await Supabase.instance.client.from('profile_views').upsert({
        'viewer_id': myUid,
        'viewed_id': user.id,
        'created_at': DateTime.now().toIso8601String(),
      }, onConflict: 'viewer_id,viewed_id');
    } catch (e) {
      debugPrint('_recordProfileView error: $e');
    }
  }

  Future<void> _loadActiveStory() async {
    try {
      final data = await Supabase.instance.client
          .from('stories')
          .select('*, profiles(name, photo_url)')
          .eq('user_id', user.id)
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data != null && mounted) {
        final profile = data['profiles'] as Map<String, dynamic>?;
        final viewedBy =
            (data['viewed_by'] as List?)?.map((e) => e.toString()).toList() ??
                [];
        final myUid = Supabase.instance.client.auth.currentUser?.id;
        setState(() {
          _activeStory = StoryModel(
            id: data['id'],
            userId: data['user_id'],
            userName: profile?['name'] ?? user.name,
            userPhotoUrl: profile?['photo_url'] ?? user.photoUrl,
            mediaUrl: data['media_url'],
            isVideo: data['is_video'] ?? false,
            caption: data['caption'],
            createdAt: DateTime.parse(data['created_at']),
            expiresAt: DateTime.parse(data['expires_at']),
            viewedBy: viewedBy,
            isSeen: myUid != null && viewedBy.contains(myUid),
            isPinned: data['is_pinned'] ?? false,
          );
        });
      }
    } catch (e) {
      debugPrint('_loadActiveStory error: $e');
    } finally {
      if (mounted) setState(() => _loadingStory = false);
    }
  }

  Future<void> _loadStories() async {
    try {
      final myUid = Supabase.instance.client.auth.currentUser?.id;
      final data = await Supabase.instance.client
          .from('stories')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
      if (mounted) {
        final list = (data as List).map((row) {
          final viewedBy = List<String>.from(row['viewed_by'] ?? []);
          return StoryModel(
            id: row['id'],
            userId: row['user_id'],
            userName: user.name,
            userPhotoUrl: user.photoUrl,
            mediaUrl: row['media_url'] ?? '',
            isVideo: row['is_video'] ?? false,
            caption: row['caption'],
            createdAt: DateTime.parse(row['created_at']),
            expiresAt: DateTime.parse(row['expires_at']),
            viewedBy: viewedBy,
            isSeen: myUid != null && viewedBy.contains(myUid),
            isPinned: row['is_pinned'] ?? false,
          );
        }).toList();
        setState(() {
          _stories = list;
          _loadingStories = false;
        });
      }
    } catch (e) {
      debugPrint('_loadStories error: $e');
      if (mounted) setState(() => _loadingStories = false);
    }
  }

  void _viewStory() {
    if (_activeStory == null) return;
    Get.to(
      () => StoryViewerScreen(stories: [_activeStory!], initialIndex: 0),
      transition: Transition.fadeIn,
    );
  }

  Future<void> _ouvrirChat() async {
    setState(() => _isLoadingMsg = true);
    try {
      final service = SupabaseService();
      final convId = await service.getOrCreateConversation(user.id);
      final conv = ConversationModel(
        id: convId,
        userId: user.id,
        userName: user.name,
        userPhotoUrl: user.photoUrl,
        isOnline: user.isOnline,
        unreadCount: 0,
      );
      Get.toNamed('/chat/conversation', arguments: conv);
    } catch (_) {
      Get.snackbar('Erreur', "Impossible d'ouvrir la conversation",
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _isLoadingMsg = false);
    }
  }

  String _lastSeenLabel() {
    if (user.isOnline) return '';
    final lastSeen = user.lastSeen;
    if (lastSeen == null) return 'Hors ligne';
    final diff = DateTime.now().difference(lastSeen);
    if (diff.inMinutes < 1) return 'Vu à l\'instant';
    if (diff.inMinutes < 60) return 'Vu il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Vu il y a ${diff.inHours}h';
    if (diff.inDays < 7)
      return 'Vu il y a ${diff.inDays} jour${diff.inDays > 1 ? 's' : ''}';
    return 'Hors ligne';
  }

  void _showOptions() {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        decoration: const BoxDecoration(
            color: Color(0xFF11111C),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFF252538),
                    borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () async {
              Get.back();
              final confirmed = await Get.dialog<bool>(AlertDialog(
                backgroundColor: const Color(0xFF11111C),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: Text('Bloquer ${user.name} ?',
                    style: const TextStyle(
                        fontFamily: 'Syne',
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontSize: 17)),
                content: Text(
                    '${user.name} ne pourra plus voir ton profil ni t\'envoyer des messages.',
                    style: const TextStyle(
                        color: Color(0xFF5A5A78), fontSize: 13)),
                actions: [
                  TextButton(
                      onPressed: () => Get.back(result: false),
                      child: const Text('Annuler',
                          style: TextStyle(color: Color(0xFF5A5A78)))),
                  GestureDetector(
                    onTap: () => Get.back(result: true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 9),
                      decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(12)),
                      child: const Text('Bloquer',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ));
              if (confirmed == true) {
                await ControleurProfil.to.bloquerProfil(user.id);
                Get.back();
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.error.withOpacity(0.25))),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.block_rounded, color: AppColors.error, size: 20),
                const SizedBox(width: 10),
                Text('Bloquer ${user.name}',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.error)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              Get.back();
              _showSignalerSheet();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.withOpacity(0.25))),
              child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.flag_rounded, color: Colors.orange, size: 20),
                    SizedBox(width: 10),
                    Text('Signaler ce profil',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.orange)),
                  ]),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Get.back(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border)),
              child: Center(
                child: Text('Annuler',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted)),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(Get.context!).padding.bottom + 16),
        ]),
      ),
      isScrollControlled: true,
    );
  }

  void _showSignalerSheet() {
    final raisons = [
      {'icon': '🔞', 'label': 'Contenu inapproprié'},
      {'icon': '🤖', 'label': 'Faux profil / Bot'},
      {'icon': '💬', 'label': 'Harcèlement ou spam'},
      {'icon': '⚠️', 'label': 'Comportement dangereux'},
      {'icon': '🔗', 'label': 'Escroquerie / Arnaque'},
      {'icon': '🚩', 'label': 'Autre raison'},
    ];

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        decoration: const BoxDecoration(
            color: Color(0xFF11111C),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFF252538),
                    borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),
          const Text('Pourquoi signaler ce profil ?',
              style: TextStyle(
                  fontFamily: 'Syne',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          const SizedBox(height: 16),
          ...raisons.map((r) => GestureDetector(
                onTap: () {
                  Get.back();
                  ControleurProfil.to.signalerProfil(user.id, r['label']!);
                },
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border)),
                  child: Row(children: [
                    Text(r['icon']!, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 12),
                    Text(r['label']!,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded,
                        color: AppColors.textMuted, size: 18),
                  ]),
                ),
              )),
          SizedBox(height: MediaQuery.of(Get.context!).padding.bottom + 16),
        ]),
      ),
      isScrollControlled: true,
    );
  }

  void _openPhoto(String url) {
    Get.to(
      () => _FullScreenPhoto(url: url),
      transition: Transition.fadeIn,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final photos = _allPhotos;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: size.height * 0.55,
            pinned: true,
            backgroundColor: const Color(0xFF0D0D1A),
            leading: GestureDetector(
              onTap: () => Get.back(),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24)),
                child: const Icon(Icons.arrow_back_ios_rounded,
                    size: 18, color: Colors.white),
              ),
            ),
            actions: [
              GestureDetector(
                onTap: _showOptions,
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24)),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.more_horiz_rounded,
                        size: 20, color: Colors.white),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // ✅ NOUVEAU — swipe VERTICAL (haut/bas) entre les photos
                  // du profil, façon Grindr. Ne rentre pas en conflit avec
                  // le swipe HORIZONTAL entre profils (axes différents).
                  photos.isNotEmpty
                      ? _VerticalPhotoPager(
                          photos: photos,
                          name: user.name,
                          initialIndex: _currentPhotoIndex,
                          onIndexChanged: (i) =>
                              setState(() => _currentPhotoIndex = i),
                          onTapPhoto: () =>
                              _openPhoto(photos[_currentPhotoIndex]),
                        )
                      : _GradientBg(name: user.name),
                  const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Color(0xCC000000),
                            Color(0xFF0D0D1A),
                          ],
                          stops: [0.0, 0.5, 0.85, 1.0],
                        ),
                      ),
                    ),
                  ),
                  if (photos.length > 1)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 54,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            photos.length,
                            (i) => AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              width: i == _currentPhotoIndex ? 20 : 6,
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: i == _currentPhotoIndex
                                    ? Colors.white
                                    : Colors.white38,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (user.isNewMember)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 54,
                      left: 16,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: AppColors.gradientPink,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_rounded,
                                  size: 11, color: Colors.white),
                              SizedBox(width: 4),
                              Text('Nouveau membre',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (!_loadingStory && _activeStory != null)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 52,
                      right: 16,
                      child: GestureDetector(
                        onTap: _viewStory,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: _activeStory!.isSeen
                                    ? null
                                    : LinearGradient(
                                        colors: [
                                            AppColors.accent,
                                            AppColors.accent2,
                                            AppColors.accent3,
                                          ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight),
                                color: _activeStory!.isSeen
                                    ? AppColors.border
                                    : null,
                              ),
                              child: Container(
                                width: 52,
                                height: 52,
                                decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF0D0D1A)),
                                padding: const EdgeInsets.all(2),
                                child: ClipOval(
                                  child: CachedNetworkImage(
                                    imageUrl: _activeStory!.mediaUrl,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                        color: AppColors.surface2,
                                        child: const Icon(
                                            Icons.play_circle_outline_rounded,
                                            color: Colors.white54,
                                            size: 20)),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text(
                                _activeStory!.isSeen ? 'Vue' : 'Story',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: _activeStory!.isSeen
                                        ? Colors.white54
                                        : Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 80,
                    child: IgnorePointer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text('${user.name}, ${user.age}',
                                      style: const TextStyle(
                                          fontFamily: 'Syne',
                                          fontSize: 26,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          letterSpacing: -0.5)),
                                ),
                                if (user.isPremium) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 18,
                                    height: 18,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [
                                          Color(0xFFFFD700),
                                          Color(0xFFFFA500)
                                        ],
                                      ),
                                    ),
                                    child: const Icon(Icons.check_rounded,
                                        size: 12, color: Colors.white),
                                  ),
                                ],
                                if (user.isOnline) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                        color:
                                            AppColors.online.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                            color: AppColors.online
                                                .withOpacity(0.5))),
                                    child: Row(children: [
                                      Icon(Icons.circle,
                                          size: 7, color: AppColors.online),
                                      SizedBox(width: 4),
                                      Text('En ligne',
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.online)),
                                    ]),
                                  ),
                                ],
                              ]),
                          if (!user.isOnline) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              const Icon(Icons.access_time_rounded,
                                  size: 11, color: Colors.white54),
                              const SizedBox(width: 4),
                              Text(_lastSeenLabel(),
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.white54)),
                            ]),
                          ],
                          if (user.distanceMeters != null) ...[
                            const SizedBox(height: 2),
                            Row(children: [
                              const Icon(Icons.location_on_rounded,
                                  size: 12, color: Colors.white54),
                              const SizedBox(width: 3),
                              Text(user.distanceLabel,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.white54)),
                            ]),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (photos.length > 1)
                    Positioned(
                      bottom: 22,
                      right: 16,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(10)),
                          child: Text(
                              '${_currentPhotoIndex + 1}/${photos.length}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  _FollowButton(userId: user.id),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _ouvrirChat,
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                              gradient: AppColors.gradientPink,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                    color: AppColors.accent.withOpacity(0.4),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4))
                              ]),
                          child: Center(
                            child: _isLoadingMsg
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                        Icon(Icons.chat_bubble_rounded,
                                            size: 17, color: Colors.white),
                                        SizedBox(width: 8),
                                        Text('Envoyer un message',
                                            style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white)),
                                      ]),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _ActionBtn(
                        emoji: '📸',
                        onTap: () => Get.snackbar('📸 Snap', 'Bientôt !',
                            snackPosition: SnackPosition.TOP,
                            backgroundColor: const Color(0xFF13131A),
                            colorText: Colors.white)),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 50,
                      height: 50,
                      child: LikeButton(user: user),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
        body: _CorpsProfil(
          user: user,
          publications: _publications,
          loadingStories: _loadingStories,
          tabCtrl: _tabCtrl,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  ✅ NOUVEAU — SWIPE VERTICAL ENTRE LES PHOTOS D'UN PROFIL (Grindr)
// ══════════════════════════════════════════════════════════════════

class _VerticalPhotoPager extends StatefulWidget {
  final List<String> photos;
  final String name;
  final int initialIndex;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback onTapPhoto;

  const _VerticalPhotoPager({
    required this.photos,
    required this.name,
    required this.onIndexChanged,
    required this.onTapPhoto,
    this.initialIndex = 0,
  });

  @override
  State<_VerticalPhotoPager> createState() => _VerticalPhotoPagerState();
}

class _VerticalPhotoPagerState extends State<_VerticalPhotoPager> {
  late final PageController _vCtrl;

  @override
  void initState() {
    super.initState();
    _vCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _vCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTapPhoto,
      child: PageView.builder(
        controller: _vCtrl,
        scrollDirection: Axis.vertical,
        physics: const ClampingScrollPhysics(),
        itemCount: widget.photos.length,
        onPageChanged: widget.onIndexChanged,
        itemBuilder: (_, i) => CachedNetworkImage(
          key: ValueKey(widget.photos[i]),
          imageUrl: widget.photos[i],
          fit: BoxFit.cover,
          placeholder: (_, __) => _GradientBg(name: widget.name),
          errorWidget: (_, __, ___) => _GradientBg(name: widget.name),
        ),
      ),
    );
  }
}

// ─── BOUTON SUIVRE / SUIVI ────────────────────────────────────────

class _FollowButton extends StatelessWidget {
  final String userId;
  const _FollowButton({required this.userId});

  @override
  Widget build(BuildContext context) {
    final myUid = Supabase.instance.client.auth.currentUser?.id;
    if (myUid == null || myUid == userId) return const SizedBox.shrink();

    final ctrl = Get.find<FollowController>();

    return Obx(() {
      final following = ctrl.isFollowing(userId);
      return GestureDetector(
        onTap: () => ctrl.toggleFollow(userId),
        child: Container(
          width: double.infinity,
          height: 44,
          decoration: BoxDecoration(
            gradient: following ? null : AppColors.gradientPink,
            color: following ? AppColors.surface : null,
            borderRadius: BorderRadius.circular(14),
            border: following ? Border.all(color: AppColors.border) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                following
                    ? Icons.check_rounded
                    : Icons.person_add_alt_1_rounded,
                size: 17,
                color: following ? AppColors.textPrimary : Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                following ? 'Suivi' : 'Suivre',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: following ? AppColors.textPrimary : Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

// ─── PHOTO PLEIN ÉCRAN ────────────────────────────────────────────

class _FullScreenPhoto extends StatelessWidget {
  final String url;
  const _FullScreenPhoto({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Get.back()),
      ),
      body: InteractiveViewer(
        child: Center(
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (_, __) =>
                const CircularProgressIndicator(color: Colors.white),
            errorWidget: (_, __, ___) => const Icon(Icons.broken_image_rounded,
                color: Colors.white38, size: 48),
          ),
        ),
      ),
    );
  }
}

// ─── CORPS DU PROFIL ─────────────────────────────────────────────

class _CorpsProfil extends StatelessWidget {
  final UserModel user;
  final List<StoryModel> publications;
  final bool loadingStories;
  final TabController tabCtrl;

  const _CorpsProfil({
    required this.user,
    required this.publications,
    required this.loadingStories,
    required this.tabCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border)),
            child: Row(children: [
              _InfoTile(icon: '🎂', label: 'Âge', value: '${user.age} ans'),
              _InfoTile(
                  icon: '📍',
                  label: 'Distance',
                  value: user.distanceMeters != null
                      ? user.distanceLabel
                      : 'Inconnue'),
              _InfoTile(
                  icon: '🟢',
                  label: 'Statut',
                  value: user.isOnline ? 'En ligne' : 'Hors ligne'),
            ]),
          ),
          const SizedBox(height: 12),
          if (user.taille != null ||
              user.poids != null ||
              user.morphologie != null ||
              user.lieuRencontre != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border)),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (user.taille != null)
                    _PhysiqueBadge(icon: '📏', label: '${user.taille} cm'),
                  if (user.poids != null)
                    _PhysiqueBadge(icon: '⚖️', label: '${user.poids} kg'),
                  if (user.morphologie != null)
                    _PhysiqueBadge(icon: '💪', label: user.morphologie!),
                  if (user.lieuRencontre != null)
                    _PhysiqueBadge(
                        icon: '📍', label: 'Rencontre : ${user.lieuRencontre}'),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (user.bio != null && user.bio!.isNotEmpty) ...[
            const _SectionTitle('✍️ À propos'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border)),
              child: Text(user.bio!,
                  style: TextStyle(
                      fontSize: 14, color: AppColors.textPrimary, height: 1.6)),
            ),
            const SizedBox(height: 16),
          ],
          if (user.interests.isNotEmpty) ...[
            const _SectionTitle('🎯 Intérêts'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: user.interests
                  .map((i) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            gradient: AppColors.gradientPink,
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(i,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: TabBar(
              controller: tabCtrl,
              indicator: BoxDecoration(
                gradient: AppColors.gradientPink,
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textMuted,
              labelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              tabs: [
                Tab(text: 'Publications (${publications.length})'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (loadingStories)
            Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                    color: AppColors.accent, strokeWidth: 2),
              ),
            )
          else
            SizedBox(
              height: publications.isEmpty ? 150 : 400,
              child: TabBarView(
                controller: tabCtrl,
                children: [
                  _GrilleStoriesDetail(stories: publications),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Badge physique ────────────────────────────────────────────────

class _PhysiqueBadge extends StatelessWidget {
  final String icon, label;
  const _PhysiqueBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(icon, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      ]),
    );
  }
}

// ─── GRILLE PUBLICATIONS ─────────────────────────────────────────

class _GrilleStoriesDetail extends StatelessWidget {
  final List<StoryModel> stories;
  const _GrilleStoriesDetail({required this.stories});

  @override
  Widget build(BuildContext context) {
    if (stories.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined,
              size: 36, color: AppColors.textMuted),
          SizedBox(height: 8),
          Text('Aucune publication',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
        ],
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: stories.length,
      itemBuilder: (_, i) {
        final story = stories[i];
        return GestureDetector(
          onTap: () => Get.to(
            () => StoryViewerScreen(stories: stories, initialIndex: i),
            transition: Transition.fadeIn,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              story.mediaUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: story.mediaUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                          color: AppColors.surface2,
                          child: const Icon(Icons.broken_image_rounded,
                              color: Colors.white38, size: 24)))
                  : Container(
                      color: AppColors.surface2,
                      child: const Icon(Icons.photo_rounded,
                          color: Colors.white38, size: 24)),
              if (story.isVideo)
                Positioned(
                    bottom: 6,
                    left: 6,
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4)),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 12))),
              Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                          gradient: AppColors.gradientPink,
                          shape: BoxShape.circle),
                      child: const Icon(Icons.push_pin_rounded,
                          color: Colors.white, size: 10))),
              if (story.isSeen)
                Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                            color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded,
                            color: Colors.white70, size: 10))),
            ],
          ),
        );
      },
    );
  }
}

// ─── WIDGETS ─────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  final String icon, label, value;
  const _InfoTile(
      {required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
            textAlign: TextAlign.center),
        Text(label, style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;
  const _ActionBtn({required this.emoji, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24)),
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(),
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 0.8));
  }
}

class _GradientBg extends StatelessWidget {
  final String name;
  const _GradientBg({required this.name});
  @override
  Widget build(BuildContext context) {
    final colors = [
      [const Color(0xFFFF3CAC), const Color(0xFF7B2FFF)],
      [const Color(0xFF7B2FFF), const Color(0xFF00F5D4)],
      [const Color(0xFFFF6B6B), const Color(0xFFFF3CAC)],
    ];
    final idx = name.isNotEmpty ? name.codeUnitAt(0) % colors.length : 0;
    return Container(
      decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: colors[idx],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight)),
      child: Center(
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  fontSize: 100,
                  fontWeight: FontWeight.w900,
                  color: Colors.white24))),
    );
  }
}
