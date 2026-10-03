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
  const PersonneAcces({required this.id, required this.nom, this.photoUrl});
}

class AlbumService {
  AlbumService._();

  static const maxPhotos = 12;
  static const _bucket = 'albums';
  static SupabaseClient get _sb => Supabase.instance.client;
  static String? get _uid => _sb.auth.currentUser?.id;

  /// Photos de l'album de [ownerId] — vide si je n'y ai pas accès.
  static Future<List<PhotoAlbum>> photosDe(String ownerId) async {
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
    final acces = await _sb
        .from('album_acces')
        .select('viewer_id')
        .eq('owner_id', uid)
        .order('created_at', ascending: false);
    final ids = (acces as List).map((r) => r['viewer_id'] as String).toList();
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
        ),
    ];
  }
}
