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

/// Accès d'une personne à un album : vue unique, date de fin, ouvertures.
class AccesAlbum {
  final bool vueUnique;
  final DateTime? expireLe;
  final int vues;
  const AccesAlbum({this.vueUnique = false, this.expireLe, this.vues = 0});
  bool get expire => expireLe != null && expireLe!.isBefore(DateTime.now());
}

class AlbumService {
  AlbumService._();

  static const maxPhotos = 12;
  static const _bucket = 'albums';
  static SupabaseClient get _sb => Supabase.instance.client;
  static String? get _uid => _sb.auth.currentUser?.id;

  /// Photos de l'album de [ownerId] — vide si je n'y ai pas accès.
  /// Ouvrir l'album de quelqu'un est compté pour lui ; en vue unique, la
  /// 1ʳᵉ ouverture lance les 2 minutes d'accès (SQL 094).
  static Future<List<PhotoAlbum>> photosDe(String ownerId) async {
    final uid = _uid;
    var secondes = 3600;
    if (ownerId != uid && uid != null) {
      try {
        await _sb.rpc('noter_vue_album', params: {'p_owner': ownerId});
      } catch (_) {}
      final acces = await accesDe(ownerId: ownerId, viewerId: uid);
      // Vue unique : liens valables 2 min seulement
      if (acces?.vueUnique == true) secondes = 120;
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
        await _sb.storage.from(_bucket).createSignedUrls(chemins, secondes);
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

  /// Nombre de photos de mon album (sans créer de liens).
  static Future<int> nombreMesPhotos() async {
    final uid = _uid;
    if (uid == null) return 0;
    try {
      return await _sb
          .from('album_photos')
          .count(CountOption.exact)
          .eq('owner_id', uid);
    } catch (_) {
      return 0;
    }
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

  /// Accès de [viewerId] à l'album de [ownerId] (null = pas partagé).
  static Future<AccesAlbum?> accesDe(
      {required String ownerId, required String viewerId}) async {
    Future<Map<String, dynamic>?> lire(String colonnes) => _sb
        .from('album_acces')
        .select(colonnes)
        .eq('owner_id', ownerId)
        .eq('viewer_id', viewerId)
        .maybeSingle();
    Map<String, dynamic>? row;
    try {
      row = await lire('vues, expire_le, vue_unique');
    } catch (_) {
      // Colonnes absentes (SQL 052 / 094 pas encore passés)
      try {
        row = await lire('owner_id');
      } catch (_) {
        return null;
      }
    }
    if (row == null) return null;
    return AccesAlbum(
      vueUnique: row['vue_unique'] == true,
      expireLe: DateTime.tryParse('${row['expire_le'] ?? ''}')?.toLocal(),
      vues: (row['vues'] as num?)?.toInt() ?? 0,
    );
  }

  /// Mon album, vu par [viewerId] (null = pas partagé).
  static Future<AccesAlbum?> monAccesPour(String viewerId) async {
    final uid = _uid;
    if (uid == null) return null;
    return accesDe(ownerId: uid, viewerId: viewerId);
  }

  /// [ownerId] m'a-t-il ouvert son album, encore valable ? (sans compter
  /// une ouverture)
  static Future<bool> aPartageAvecMoi(String ownerId) async {
    final uid = _uid;
    if (uid == null) return false;
    final a = await accesDe(ownerId: ownerId, viewerId: uid);
    return a != null && !a.expire;
  }

  /// Ouvre mon album à [viewerId] : sans limite, pour une [duree], ou en
  /// [vueUnique] (2 min à partir de la 1ʳᵉ ouverture). Un nouveau partage
  /// remplace le précédent (supprimer puis créer : pas de règle UPDATE).
  static Future<void> partager(String viewerId,
      {Duration? duree, bool vueUnique = false}) async {
    final uid = _uid;
    if (uid == null) return;
    final base = {'owner_id': uid, 'viewer_id': viewerId};
    final limite = duree != null || vueUnique;
    if (!limite) {
      // Sans limite : un partage déjà présent est gardé tel quel s'il
      // n'a pas de limite ; sinon il est remplacé.
      final a = await accesDe(ownerId: uid, viewerId: viewerId);
      if (a != null && a.expireLe == null && !a.vueUnique) return;
    }
    await retirer(viewerId);
    try {
      await _sb.from('album_acces').insert({
        ...base,
        if (duree != null)
          'expire_le': DateTime.now().add(duree).toUtc().toIso8601String(),
        if (vueUnique) 'vue_unique': true,
      });
    } on PostgrestException catch (e) {
      // Colonnes absentes (SQL 094 pas encore passé) : partage sans limite
      if (!limite || (e.code != 'PGRST204' && e.code != '42703')) rethrow;
      await _sb.from('album_acces').insert(base);
    }
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
