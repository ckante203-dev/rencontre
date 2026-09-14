import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/follow/controller/follow_controller.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
import 'package:rencontre/shared/models/user_model.dart';

// ✅ Helper : récupère FollowController s'il est déjà enregistré, sinon
// l'enregistre à la volée. Filet de sécurité au cas où l'enregistrement
// global dans main.dart n'aurait pas encore eu lieu (ex: hot reload,
// ordre d'init différent, etc.) — évite un Get.find qui plante
// silencieusement et laisse la liste vide.
FollowController _getFollowController() {
  return Get.isRegistered<FollowController>()
      ? Get.find<FollowController>()
      : Get.put(FollowController(), permanent: true);
}

class FollowersScreen extends StatefulWidget {
  const FollowersScreen({super.key});

  @override
  State<FollowersScreen> createState() => _FollowersScreenState();
}

class _FollowersScreenState extends State<FollowersScreen> {
  List<Map<String, dynamic>> _profiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final fc = _getFollowController();
      await fc.loadFollowData();
      final ids = fc.followerIds.toList();
      if (ids.isEmpty) {
        setState(() {
          _profiles = [];
          _loading = false;
        });
        return;
      }

      final myUid = Supabase.instance.client.auth.currentUser?.id;
      final myData = myUid != null
          ? await Supabase.instance.client
              .from('profiles')
              .select('blocked_users')
              .eq('id', myUid)
              .maybeSingle()
          : null;
      final blocked = List<String>.from(myData?['blocked_users'] ?? []);

      final data = await Supabase.instance.client
          .from('profiles')
          .select('id, name, photo_url, age, is_online')
          .inFilter('id', ids);

      if (mounted) {
        setState(() {
          _profiles = (data as List)
              .map((r) => Map<String, dynamic>.from(r))
              .where((p) => !blocked.contains(p['id']))
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _bloquer(String userId) async {
    final confirmed = await Get.dialog<bool>(AlertDialog(
      backgroundColor: const Color(0xFF11111C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Bloquer cet utilisateur ?',
          style: TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              color: Colors.white)),
      content: const Text(
          'Il/elle ne pourra plus voir ton profil ni te contacter.',
          style: TextStyle(color: Color(0xFF5A5A78), fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Annuler',
                style: TextStyle(color: Color(0xFF5A5A78)))),
        GestureDetector(
          onTap: () => Get.back(result: true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(12)),
            child: const Text('Bloquer',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    ));
    if (confirmed == true) {
      await ControleurProfil.to.bloquerProfil(userId);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fc = _getFollowController();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text('Abonnés',
            style: TextStyle(
                fontFamily: 'Syne',
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _profiles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline_rounded,
                          size: 56, color: AppColors.textMuted),
                      const SizedBox(height: 12),
                      Text('Personne ne te suit encore',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 13)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.accent,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _profiles.length,
                    itemBuilder: (_, i) {
                      final p = _profiles[i];
                      final id = p['id'] as String;
                      final name = p['name'] ?? 'Utilisateur';
                      final photo = p['photo_url'] as String?;
                      final isOnline = p['is_online'] ?? false;

                      return ListTile(
                        onTap: () {
                          final user = UserModel(
                            id: id,
                            name: name,
                            age: p['age'] ?? 18,
                            photoUrl: photo,
                            isOnline: isOnline,
                          );
                          Get.toNamed('/profile/view', arguments: user);
                        },
                        leading: Stack(children: [
                          ClipOval(
                            child: SizedBox(
                              width: 46,
                              height: 46,
                              child: photo != null && photo.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: photo, fit: BoxFit.cover)
                                  : Container(
                                      color: AppColors.surface2,
                                      child: Center(
                                        child: Text(
                                          name.isNotEmpty
                                              ? name[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    ),
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
                                    border: Border.all(
                                        color: AppColors.bg, width: 2)),
                              ),
                            ),
                        ]),
                        title: Text(name,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Obx(() {
                              final following = fc.isFollowing(id);
                              return GestureDetector(
                                onTap: () => fc.toggleFollow(id),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    gradient: following
                                        ? null
                                        : AppColors.gradientPink,
                                    color: following ? AppColors.surface : null,
                                    borderRadius: BorderRadius.circular(20),
                                    border: following
                                        ? Border.all(color: AppColors.border)
                                        : null,
                                  ),
                                  child: Text(
                                    following ? 'Suivi' : 'Suivre',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: following
                                            ? AppColors.textPrimary
                                            : Colors.white),
                                  ),
                                ),
                              );
                            }),
                            IconButton(
                              icon: Icon(Icons.more_vert_rounded,
                                  color: AppColors.textMuted, size: 20),
                              onPressed: () => _bloquer(id),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
