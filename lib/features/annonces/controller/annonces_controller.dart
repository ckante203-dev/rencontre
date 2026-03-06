import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/features/annonces/model/annonce_model.dart';

class AnnoncesController extends GetxController {
  final _sb = Supabase.instance.client;

  final RxList<AnnonceModel> annonces = <AnnonceModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxString filterCategorie = 'toutes'.obs;
  final RxBool isBoosting = false.obs;

  final categories = ['toutes', 'rencontre', 'amitie', 'sortie', 'voyage'];

  @override
  void onInit() {
    super.onInit();
    loadAnnonces();
  }

  List<AnnonceModel> get filtered {
    if (filterCategorie.value == 'toutes') return annonces.toList();
    return annonces.where((a) => a.categorie == filterCategorie.value).toList();
  }

  Future<void> loadAnnonces() async {
    isLoading.value = true;
    try {
      final uid = _sb.auth.currentUser?.id;
      final data = await _sb
        .from('annonces')
        .select('*, profiles(name, photo_url, age)')
        .order('is_boosted', ascending: false)
        .order('created_at', ascending: false)
        .limit(50);

      List<String> myLikes = [];
      if (uid != null) {
        final likesData = await _sb
          .from('annonce_likes')
          .select('annonce_id')
          .eq('user_id', uid);
        myLikes = (likesData as List)
          .map((l) => l['annonce_id'].toString()).toList();
      }

      annonces.value = (data as List).map((row) {
        final p = row['profiles'] as Map<String, dynamic>?;
        final isAnon = row['is_anonyme'] ?? false;
        return AnnonceModel(
          id: row['id'],
          userId: row['user_id'],
          userName: isAnon ? 'Anonyme' : (p?['name'] ?? 'Utilisateur'),
          userPhotoUrl: isAnon ? null : p?['photo_url'],
          userAge: p?['age'] ?? 18,
          titre: row['titre'] ?? '',
          description: row['description'] ?? '',
          categorie: row['categorie'] ?? 'rencontre',
          ville: isAnon ? null : row['ville'],
          createdAt: DateTime.parse(row['created_at']),
          likes: row['likes_count'] ?? 0,
          isLiked: myLikes.contains(row['id']),
          isBoosted: row['is_boosted'] ?? false,
          boostedUntil: row['boosted_until'] != null
            ? DateTime.parse(row['boosted_until']) : null,
          isAnonyme: isAnon,
          mediaUrl: row['media_url'],
          isVideo: row['is_video'] ?? false,
        );
      }).toList();
    } catch (e) {
      debugPrint('loadAnnonces error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> toggleLike(AnnonceModel annonce) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final idx = annonces.indexWhere((a) => a.id == annonce.id);
      if (idx < 0) return;

      if (annonce.isLiked) {
        await _sb.from('annonce_likes').delete()
          .eq('annonce_id', annonce.id).eq('user_id', uid);
        await _sb.from('annonces')
          .update({'likes_count': annonce.likes - 1}).eq('id', annonce.id);
      } else {
        await _sb.from('annonce_likes')
          .insert({'annonce_id': annonce.id, 'user_id': uid});
        await _sb.from('annonces')
          .update({'likes_count': annonce.likes + 1}).eq('id', annonce.id);
      }
      await loadAnnonces();
    } catch (e) {
      debugPrint('toggleLike error: $e');
    }
  }

  // ── Publier avec anonyme + media ──────────────────────────────
  Future<bool> publierAnnonce({
    required String titre,
    required String description,
    required String categorie,
    String? ville,
    bool anonyme = false,
    XFile? mediaFile,
    bool isVideo = false,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      String? mediaUrl;

      // Upload du media si présent
      if (mediaFile != null) {
        final bytes = await mediaFile.readAsBytes();
        final ext = isVideo ? 'mp4' : 'jpg';
        final path = 'annonces/$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
        final bucket = isVideo ? 'annonces-videos' : 'annonces-images';

        await _sb.storage.from(bucket).uploadBinary(path, bytes,
          fileOptions: FileOptions(
            contentType: isVideo ? 'video/mp4' : 'image/jpeg',
            upsert: true));

        mediaUrl = _sb.storage.from(bucket).getPublicUrl(path);
      }

      await _sb.from('annonces').insert({
        'user_id': uid,
        'titre': titre,
        'description': description,
        'categorie': categorie,
        'ville': anonyme ? null : ville,
        'likes_count': 0,
        'is_boosted': false,
        'is_anonyme': anonyme,
        'media_url': mediaUrl,
        'is_video': isVideo,
      });

      await loadAnnonces();
      return true;
    } catch (e) {
      debugPrint('publierAnnonce error: $e');
      return false;
    }
  }

  Future<void> supprimerAnnonce(String id) async {
    try {
      await _sb.from('annonces').delete().eq('id', id);
      annonces.removeWhere((a) => a.id == id);
    } catch (e) {
      debugPrint('supprimerAnnonce error: $e');
    }
  }

  // ── BOOST annonce ─────────────────────────────────────────────
  Future<void> boosterAnnonce(AnnonceModel annonce) async {
    isBoosting.value = true;
    try {
      final until = DateTime.now().add(const Duration(hours: 24));
      await _sb.from('annonces').update({
        'is_boosted': true,
        'boosted_until': until.toIso8601String(),
      }).eq('id', annonce.id);
      await loadAnnonces();
      Get.snackbar('⚡ Annonce boostée !',
        'Visible en tête de liste pendant 24h',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF1A1228),
        colorText: Colors.white,
        duration: const Duration(seconds: 3));
    } catch (e) {
      debugPrint('boosterAnnonce error: $e');
    } finally {
      isBoosting.value = false;
    }
  }

  // ── BOOST profil ──────────────────────────────────────────────
  Future<void> boosterProfil() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    isBoosting.value = true;
    try {
      final until = DateTime.now().add(const Duration(minutes: 30));
      await _sb.from('profiles').update({
        'is_boosted': true,
        'boosted_until': until.toIso8601String(),
      }).eq('id', uid);
      Get.snackbar('⚡ Profil boosté !',
        'Tu apparais en premier pendant 30 minutes',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF1A1228),
        colorText: Colors.white,
        duration: const Duration(seconds: 3));
    } catch (e) {
      debugPrint('boosterProfil error: $e');
    } finally {
      isBoosting.value = false;
    }
  }
}