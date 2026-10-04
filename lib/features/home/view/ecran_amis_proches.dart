import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';

// ─── STORIES « AMIS PROCHES » ─────────────────────────────────────
// Ma liste : seules ces personnes voient mes stories « ⭐ Amis proches »
// (filtré par la base, politique stories_amis_proches). Elles ne savent
// pas qu'elles sont dans la liste.

/// Nombre de personnes dans ma liste (0 si erreur / script SQL absent).
Future<int> nombreAmisProches() async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return 0;
  try {
    return await supabase.from('amis_proches').count().eq('owner_id', uid);
  } catch (_) {
    return 0;
  }
}

class _Personne {
  final String id;
  final String nom;
  final String? photo;
  final String? pseudo;
  const _Personne(this.id, this.nom, this.photo, [this.pseudo]);
}

class EcranAmisProches extends StatefulWidget {
  const EcranAmisProches({super.key});

  @override
  State<EcranAmisProches> createState() => _EcranAmisProchesState();
}

class _EcranAmisProchesState extends State<EcranAmisProches> {
  final Set<String> _liste = {};
  final Map<String, _Personne> _personnes = {};
  final List<String> _ordre = []; // contacts des conversations d'abord
  List<_Personne> _trouves = [];
  String _recherche = '';
  int _rechercheNumero = 0;
  bool _chargement = true;

  String? get _uid => supabase.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final uid = _uid;
    if (uid == null) return;
    // 1. Mes contacts de conversation
    if (Get.isRegistered<ChatListController>()) {
      for (final c in Get.find<ChatListController>().conversations) {
        if (c.userId.isEmpty || _personnes.containsKey(c.userId)) continue;
        _personnes[c.userId] = _Personne(c.userId, c.userName, c.userPhotoUrl);
        _ordre.add(c.userId);
      }
    }
    // 2. Ma liste actuelle (dont des personnes sans conversation)
    try {
      final rows = await supabase
          .from('amis_proches')
          .select(
              'ami_id, profiles!amis_proches_ami_id_fkey(name, photo_url, username)')
          .eq('owner_id', uid);
      for (final r in rows as List) {
        final id = r['ami_id'] as String;
        _liste.add(id);
        final p = r['profiles'] as Map<String, dynamic>?;
        if (!_personnes.containsKey(id)) {
          _personnes[id] = _Personne(id, p?['name'] ?? 'Utilisateur',
              p?['photo_url'] as String?, p?['username'] as String?);
          _ordre.insert(0, id);
        }
      }
    } catch (e) {
      debugPrint('amis_proches : $e'); // script SQL 030 absent ?
    }
    if (mounted) setState(() => _chargement = false);
  }

  Future<void> _basculer(_Personne p) async {
    final uid = _uid;
    if (uid == null) return;
    final ajouter = !_liste.contains(p.id);
    setState(() {
      ajouter ? _liste.add(p.id) : _liste.remove(p.id);
      if (!_personnes.containsKey(p.id)) {
        _personnes[p.id] = p;
        _ordre.insert(0, p.id);
      }
    });
    try {
      if (ajouter) {
        await supabase
            .from('amis_proches')
            .upsert({'owner_id': uid, 'ami_id': p.id}, ignoreDuplicates: true);
      } else {
        await supabase
            .from('amis_proches')
            .delete()
            .eq('owner_id', uid)
            .eq('ami_id', p.id);
      }
    } catch (e) {
      debugPrint('amis_proches basculer : $e');
      if (!mounted) return;
      setState(() => ajouter ? _liste.remove(p.id) : _liste.add(p.id));
      Get.snackbar('Oups', 'Modification non enregistrée, vérifie ta connexion',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white);
    }
  }

  // Recherche par @pseudo pour ajouter quelqu'un sans conversation
  Future<void> _chercher(String q) async {
    setState(() => _recherche = q);
    final pseudo = q.trim().replaceFirst(RegExp(r'^@+'), '');
    final numero = ++_rechercheNumero;
    if (pseudo.length < 3) {
      setState(() => _trouves = []);
      return;
    }
    await Future.delayed(const Duration(milliseconds: 350));
    if (numero != _rechercheNumero) return;
    try {
      final rows = await supabase
          .rpc('chercher_par_pseudo', params: {'p_q': pseudo}) as List;
      if (numero != _rechercheNumero || !mounted) return;
      setState(() => _trouves = rows
          .map((r) => _Personne(r['id'] as String, r['name'] ?? 'Utilisateur',
              r['photo_url'] as String?, r['username'] as String?))
          .toList());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final q = _recherche.trim().toLowerCase().replaceFirst(RegExp(r'^@+'), '');
    final contacts = _ordre
        .map((id) => _personnes[id]!)
        .where((p) =>
            q.isEmpty ||
            p.nom.toLowerCase().contains(q) ||
            (p.pseudo ?? '').toLowerCase().contains(q))
        .toList();
    final dejaAffiches = contacts.map((p) => p.id).toSet();
    final autres = _trouves.where((p) => !dejaAffiches.contains(p.id)).toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Text('⭐ Amis proches (${_liste.length})',
            style: const TextStyle(
                fontFamily: 'Syne', fontWeight: FontWeight.w800)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
              'Seules ces personnes verront tes stories « Amis proches ». '
              'Elles ne savent pas qu\'elles sont dans ta liste.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            onChanged: _chercher,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Rechercher un nom ou un @pseudo…',
              hintStyle: TextStyle(color: AppColors.textMuted),
              prefixIcon:
                  Icon(Icons.search_rounded, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: _chargement
              ? Center(
                  child: CircularProgressIndicator(color: AppColors.accent))
              : (contacts.isEmpty && autres.isEmpty)
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                            q.isEmpty
                                ? 'Discute avec des gens ou cherche un @pseudo pour les ajouter'
                                : 'Personne trouvé',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textMuted)),
                      ),
                    )
                  : ListView(children: [
                      for (final p in contacts) _ligne(p),
                      if (autres.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                          child: Text('PROFILS ZAMU',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: AppColors.textMuted)),
                        ),
                        for (final p in autres) _ligne(p),
                      ],
                    ]),
        ),
      ]),
    );
  }

  Widget _ligne(_Personne p) {
    final dans = _liste.contains(p.id);
    return ListTile(
      onTap: () => _basculer(p),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: AppColors.surface2,
        backgroundImage: (p.photo ?? '').isNotEmpty
            ? CachedNetworkImageProvider(p.photo!)
            : null,
        child: (p.photo ?? '').isEmpty
            ? Text(p.nom.isEmpty ? '?' : p.nom[0].toUpperCase(),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700))
            : null,
      ),
      title: Text(p.nom,
          style: TextStyle(
              fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      subtitle: (p.pseudo ?? '').isNotEmpty
          ? Text('@${p.pseudo}',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13))
          : null,
      trailing: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dans ? AppColors.online : Colors.transparent,
          border: Border.all(
              color: dans ? AppColors.online : AppColors.border, width: 2),
        ),
        child: dans
            ? const Icon(Icons.star_rounded, size: 16, color: Colors.white)
            : null,
      ),
    );
  }
}
