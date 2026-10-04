import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ═══════════════════════════════════════════════════════════════
// Modération des photos via la fonction serveur moderate-image
// (analyse Sightengine). C'est le serveur qui publie la photo sur le
// profil / valide la story selon le résultat.
// ═══════════════════════════════════════════════════════════════

enum ModerationResult {
  /// Publiée (analysée et correcte, ou publiée sans analyse possible).
  approved,

  /// Douteuse : cachée jusqu'à la validation par un administrateur.
  pending,

  /// Refusée : contenu explicite, fichier supprimé par le serveur.
  rejected,

  /// Galerie pleine (photos publiées + en attente).
  full,

  /// Appel impossible (réseau, serveur).
  error,
}

class ModerationService {
  static Future<ModerationResult> _call(Map<String, dynamic> body) async {
    try {
      final res = await Supabase.instance.client.functions
          .invoke('moderate-image', body: body);
      final data = res.data;
      final status = data is Map ? data['status'] : null;
      switch (status) {
        case 'approved':
        case 'unchecked':
          return ModerationResult.approved;
        case 'pending':
          return ModerationResult.pending;
        case 'rejected':
          return ModerationResult.rejected;
      }
      return ModerationResult.error;
    } on FunctionException catch (e) {
      debugPrint('moderate-image ${e.status}: ${e.details}');
      if (e.status == 409) return ModerationResult.full;
      return ModerationResult.error;
    } catch (e) {
      debugPrint('moderate-image error: $e');
      return ModerationResult.error;
    }
  }

  /// Photo principale déjà envoyée dans le bucket `avatars`.
  static Future<ModerationResult> photoProfil(String publicUrl) =>
      _call({'kind': 'profile', 'url': publicUrl});

  /// Photo de galerie déjà envoyée dans le bucket `profile-photos`.
  static Future<ModerationResult> photoGalerie(String publicUrl) =>
      _call({'kind': 'gallery', 'url': publicUrl});

  /// Photo d'un message de groupe déjà inséré (supprimée si explicite).
  static Future<ModerationResult> photoGroupe(String messageId) =>
      _call({'kind': 'groupe', 'id': messageId});

  /// Story (photo ou vidéo) déjà insérée dans `stories`.
  static Future<ModerationResult> story(String storyId) =>
      _call({'kind': 'story', 'id': storyId});

  static const messageRefus =
      'Cette photo ne respecte pas nos règles (nudité ou contenu explicite). '
      'Choisis-en une autre.';
  static const messageAttente =
      'Ta photo est en cours de vérification. Elle apparaîtra dès '
      'qu\'elle sera validée.';
}
