import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:rencontre/features/home/view/story_screen.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/shared/models/story_model.dart';

class EcranProfilDetail extends StatefulWidget {
  const EcranProfilDetail({super.key});

  @override
  State<EcranProfilDetail> createState() => _EcranProfilDetailState();
}

class _EcranProfilDetailState extends State<EcranProfilDetail> {
  late UserModel user;
  bool _isLoadingMsg = false;

  // Story active de cet utilisateur
  StoryModel? _activeStory;
  bool _loadingStory = true;

  @override
  void initState() {
    super.initState();
    user = Get.arguments as UserModel;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _loadActiveStory();
  }

  // ── Charge la story active la plus récente de ce profil ───────

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
          );
        });
      }
    } catch (e) {
      debugPrint('_loadActiveStory error: $e');
    } finally {
      if (mounted) setState(() => _loadingStory = false);
    }
  }

  // ── Ouvrir la story de ce profil ─────────────────────────────

  void _viewStory() {
    if (_activeStory == null) return;
    Get.to(
      () => StoryViewerScreen(stories: [_activeStory!], initialIndex: 0),
      transition: Transition.fadeIn,
    );
  }

  // ── Ouvrir le chat ────────────────────────────────────────────

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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          // ── SliverAppBar — photo plein écran collapsible ───────
          SliverAppBar(
            expandedHeight: size.height * 0.52,
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
                  // Photo de profil
                  user.photoUrl != null && user.photoUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: user.photoUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _GradientBg(name: user.name),
                          errorWidget: (_, __, ___) =>
                              _GradientBg(name: user.name),
                        )
                      : _GradientBg(name: user.name),

                  // Gradient bas
                  const DecoratedBox(
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

                  // ✅ Vignette story active — en haut à droite de la photo
                  // Visible uniquement si cet user a une story active.
                  // Tap → ouvre le StoryViewer directement.
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
                                    : const LinearGradient(
                                        colors: [
                                          AppColors.accent,
                                          AppColors.accent2,
                                          AppColors.accent3,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                color: _activeStory!.isSeen
                                    ? AppColors.border
                                    : null,
                              ),
                              child: Container(
                                width: 52,
                                height: 52,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF0D0D1A),
                                ),
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
                                          size: 20),
                                    ),
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
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _activeStory!.isSeen ? 'Vue' : 'Story',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: _activeStory!.isSeen
                                      ? Colors.white54
                                      : Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Nom + statut en bas de la photo
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              '${user.name}, ${user.age}',
                              style: const TextStyle(
                                fontFamily: 'Syne',
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                            if (user.isOnline) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                    color: AppColors.online.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color:
                                            AppColors.online.withOpacity(0.5))),
                                child: const Row(children: [
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
                          ],
                        ),
                        if (user.distanceMeters != null)
                          Row(children: [
                            const Icon(Icons.location_on_rounded,
                                size: 12, color: Colors.white54),
                            const SizedBox(width: 3),
                            Text(user.distanceLabel,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.white54)),
                          ]),
                        // ✅ Pill "Story active" sous le nom
                        if (!_loadingStory && _activeStory != null)
                          GestureDetector(
                            onTap: _viewStory,
                            child: Container(
                              margin: const EdgeInsets.only(top: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                gradient: _activeStory!.isSeen
                                    ? null
                                    : AppColors.gradientPink,
                                color: _activeStory!.isSeen
                                    ? Colors.black38
                                    : null,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: _activeStory!.isSeen
                                        ? Colors.white24
                                        : Colors.transparent),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.play_circle_filled_rounded,
                                    size: 13,
                                    color: _activeStory!.isSeen
                                        ? Colors.white54
                                        : Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _activeStory!.isSeen
                                        ? 'Story vue'
                                        : 'Story active',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _activeStory!.isSeen
                                          ? Colors.white54
                                          : Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Boutons action ───────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
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
                                ],
                              ),
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
                      colorText: Colors.white),
                ),
                const SizedBox(width: 10),
                _ActionBtn(
                  emoji: '❤️',
                  onTap: () => Get.snackbar('❤️ Like', 'Bientôt !',
                      snackPosition: SnackPosition.TOP,
                      backgroundColor: const Color(0xFF13131A),
                      colorText: Colors.white),
                ),
              ]),
            ),
          ),
        ],

        // ── Corps : uniquement l'onglet Profil ────────────────
        body: _TabProfil(user: user),
      ),
    );
  }

  void _showOptions() {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
            color: Color(0xFF11111C),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFF252538),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          _OptionItem(
              icon: '🚫',
              label: 'Bloquer ${user.name}',
              color: AppColors.error,
              onTap: () => Get.back()),
          const SizedBox(height: 10),
          _OptionItem(
              icon: '⚠️',
              label: 'Signaler ce profil',
              color: Colors.orange,
              onTap: () => Get.back()),
          const SizedBox(height: 10),
          _OptionItem(
              icon: '❌',
              label: 'Annuler',
              color: AppColors.textMuted,
              onTap: () => Get.back()),
        ]),
      ),
    );
  }
}

// ─── ONGLET PROFIL — style Grindr ─────────────────────────────────

class _TabProfil extends StatelessWidget {
  final UserModel user;
  const _TabProfil({required this.user});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Grille infos rapides (style Grindr) ──────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border)),
            child: Column(children: [
              Row(children: [
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
              if (user.gender != null || user.lookingFor != null) ...[
                const SizedBox(height: 12),
                Row(children: [
                  if (user.gender != null)
                    _InfoTile(
                        icon: user.gender == 'femme' ? '♀️' : '♂️',
                        label: 'Genre',
                        value: user.gender!.capitalize!),
                  if (user.lookingFor != null)
                    _InfoTile(
                        icon: '💞',
                        label: 'Cherche',
                        value: user.lookingFor!.capitalize!),
                  // Remplir la ligne si un seul item
                  if (user.gender != null && user.lookingFor == null)
                    const Expanded(child: SizedBox()),
                  if (user.gender == null && user.lookingFor != null)
                    const Expanded(child: SizedBox()),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 16),

          // ── À propos ─────────────────────────────────────────
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
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.textPrimary, height: 1.6)),
            ),
            const SizedBox(height: 16),
          ],

          // ── Intérêts ─────────────────────────────────────────
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

          // ── Aucune info ───────────────────────────────────────
          if ((user.bio == null || user.bio!.isEmpty) &&
              user.interests.isEmpty) ...[
            const SizedBox(height: 24),
            Center(
              child: Column(children: [
                Icon(Icons.person_outline_rounded,
                    size: 48, color: AppColors.textMuted.withOpacity(0.4)),
                const SizedBox(height: 12),
                const Text('Aucune info sur ce profil',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── WIDGETS COMMUNS ──────────────────────────────────────────────

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
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
            textAlign: TextAlign.center),
        Text(label,
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
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
        style: const TextStyle(
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

class _OptionItem extends StatelessWidget {
  final String icon, label;
  final Color color;
  final VoidCallback onTap;
  const _OptionItem(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
            color: const Color(0xFF191926),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF252538))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }
}
