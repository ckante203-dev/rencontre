import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

// ══════════════════════════════════════════════════════════════════
//  ALBUM PRIVÉ (façon Grindr)
//  Photos dans le bucket PRIVÉ « albums » (dossier = id du propriétaire).
//  Personne ne les voit, sauf les personnes à qui on a partagé l'album
//  (table album_acces). Le serveur le vérifie (RLS + politiques Storage,
//  script 20261002000020_album_prive.sql) ; l'app n'affiche que des liens
//  temporaires (1 h).
// ══════════════════════════════════════════════════════════════════

class PhotoAlbum {
  final String id;
  final String chemin;
  final String url; // lien temporaire
  const PhotoAlbum({required this.id, required this.chemin, required this.url});
}

class PersonneAcces {
  final String id;
  final String nom;
  final String? photoUrl;
  final int vues; // nombre d'ouvertures de mon album par cette personne
  final DateTime? derniereVue;
  const PersonneAcces(
      {required this.id,
      required this.nom,
      this.photoUrl,
      this.vues = 0,
      this.derniereVue});
}

class AlbumService {
  AlbumService._();

  static const maxPhotos = 12;
  static const _bucket = 'albums';
  static SupabaseClient get _sb => Supabase.instance.client;
  static String? get _uid => _sb.auth.currentUser?.id;

  /// Photos de l'album de [ownerId] — vide si je n'y ai pas accès.
  static Future<List<PhotoAlbum>> photosDe(String ownerId) async {
    // Ouverture de l'album de quelqu'un d'autre : comptée pour lui (SQL 052)
    if (ownerId != _uid) {
      _sb
          .rpc('noter_vue_album', params: {'p_owner': ownerId})
          .then((_) {}, onError: (_) {});
    }
    final rows = await _sb
        .from('album_photos')
        .select('id, chemin')
        .eq('owner_id', ownerId)
        .order('created_at');
    final liste = List<Map<String, dynamic>>.from(rows);
    if (liste.isEmpty) return [];
    final chemins = liste.map((r) => r['chemin'] as String).toList();
    final signes =
        await _sb.storage.from(_bucket).createSignedUrls(chemins, 3600);
    final urlParChemin = {for (final s in signes) s.path: s.signedUrl};
    return [
      for (final r in liste)
        if (urlParChemin[r['chemin']] != null)
          PhotoAlbum(
            id: r['id'] as String,
            chemin: r['chemin'] as String,
            url: urlParChemin[r['chemin']]!,
          ),
    ];
  }

  static Future<List<PhotoAlbum>> mesPhotos() async {
    final uid = _uid;
    if (uid == null) return [];
    return photosDe(uid);
  }

  static Future<void> ajouter(File fichier) async {
    final uid = _uid;
    if (uid == null) return;
    final chemin = '$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _sb.storage.from(_bucket).upload(chemin, fichier,
        fileOptions: const FileOptions(contentType: 'image/jpeg'));
    try {
      await _sb.from('album_photos').insert({'owner_id': uid, 'chemin': chemin});
    } catch (_) {
      // Ligne refusée (limite atteinte…) : on ne laisse pas le fichier seul.
      await _sb.storage.from(_bucket).remove([chemin]).catchError((_) => <FileObject>[]);
      rethrow;
    }
  }

  static Future<void> supprimer(PhotoAlbum photo) async {
    await _sb.from('album_photos').delete().eq('id', photo.id);
    await _sb.storage.from(_bucket).remove([photo.chemin]).catchError((_) => <FileObject>[]);
  }

  /// [viewerId] peut-il voir mon album ?
  static Future<bool> partageAvec(String viewerId) async {
    final uid = _uid;
    if (uid == null) return false;
    final row = await _sb
        .from('album_acces')
        .select('viewer_id')
        .eq('owner_id', uid)
        .eq('viewer_id', viewerId)
        .maybeSingle();
    return row != null;
  }

  /// Combien de fois [viewerId] a ouvert mon album (null si inconnu).
  static Future<int?> vuesPar(String viewerId) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final row = await _sb
          .from('album_acces')
          .select('vues')
          .eq('owner_id', uid)
          .eq('viewer_id', viewerId)
          .maybeSingle();
      return (row?['vues'] as num?)?.toInt();
    } catch (_) {
      return null; // colonne vues absente (SQL 052)
    }
  }

  /// [ownerId] m'a-t-il ouvert son album ? (sans compter une « vue »)
  static Future<bool> aPartageAvecMoi(String ownerId) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      final row = await _sb
          .from('album_acces')
          .select('owner_id')
          .eq('owner_id', ownerId)
          .eq('viewer_id', uid)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }

  static Future<void> partager(String viewerId) async {
    final uid = _uid;
    if (uid == null) return;
    // ignoreDuplicates : déjà partagé → rien à faire. Un upsert « normal »
    // demanderait une règle UPDATE (absente) et échouerait au 2ᵉ partage.
    await _sb.from('album_acces').upsert(
        {'owner_id': uid, 'viewer_id': viewerId},
        ignoreDuplicates: true);
  }

  static Future<void> retirer(String viewerId) async {
    final uid = _uid;
    if (uid == null) return;
    await _sb
        .from('album_acces')
        .delete()
        .eq('owner_id', uid)
        .eq('viewer_id', viewerId);
  }

  /// Personnes qui peuvent voir mon album.
  static Future<List<PersonneAcces>> personnesAvecAcces() async {
    final uid = _uid;
    if (uid == null) return [];
    List acces;
    try {
      acces = await _sb
          .from('album_acces')
          .select('viewer_id, vues, derniere_vue')
          .eq('owner_id', uid)
          .order('created_at', ascending: false);
    } catch (_) {
      // Colonnes vues / derniere_vue absentes (SQL 052 pas encore passé)
      acces = await _sb
          .from('album_acces')
          .select('viewer_id')
          .eq('owner_id', uid)
          .order('created_at', ascending: false);
    }
    final infos = {for (final r in acces) r['viewer_id'] as String: r};
    final ids = acces.map((r) => r['viewer_id'] as String).toList();
    if (ids.isEmpty) return [];
    final profils = await _sb
        .from('profiles')
        .select('id, name, photo_url')
        .inFilter('id', ids);
    final parId = {for (final p in (profils as List)) p['id'] as String: p};
    return [
      for (final id in ids)
        PersonneAcces(
          id: id,
          nom: (parId[id]?['name'] as String?) ?? 'Utilisateur',
          photoUrl: parId[id]?['photo_url'] as String?,
          vues: (infos[id]?['vues'] as int?) ?? 0,
          derniereVue: DateTime.tryParse(
                  (infos[id]?['derniere_vue'] ?? '').toString())
              ?.toLocal(),
        ),
    ];
  }
}
