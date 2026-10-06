import 'package:flutter/material.dart';
import 'package:rencontre/core/theme/app_palette.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:rencontre/features/amis/ecran_amis.dart';
import 'package:rencontre/features/profil/vue/carte_dispo.dart';
import 'package:rencontre/features/album/ecran_album_prive.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:rencontre/features/home/view/story_screen.dart';
import 'package:rencontre/features/home/controller/home_controller.dart'; // ✅ AJOUTÉ — nécessaire pour HomeController
import 'package:rencontre/features/likes/like_widgets.dart' show LikeButton;
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/shared/models/story_model.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';

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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _precharger(_initialIndex));
  }

  /// Photos des profils voisins chargées à l'avance : le balayage vers
  /// le profil suivant / précédent est instantané.
  void _precharger(int i) {
    if (!mounted) return;
    for (final j in [i + 1, i - 1, i + 2]) {
      if (j < 0 || j >= _profiles.length) continue;
      final p = _profiles[j];
      for (final url in [p.photoUrl, ...p.photoUrls.take(1)]) {
        if (url != null && url.isNotEmpty) {
          precacheImage(CachedNetworkImageProvider(url), context)
              .catchError((_) {});
        }
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_profiles.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: const Center(
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
      onPageChanged: _precharger,
      itemCount: _profiles.length,
      itemBuilder: (context, index) {
        return _ProfilDetailContent(
          key: ValueKey(_profiles[index].id),
          user: _profiles[index],
          allProfiles: _profiles,
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
  final List<UserModel> allProfiles;
  const _ProfilDetailContent({
    super.key,
    required this.user,
    required this.allProfiles,
  });

  @override
  State<_ProfilDetailContent> createState() =>
      _ProfilDetailContentState(); // ✅ AJOUTÉ — manquait, obligatoire pour un StatefulWidget
}

class _ProfilDetailContentState extends State<_ProfilDetailContent> {
  late UserModel user;
  bool _isLoadingMsg = false;
  StoryModel? _activeStory;
  bool _loadingStory = true;
  int _currentPhotoIndex = 0;

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
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    _loadActiveStory();
    _recordProfileView();
  }

  Future<void> _recordProfileView() async {
    try {
      final myUid = Supabase.instance.client.auth.currentUser?.id;
      if (myUid == null || myUid == user.id) return;
      await Supabase.instance.client.from('profile_views').upsert({
        'viewer_id': myUid,
        'viewed_id': user.id,
        'created_at': DateTime.now().toUtc().toIso8601String(),
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
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
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

  void _viewStory() {
    if (_activeStory == null) return;

    if (!Get.isRegistered<HomeController>()) {
      ouvrirStories([_activeStory!]);
      return;
    }

    final homeCtrl = Get.find<HomeController>();
    final combined = <StoryModel>[];
    int startIndex = 0;

    for (final p in widget.allProfiles) {
      final userStories = homeCtrl.storiesForUser(p.id);
      if (userStories.isEmpty) continue;
      if (p.id == user.id) startIndex = combined.length;
      combined.addAll(userStories);
    }

    if (combined.isEmpty) combined.add(_activeStory!);

    ouvrirStories(combined, index: startIndex);
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
          backgroundColor: AppColors.surface,
          colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _isLoadingMsg = false);
    }
  }

  void _showOptions() {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () async {
              Get.back();
              final confirmed = await Get.dialog<bool>(AlertDialog(
                backgroundColor: AppColors.surface,
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
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                actions: [
                  TextButton(
                      onPressed: () => Get.back(result: false),
                      child: Text('Annuler',
                          style: TextStyle(color: AppColors.textMuted))),
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
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.surface2,
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

  /// Aperçu de mon propre profil (depuis « Mon profil » → Aperçu)
  bool get _cEstMoi => user.id == Supabase.instance.client.auth.currentUser?.id;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final photos = _allPhotos;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: size.height * 0.58,
            pinned: true,
            backgroundColor: AppColors.bg,
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
              if (!_cEstMoi)
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
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            const Color(0xCC000000),
                            AppColors.bg,
                          ],
                          stops: const [0.0, 0.5, 0.85, 1.0],
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
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.bg),
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
                    bottom: 18,
                    left: 20,
                    right: 20,
                    child: IgnorePointer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(children: [
                            Flexible(
                              child: Text(
                                  user.showBirthdate && user.age > 0
                                      ? '${user.name}, ${user.age}'
                                      : user.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontFamily: 'Syne',
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: -0.5,
                                      shadows: [
                                        Shadow(
                                            color: Colors.black54,
                                            blurRadius: 8)
                                      ])),
                            ),
                            if (user.isPremium) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.workspace_premium_rounded,
                                  size: 22, color: Color(0xFFFFC233)),
                            ],
                          ]),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              if (user.isOnline)
                                _InfoEntete(
                                    point: AppColors.online, texte: 'En ligne')
                              else if (user.lastSeen != null)
                                _InfoEntete(
                                    texte: 'Vu ${_ilYa(user.lastSeen!)}'),
                              if (user.distanceMeters != null &&
                                  user.showDistance)
                                _InfoEntete(
                                    texte:
                                        '📍 ${HomeController.formatDistance(user.distanceMeters)}'),
                              if (user.isNewMember)
                                const _InfoEntete(texte: '✨ Nouveau'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_cEstMoi)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  Icon(Icons.visibility_rounded,
                      color: AppColors.accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        'Aperçu : voici ton profil tel que les autres le voient',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                  ),
                ]),
              ),
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  children: [
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
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
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
                      if (Get.isRegistered<HomeController>()) ...[
                        Obx(() {
                          final home = Get.find<HomeController>();
                          final fav = home.estFavori(user.id);
                          return _ActionBtn(
                              icone: fav
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              couleur:
                                  fav ? const Color(0xFFFFC233) : Colors.white,
                              onTap: () async {
                                final r = await home.basculerFavori(user.id);
                                if (r == null) return;
                                Get.snackbar(
                                    r
                                        ? '⭐ Ajouté à tes favoris'
                                        : 'Retiré de tes favoris',
                                    r ? '${user.name} ne le saura pas' : '',
                                    snackPosition: SnackPosition.TOP,
                                    backgroundColor: AppColors.surface,
                                    colorText: Colors.white,
                                    duration: const Duration(seconds: 2));
                              });
                        }),
                        const SizedBox(width: 10),
                      ],
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
        body: _CorpsProfil(user: user),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  PHOTOS D'UN PROFIL : appui à gauche / à droite (façon Tinder)
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
  late int _index = widget.initialIndex;

  @override
  void initState() {
    super.initState();
    _vCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Toutes les photos du profil prêtes avant qu'on les fasse défiler
    for (final url in widget.photos.skip(1)) {
      precacheImage(CachedNetworkImageProvider(url), context)
          .catchError((_) {});
    }
  }

  @override
  void dispose() {
    _vCtrl.dispose();
    super.dispose();
  }

  void _aller(int pas) {
    final n = (_index + pas).clamp(0, widget.photos.length - 1);
    if (n == _index) {
      HapticFeedback.selectionClick(); // déjà la première / dernière
      return;
    }
    _index = n;
    _vCtrl.jumpToPage(n);
    widget.onIndexChanged(n);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Appui à gauche : photo précédente ; à droite : suivante ;
        // au centre : plein écran
        onTapUp: (d) {
          final x = d.localPosition.dx;
          if (widget.photos.length > 1 && x < c.maxWidth * 0.3) {
            _aller(-1);
          } else if (widget.photos.length > 1 && x > c.maxWidth * 0.7) {
            _aller(1);
          } else {
            widget.onTapPhoto();
          }
        },
        child: PageView.builder(
          controller: _vCtrl,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.photos.length,
          itemBuilder: (_, i) => CachedNetworkImage(
            key: ValueKey(widget.photos[i]),
            imageUrl: widget.photos[i],
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (_, __) => _GradientBg(name: widget.name),
            errorWidget: (_, __, ___) => _GradientBg(name: widget.name),
          ),
        ),
      ),
    );
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

  const _CorpsProfil({required this.user});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          if (user.estDispo) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.online.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.online.withOpacity(0.5)),
              ),
              child: Row(children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: AppColors.online, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(user.dispoTexte!,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
                Text(dureeRestanteDispo(user.dispoJusqua!),
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          // ── À propos ──
          if (user.bio != null && user.bio!.isNotEmpty) ...[
            const _SectionTitle('À propos'),
            const SizedBox(height: 8),
            Text(user.bio!,
                style: TextStyle(
                    fontSize: 15, color: AppColors.textPrimary, height: 1.55)),
            const SizedBox(height: 20),
          ],

          // ── Infos ──
          if (_aDesInfos(user)) ...[
            const _SectionTitle('Infos'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (user.lookingFor != null && user.lookingFor!.isNotEmpty)
                  _PhysiqueBadge(
                      icon: '💞',
                      label: 'Cherche : ${_recherche(user.lookingFor!)}'),
                if (user.taille != null)
                  _PhysiqueBadge(icon: '📏', label: '${user.taille} cm'),
                if (user.poids != null)
                  _PhysiqueBadge(icon: '⚖️', label: '${user.poids} kg'),
                if (user.morphologie != null)
                  _PhysiqueBadge(icon: '💪', label: user.morphologie!),
                if (user.lieuRencontre != null)
                  _PhysiqueBadge(
                      icon: '📍',
                      label:
                          'Rencontre : ${user.lieuRencontre!.replaceAll('Domicile', 'Chez moi')}'),
              ],
            ),
            const SizedBox(height: 20),
          ],

          if (user.interests.isNotEmpty) ...[
            const _SectionTitle('Intérêts'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: user.interests
                  .take(3)
                  .map((i) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color:
                                    AppColors.accent.withValues(alpha: 0.5))),
                        child: Text(i,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
          ],

          // ── Amis et album privé (pas sur l'aperçu de mon profil) ──
          if (user.id != Supabase.instance.client.auth.currentUser?.id) ...[
            Center(child: BoutonAmi(userId: user.id)),
            const SizedBox(height: 12),
            BoutonAlbumPrive(ownerId: user.id, nom: user.name),
          ],
        ],
      ),
    );
  }

  static bool _aDesInfos(UserModel u) =>
      (u.lookingFor != null && u.lookingFor!.isNotEmpty) ||
      u.taille != null ||
      u.poids != null ||
      u.morphologie != null ||
      u.lieuRencontre != null;

  static String _recherche(String v) => switch (v) {
        'hommes' => 'des hommes',
        'femmes' => 'des femmes',
        'tout le monde' => 'tout le monde',
        _ => v,
      };
}

/// Petite étiquette de l'en-tête (« ● En ligne », « 📍 3 km »…)
class _InfoEntete extends StatelessWidget {
  final String texte;
  final Color? point;
  const _InfoEntete({required this.texte, this.point});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (point != null) ...[
          Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: point, shape: BoxShape.circle)),
          const SizedBox(width: 5),
        ],
        Text(texte,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
      ]),
    );
  }
}

/// « il y a 5 min », « il y a 3 h », « il y a 2 j »
String _ilYa(DateTime d) {
  final e = DateTime.now().difference(d);
  if (e.inMinutes < 1) return "à l'instant";
  if (e.inMinutes < 60) return 'il y a ${e.inMinutes} min';
  if (e.inHours < 24) return 'il y a ${e.inHours} h';
  if (e.inDays < 7) return 'il y a ${e.inDays} j';
  // Pas plus précis au-delà (discrétion sur l'activité de chacun)
  return "il y a plus d'une semaine";
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

// ─── WIDGETS ─────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icone;
  final Color couleur;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.icone, required this.couleur, required this.onTap});
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
        child: Center(child: Icon(icone, color: couleur, size: 24)),
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
    final colors = degradesAvatar;
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
