import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
import 'package:rencontre/core/utils/app_routes.dart';
import 'package:rencontre/features/home/view/main_navigation.dart';
import 'package:rencontre/shared/models/story_model.dart';
import 'package:rencontre/features/home/view/story_screen.dart';
import 'package:rencontre/shared/models/user_model.dart';

class EcranProfil extends StatelessWidget {
  const EcranProfil({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<ControleurProfil>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Obx(() {
        if (ctrl.isLoading.value) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.accent));
        }
        return SingleChildScrollView(
          child: Column(
            children: [
              _GrandePhoto(ctrl: ctrl),
              const SizedBox(height: 16),
              _NomStatut(ctrl: ctrl),
              const SizedBox(height: 16),
              _Stats(ctrl: ctrl),
              const SizedBox(height: 20),
              _BoutonsLigne(ctrl: ctrl),
              const SizedBox(height: 28),
              // ✅ Section "Qui m'a liké"
              const _SectionLikes(),
              const SizedBox(height: 28),
              _MesStories(ctrl: ctrl),
              const SizedBox(height: 40),
            ],
          ),
        );
      }),
    );
  }
}

// ─── GRANDE PHOTO ────────────────────────────────────────────────

class _GrandePhoto extends StatelessWidget {
  final ControleurProfil ctrl;
  const _GrandePhoto({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.48;
    return Obx(() {
      final photo = ctrl.monProfil.value?.photoUrl;
      return SizedBox(
        height: h,
        width: double.infinity,
        child: Stack(
          children: [
            Positioned.fill(
              child: photo != null && photo.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photo,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          _PlaceholderAvatar(ctrl: ctrl),
                    )
                  : _PlaceholderAvatar(ctrl: ctrl),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      AppColors.bg.withOpacity(0.3),
                      AppColors.bg.withOpacity(0.95),
                    ],
                    stops: const [0.4, 0.7, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              child: _IconBtn(
                icon: Icons.logout_rounded,
                onTap: ctrl.deconnexion,
                color: const Color(0xFFFF3CAC),
              ),
            ),
            Positioned(
              bottom: 14,
              right: 16,
              child: Obx(() => ctrl.isUploadingPhoto.value
                  ? Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      ),
                    )
                  : _IconBtn(
                      icon: Icons.camera_alt_rounded,
                      onTap: ctrl.changerPhoto,
                    )),
            ),
          ],
        ),
      );
    });
  }
}

class _PlaceholderAvatar extends StatelessWidget {
  final ControleurProfil ctrl;
  const _PlaceholderAvatar({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    final name = ctrl.monProfil.value?.name ?? '';
    return Container(
      color: AppColors.surface2,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
              fontSize: 80, fontWeight: FontWeight.w900, color: Colors.white24),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  const _IconBtn({required this.icon, required this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Icon(icon, size: 20, color: color ?? Colors.white),
      ),
    );
  }
}

// ─── NOM & STATUT ────────────────────────────────────────────────

class _NomStatut extends StatelessWidget {
  final ControleurProfil ctrl;
  const _NomStatut({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final p = ctrl.monProfil.value;
      if (p == null) return const SizedBox();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(children: [
          Text('${p.name}, ${p.age}',
              style: const TextStyle(
                  fontFamily: 'Syne',
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: p.isOnline ? AppColors.online : AppColors.textMuted,
                    shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(p.isOnline ? 'En ligne' : 'Hors ligne',
                style: TextStyle(
                    fontSize: 13,
                    color:
                        p.isOnline ? AppColors.online : AppColors.textMuted)),
          ]),
          if (p.corpsMesures.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(p.corpsMesures,
                style:
                    const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ]),
      );
    });
  }
}

// ─── STATS ───────────────────────────────────────────────────────

class _Stats extends StatelessWidget {
  final ControleurProfil ctrl;
  const _Stats({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final p = ctrl.monProfil.value;
      if (p == null) return const SizedBox();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border)),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _StatItem(value: '${p.followersCount}', label: 'Abonnés'),
            Container(width: 1, height: 32, color: AppColors.border),
            _StatItem(value: '${p.followingCount}', label: 'Abonnements'),
            Container(width: 1, height: 32, color: AppColors.border),
            _StatItem(value: '${p.matchesCount}', label: 'Matchs'),
          ]),
        ),
      );
    });
  }
}

class _StatItem extends StatelessWidget {
  final String value, label;
  const _StatItem({required this.value, required this.label});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value,
          style: const TextStyle(
              fontFamily: 'Syne',
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary)),
      const SizedBox(height: 2),
      Text(label,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
    ]);
  }
}

// ─── BOUTONS LIGNE ───────────────────────────────────────────────

class _BoutonsLigne extends StatelessWidget {
  final ControleurProfil ctrl;
  const _BoutonsLigne({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: () => Get.toNamed(AppRoutes.profilEdit),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border, width: 1.5),
              ),
              child: const Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.edit_rounded,
                    color: AppColors.textPrimary, size: 22),
                SizedBox(height: 4),
                Text('Modifier',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () => Get.toNamed(AppRoutes.profilSettings),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.settings_rounded,
                    color: AppColors.textPrimary, size: 22),
                SizedBox(height: 4),
                Text('Paramètres',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ✅ SECTION QUI M'A LIKÉ
// ═══════════════════════════════════════════════════════════════════

class _SectionLikes extends StatefulWidget {
  const _SectionLikes();

  @override
  State<_SectionLikes> createState() => _SectionLikesState();
}

class _SectionLikesState extends State<_SectionLikes> {
  List<Map<String, dynamic>> _likers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      // Récupère les IDs qui ont liké
      final likes = await Supabase.instance.client
          .from('likes')
          .select('from_user_id, created_at')
          .eq('to_user_id', myId)
          .order('created_at', ascending: false)
          .limit(20);

      if ((likes as List).isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final ids = likes.map((r) => r['from_user_id'] as String).toList();

      // Récupère les profils correspondants
      final profiles = await Supabase.instance.client
          .from('profiles')
          .select('id, name, photo_url, age, is_online')
          .inFilter('id', ids);

      final profileMap = {
        for (final p in (profiles as List)) p['id'] as String: p
      };

      if (mounted) {
        setState(() {
          _likers = likes.map((r) {
            final id = r['from_user_id'] as String;
            final p = profileMap[id];
            return {
              'id': id,
              'name': p?['name'] ?? 'Utilisateur',
              'photo_url': p?['photo_url'],
              'age': p?['age'] ?? 0,
              'is_online': p?['is_online'] ?? false,
              'created_at': r['created_at'],
            };
          }).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête
          Row(
            children: [
              ShaderMask(
                shaderCallback: (b) => AppColors.gradientPink.createShader(b),
                child: const Text('❤️ Qui m\'a liké',
                    style: TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
              const Spacer(),
              if (_likers.isNotEmpty)
                GestureDetector(
                  onTap: () => _voirTout(context),
                  child: const Text('Voir tout',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Contenu
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                    color: AppColors.accent, strokeWidth: 2),
              ),
            )
          else if (_likers.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border)),
              child: const Column(children: [
                Icon(Icons.favorite_border_rounded,
                    size: 32, color: AppColors.textMuted),
                SizedBox(height: 8),
                Text('Personne n\'a encore liké ton profil',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ]),
            )
          else
            SizedBox(
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _likers.length,
                itemBuilder: (_, i) => _LikerAvatar(
                  liker: _likers[i],
                  onTap: () => _ouvrirProfil(_likers[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _ouvrirProfil(Map<String, dynamic> liker) {
    final user = UserModel(
      id: liker['id'] as String,
      name: liker['name'] as String,
      age: liker['age'] as int? ?? 18,
      photoUrl: liker['photo_url'] as String?,
      isOnline: liker['is_online'] as bool? ?? false,
    );
    Get.toNamed('/profile/view', arguments: user);
  }

  void _voirTout(BuildContext context) {
    Get.bottomSheet(
      _LikersBottomSheet(likers: _likers, onTap: _ouvrirProfil),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }
}

class _LikerAvatar extends StatelessWidget {
  final Map<String, dynamic> liker;
  final VoidCallback onTap;
  const _LikerAvatar({required this.liker, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = liker['name'] as String? ?? '';
    final photo = liker['photo_url'] as String?;
    final isOnline = liker['is_online'] as bool? ?? false;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        child: Column(children: [
          Stack(
            children: [
              // Avatar
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accent, width: 2),
                ),
                child: ClipOval(
                  child: photo != null && photo.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: photo,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _placeholder(name))
                      : _placeholder(name),
                ),
              ),
              // Badge en ligne
              if (isOnline)
                Positioned(
                  bottom: 1,
                  right: 1,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                        color: AppColors.online,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.bg, width: 2)),
                  ),
                ),
              // Coeur
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [AppColors.accent, AppColors.accent2]),
                      shape: BoxShape.circle),
                  child:
                      const Icon(Icons.favorite, size: 10, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: 58,
            child: Text(
              name.split(' ').first,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _placeholder(String name) => Container(
        color: AppColors.surface2,
        child: Center(
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white54),
          ),
        ),
      );
}

// ─── BOTTOM SHEET LISTE COMPLÈTE ─────────────────────────────────

class _LikersBottomSheet extends StatelessWidget {
  final List<Map<String, dynamic>> likers;
  final void Function(Map<String, dynamic>) onTap;
  const _LikersBottomSheet({required this.likers, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Row(children: [
            ShaderMask(
              shaderCallback: (b) => AppColors.gradientPink.createShader(b),
              child: Text('${likers.length} personnes t\'ont liké',
                  style: const TextStyle(
                      fontFamily: 'Syne',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: likers.length,
            itemBuilder: (_, i) {
              final l = likers[i];
              final name = l['name'] as String? ?? '';
              final photo = l['photo_url'] as String?;
              final age = l['age'] as int? ?? 0;
              final isOnline = l['is_online'] as bool? ?? false;
              return ListTile(
                onTap: () {
                  Get.back();
                  onTap(l);
                },
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                leading: Stack(
                  children: [
                    ClipOval(
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: photo != null && photo.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: photo, fit: BoxFit.cover)
                            : Container(
                                color: AppColors.surface2,
                                child: Center(
                                    child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white54),
                                ))),
                      ),
                    ),
                    if (isOnline)
                      Positioned(
                        bottom: 1,
                        right: 1,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                              color: AppColors.online,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: AppColors.bg, width: 2)),
                        ),
                      ),
                  ],
                ),
                title: Text('$name, $age',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                subtitle: Text(isOnline ? 'En ligne' : 'Hors ligne',
                    style: TextStyle(
                        fontSize: 12,
                        color:
                            isOnline ? AppColors.online : AppColors.textMuted)),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientPink,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Voir',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ─── MES STORIES ─────────────────────────────────────────────────

class _MesStories extends StatefulWidget {
  final ControleurProfil ctrl;
  const _MesStories({required this.ctrl});
  @override
  State<_MesStories> createState() => _MesStoriesState();
}

class _MesStoriesState extends State<_MesStories>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<StoryModel> _epinglees = [];
  List<StoryModel> _archivees = [];
  bool _loading = true;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _charger();
    _ecouterRealtime();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _ecouterRealtime() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    _realtimeChannel = Supabase.instance.client
        .channel('stories_profil_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'stories',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) => _charger(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'stories',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) => _charger(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'stories',
          callback: (_) => _charger(),
        )
        .subscribe();
  }

  Future<void> _charger() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final data = await Supabase.instance.client
          .from('stories')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false);

      final list = (data as List)
          .map((row) => StoryModel(
                id: row['id'],
                userId: row['user_id'],
                userName: '',
                mediaUrl: row['media_url'] ?? '',
                isVideo: row['is_video'] ?? false,
                caption: row['caption'],
                createdAt: DateTime.parse(row['created_at']),
                expiresAt: DateTime.parse(row['expires_at']),
                viewedBy: List<String>.from(row['viewed_by'] ?? []),
                isSeen: false,
                isPinned: row['is_pinned'] ?? false,
              ))
          .toList();

      if (mounted) {
        setState(() {
          _epinglees = list.where((s) => s.isPinned).toList();
          _archivees = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _togglePin(StoryModel story) async {
    final newVal = !story.isPinned;
    try {
      await Supabase.instance.client
          .from('stories')
          .update({'is_pinned': newVal}).eq('id', story.id);
      if (mounted) {
        setState(() {
          final idx = _archivees.indexWhere((s) => s.id == story.id);
          if (idx >= 0) {
            _archivees[idx] = _archivees[idx].copyWith(isPinned: newVal);
          }
          _epinglees = _archivees.where((s) => s.isPinned).toList();
        });
      }
      Get.snackbar(
        newVal ? '📌 Épinglée sur ton profil' : '📌 Retirée du profil',
        '',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF13131A),
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    } catch (_) {}
  }

  void _ajouterStory() {
    if (Get.isRegistered<NavigationController>()) {
      Get.find<NavigationController>().goTo(0);
    }
    Get.to(() => const AddStoryScreen(), transition: Transition.downToUp)
        ?.then((_) => _charger());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: TabBar(
              controller: _tabCtrl,
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
                Tab(text: 'Publications (${_epinglees.length})'),
                Tab(text: 'Archivées (${_archivees.length})'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(
                    color: AppColors.accent, strokeWidth: 2),
              ),
            )
          else
            SizedBox(
              height: _archivees.isEmpty ? 200 : 420,
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _GrilleStories(
                    stories: _epinglees,
                    onAjouter: _ajouterStory,
                    showAjouter: true,
                    isOwner: true,
                    onTogglePin: _togglePin,
                    emptyMessage: 'Aucune publication',
                    emptySubtitle: 'Maintiens une story\npour l\'épingler ici',
                  ),
                  _GrilleStories(
                    stories: _archivees,
                    showAjouter: false,
                    isOwner: true,
                    onTogglePin: _togglePin,
                    emptyMessage: 'Aucune story',
                    emptySubtitle: 'Tes stories apparaîtront ici',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── GRILLE STORIES ──────────────────────────────────────────────

class _GrilleStories extends StatelessWidget {
  final List<StoryModel> stories;
  final VoidCallback? onAjouter;
  final bool showAjouter;
  final bool isOwner;
  final Future<void> Function(StoryModel)? onTogglePin;
  final String emptyMessage;
  final String emptySubtitle;

  const _GrilleStories({
    required this.stories,
    this.onAjouter,
    required this.showAjouter,
    this.isOwner = false,
    this.onTogglePin,
    this.emptyMessage = 'Aucune publication',
    this.emptySubtitle = '',
  });

  @override
  Widget build(BuildContext context) {
    if (stories.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined,
              size: 48, color: AppColors.textMuted.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text(emptyMessage,
              style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
          if (emptySubtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(emptySubtitle,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
          if (showAjouter) ...[
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onAjouter,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  gradient: AppColors.gradientPink,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Ajouter une story',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ]),
              ),
            ),
          ],
        ],
      );
    }

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: stories.length + (showAjouter ? 1 : 0),
      itemBuilder: (_, i) {
        if (showAjouter && i == stories.length) {
          return GestureDetector(
            onTap: onAjouter,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded, color: AppColors.accent, size: 28),
                    SizedBox(height: 4),
                    Text('Ajouter',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600)),
                  ]),
            ),
          );
        }

        final story = stories[i];

        return GestureDetector(
          onTap: () => _voirStory(context, i),
          onLongPress: isOwner && onTogglePin != null
              ? () => _showPinMenu(context, story)
              : null,
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
                              color: Colors.white38, size: 24)),
                    )
                  : Container(
                      color: AppColors.surface2,
                      child: const Icon(Icons.photo_rounded,
                          color: Colors.white38, size: 24)),
              if (story.isVideo)
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4)),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 12),
                  ),
                ),
              if (story.isExpired)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.45),
                    child: const Center(
                      child: Icon(Icons.history_rounded,
                          color: Colors.white54, size: 22),
                    ),
                  ),
                ),
              if (story.isPinned)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                        gradient: AppColors.gradientPink,
                        shape: BoxShape.circle),
                    child: const Icon(Icons.push_pin_rounded,
                        color: Colors.white, size: 11),
                  ),
                ),
              if (isOwner && story.viewedBy.isNotEmpty)
                Positioned(
                  bottom: 4,
                  right: story.isPinned ? 28 : 6,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.remove_red_eye_rounded,
                        color: Colors.white70, size: 10),
                    const SizedBox(width: 2),
                    Text('${story.viewedBy.length}',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 4)
                            ])),
                  ]),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showPinMenu(BuildContext context, StoryModel story) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: const BoxDecoration(
          color: Color(0xFF11111C),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFF252538),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: story.mediaUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: story.mediaUrl,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover)
                : Container(width: 80, height: 80, color: AppColors.surface2),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () {
              Get.back();
              onTogglePin?.call(story);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: story.isPinned
                    ? Colors.red.withOpacity(0.1)
                    : AppColors.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: story.isPinned
                        ? Colors.red.withOpacity(0.3)
                        : AppColors.accent.withOpacity(0.3)),
              ),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(
                  story.isPinned
                      ? Icons.push_pin_outlined
                      : Icons.push_pin_rounded,
                  color: story.isPinned ? Colors.red : AppColors.accent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  story.isPinned
                      ? 'Retirer des publications'
                      : 'Épingler sur mon profil',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: story.isPinned ? Colors.red : AppColors.accent),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Get.back(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: const Text('Annuler',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }

  void _voirStory(BuildContext context, int index) {
    Get.to(
      () => StoryViewerScreen(stories: stories, initialIndex: index),
      transition: Transition.fadeIn,
    );
  }
}
