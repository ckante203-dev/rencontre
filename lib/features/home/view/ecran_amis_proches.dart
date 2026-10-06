import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/features/amis/amis_controller.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';

// ─── QUI VOIT MES STORIES ─────────────────────────────────────────
// Deux listes, filtrées par la base (personne d'autre ne peut les lire,
// les personnes ne savent pas qu'elles y sont) :
// • ⭐ Amis proches : seuls eux voient mes stories « Amis proches »
//   (politique stories_amis_proches) ;
// • 🚫 Masquer à : ils ne voient AUCUNE de mes stories, même publiques
//   (politique stories_masquees).

enum ListeStory {
  proches('amis_proches', 'ami_id'),
  masques('story_masquee', 'cible_id');

  final String table;
  final String colonne;
  const ListeStory(this.table, this.colonne);
}

/// Nombre de personnes dans une liste (0 si erreur / script SQL absent).
Future<int> nombreDansListe(ListeStory liste) async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return 0;
  try {
    return await supabase.from(liste.table).count().eq('owner_id', uid);
  } catch (_) {
    return 0;
  }
}

Future<int> nombreAmisProches() => nombreDansListe(ListeStory.proches);

class _Personne {
  final String id;
  final String nom;
  final String? photo;
  final String? pseudo;
  const _Personne(this.id, this.nom, this.photo, [this.pseudo]);
}

class EcranAmisProches extends StatefulWidget {
  final ListeStory liste;
  const EcranAmisProches({super.key, this.liste = ListeStory.proches});

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
  ListeStory get _l => widget.liste;
  bool get _masques => _l == ListeStory.masques;
  Color get _couleur => _masques ? AppColors.error : AppColors.online;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final uid = _uid;
    if (uid == null) return;
    // 0. Mes amis d'abord
    if (Get.isRegistered<AmisController>()) {
      for (final a in AmisController.to.amis) {
        if (_personnes.containsKey(a.id)) continue;
        _personnes[a.id] = _Personne(a.id, a.nom, a.photoUrl, a.pseudo);
        _ordre.add(a.id);
      }
    }
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
          .from(_l.table)
          .select('${_l.colonne}, '
              'profiles!${_l.table}_${_l.colonne}_fkey(name, photo_url, username)')
          .eq('owner_id', uid);
      for (final r in rows as List) {
        final id = r[_l.colonne] as String;
        _liste.add(id);
        final p = r['profiles'] as Map<String, dynamic>?;
        if (!_personnes.containsKey(id)) {
          _personnes[id] = _Personne(id, p?['name'] ?? 'Utilisateur',
              p?['photo_url'] as String?, p?['username'] as String?);
          _ordre.insert(0, id);
        }
      }
    } catch (e) {
      debugPrint('${_l.table} : $e'); // script SQL 030 / 031 absent ?
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
        await supabase.from(_l.table).upsert(
            {'owner_id': uid, _l.colonne: p.id},
            ignoreDuplicates: true);
      } else {
        await supabase
            .from(_l.table)
            .delete()
            .eq('owner_id', uid)
            .eq(_l.colonne, p.id);
      }
    } catch (e) {
      debugPrint('${_l.table} basculer : $e');
      if (!mounted) return;
      setState(() => ajouter ? _liste.remove(p.id) : _liste.add(p.id));
      Get.snackbar('Oups', 'Modification non enregistrée, vérifie ta connexion',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
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
        title: Text(
            _masques
                ? '🚫 Masquer ma story à (${_liste.length})'
                : '⭐ Amis proches (${_liste.length})',
            style: const TextStyle(
                fontFamily: 'Syne', fontWeight: FontWeight.w800)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
              _masques
                  ? 'Ces personnes ne verront AUCUNE de tes stories, même '
                      'publiques. Elles ne sont pas prévenues.'
                  : 'Seules ces personnes verront tes stories « Amis proches ». '
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
        onBackgroundImageError:
            (p.photo ?? '').isNotEmpty ? (_, __) {} : null,
        child: (p.photo ?? '').isEmpty
            ? Text(p.nom.isEmpty ? '?' : p.nom[0].toUpperCase(),
                style: TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w700))
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
          color: dans ? _couleur : Colors.transparent,
          border: Border.all(color: dans ? _couleur : AppColors.border, width: 2),
        ),
        child: dans
            ? Icon(_masques ? Icons.block_rounded : Icons.star_rounded,
                size: 16, color: AppColors.surAccent)
            : null,
      ),
    );
  }
}
