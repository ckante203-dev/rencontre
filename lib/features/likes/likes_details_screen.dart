import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/shared/models/user_model.dart';

/// Affiche la liste complète de "qui m'a vu" ou "qui m'a liké",
/// réservée aux utilisateurs premium (la vérification premium est
/// faite en amont, dans LikesInsightsScreen, avant la navigation ici).
///
/// arguments attendu : 'viewers' ou 'likers'
class LikesDetailsScreen extends StatefulWidget {
  const LikesDetailsScreen({super.key});

  @override
  State<LikesDetailsScreen> createState() => _LikesDetailsScreenState();
}

class _LikesDetailsScreenState extends State<LikesDetailsScreen> {
  late final String _type; // 'viewers' | 'likers'
  List<Map<String, dynamic>> _people = [];
  bool _loading = true;

  int _calcAge(dynamic birthdate) {
    if (birthdate == null) return 18;
    try {
      final birth = DateTime.parse(birthdate.toString());
      final now = DateTime.now();
      int age = now.year - birth.year;
      if (now.month < birth.month ||
          (now.month == birth.month && now.day < birth.day)) {
        age--;
      }
      return age < 0 ? 18 : age;
    } catch (_) {
      return 18;
    }
  }

  @override
  void initState() {
    super.initState();
    _type = (Get.arguments as String?) ?? 'likers';
    _load();
  }

  bool get _isViewers => _type == 'viewers';

  Future<void> _load() async {
    setState(() => _loading = true);
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) {
      setState(() {
        _people = [];
        _loading = false;
      });
      return;
    }
    try {
      // ── 1. Liste (id, nom, photo, date de naissance, en ligne, date) ──
      // Servie par une RPC réservée aux Premium (vérifiée côté serveur).
      final rows = await _chargerViaRpc() ?? await _chargerEnDirect(myId);

      if (rows.isEmpty) {
        if (mounted)
          setState(() {
            _people = [];
            _loading = false;
          });
        return;
      }

      // ── 2. Exclut les profils bloqués ─────────────────────────────
      final myData = await Supabase.instance.client
          .from('profiles')
          .select('blocked_users')
          .eq('id', myId)
          .maybeSingle();
      final blocked = List<String>.from(myData?['blocked_users'] ?? []);

      if (mounted) {
        setState(() {
          _people = rows
              .map((p) => {
                    'id': p['id'] as String,
                    'name': p['name'] ?? 'Utilisateur',
                    'photo_url': p['photo_url'],
                    'age': _calcAge(p['birthdate']),
                    'is_online': p['is_online'] ?? false,
                    'created_at': p['created_at'],
                  })
              .where((p) => !blocked.contains(p['id']))
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('LikesDetailsScreen _load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Appelle la RPC `qui_m_a_vu` / `qui_m_a_like` (Premium vérifié côté
  /// serveur). Renvoie null si la RPC n'existe pas encore en base
  /// (migration 20260929000008 pas encore exécutée) → repli en direct.
  /// Si le serveur refuse (non Premium, 42501) → liste vide.
  Future<List<Map<String, dynamic>>?> _chargerViaRpc() async {
    try {
      final res = await Supabase.instance.client.rpc(
        _isViewers ? 'qui_m_a_vu' : 'qui_m_a_like',
        params: {'p_limit': 50},
      );
      return List<Map<String, dynamic>>.from(
          (res as List).map((r) => Map<String, dynamic>.from(r as Map)));
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return null;
      if (e.code == '42501') {
        debugPrint('LikesDetailsScreen : accès Premium refusé');
        return [];
      }
      rethrow;
    }
  }

  /// Ancien chargement par requêtes directes (utilisé uniquement tant que
  /// les RPC n'existent pas en base).
  Future<List<Map<String, dynamic>>> _chargerEnDirect(String myId) async {
    final rows = _isViewers
        ? await Supabase.instance.client
            .from('profile_views')
            .select('viewer_id, created_at')
            .eq('viewed_id', myId)
            .order('created_at', ascending: false)
            .limit(50)
        : await Supabase.instance.client
            .from('likes')
            .select('from_user_id, created_at')
            .eq('to_user_id', myId)
            .order('created_at', ascending: false)
            .limit(50);

    final list = rows as List;
    if (list.isEmpty) return [];

    final idKey = _isViewers ? 'viewer_id' : 'from_user_id';
    final ids = list.map((r) => r[idKey] as String).toList();

    final profiles = await Supabase.instance.client
        .from('profiles')
        .select('id, name, photo_url, birthdate, is_online')
        .inFilter('id', ids);

    final profileMap = {
      for (final p in (profiles as List)) p['id'] as String: p
    };

    return list.map((r) {
      final id = r[idKey] as String;
      final p = profileMap[id];
      return <String, dynamic>{
        'id': id,
        'name': p?['name'],
        'photo_url': p?['photo_url'],
        'birthdate': p?['birthdate'],
        'is_online': p?['is_online'],
        'created_at': r['created_at'],
      };
    }).toList();
  }

  void _ouvrirProfil(Map<String, dynamic> p) {
    final user = UserModel(
      id: p['id'] as String,
      name: p['name'] as String,
      age: p['age'] as int? ?? 18,
      photoUrl: p['photo_url'] as String?,
      isOnline: p['is_online'] as bool? ?? false,
    );
    Get.toNamed('/profile/view', arguments: user);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text(
          _isViewers ? 'Qui m\'a vu' : 'Qui m\'a liké',
          style: TextStyle(
            fontFamily: 'Syne',
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : _people.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isViewers
                            ? Icons.remove_red_eye_outlined
                            : Icons.favorite_border_rounded,
                        size: 56,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isViewers
                            ? 'Personne n\'a encore vu ton profil'
                            : 'Personne n\'a encore liké ton profil',
                        style:
                            TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.accent,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _people.length,
                    itemBuilder: (_, i) {
                      final p = _people[i];
                      final name = p['name'] as String;
                      final photo = p['photo_url'] as String?;
                      final age = p['age'] as int;
                      final isOnline = p['is_online'] as bool;

                      return ListTile(
                        onTap: () => _ouvrirProfil(p),
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
                        title: Text('$name, $age',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        subtitle: Text(isOnline ? 'En ligne' : 'Hors ligne',
                            style: TextStyle(
                                fontSize: 12,
                                color: isOnline
                                    ? AppColors.online
                                    : AppColors.textMuted)),
                        trailing: Icon(Icons.chevron_right_rounded,
                            color: AppColors.textMuted),
                      );
                    },
                  ),
                ),
    );
  }
}
