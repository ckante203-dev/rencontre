// lib/features/annonces/controller/annonces_controller.dart

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
  final RxInt unseenCount = 0.obs;
  DateTime? _lastSeenAt;

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
        myLikes =
            (likesData as List).map((l) => l['annonce_id'].toString()).toList();
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
              ? DateTime.parse(row['boosted_until'])
              : null,
          isAnonyme: isAnon,
          mediaUrl: row['media_url'],
          isVideo: row['is_video'] ?? false,
          reponsesCount: row['reponses_count'] ?? 0,
          commentsEnabled: row['comments_enabled'] ?? true,
        );
      }).toList();
      _updateUnseenCount();
    } catch (e) {
      debugPrint('loadAnnonces error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void markAnnoncesAsSeen() {
    _lastSeenAt = DateTime.now();
    unseenCount.value = 0;
  }

  void _updateUnseenCount() {
    if (_lastSeenAt == null) {
      unseenCount.value = annonces.length;
      return;
    }
    unseenCount.value =
        annonces.where((a) => a.createdAt.isAfter(_lastSeenAt!)).length;
  }

  Future<void> toggleLike(AnnonceModel annonce) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    final idx = annonces.indexWhere((a) => a.id == annonce.id);
    if (idx < 0) return;

    final newLiked = !annonce.isLiked;
    final newCount = annonce.likes + (newLiked ? 1 : -1);
    annonces[idx] = AnnonceModel(
      id: annonce.id,
      userId: annonce.userId,
      userName: annonce.userName,
      userPhotoUrl: annonce.userPhotoUrl,
      userAge: annonce.userAge,
      titre: annonce.titre,
      description: annonce.description,
      categorie: annonce.categorie,
      ville: annonce.ville,
      createdAt: annonce.createdAt,
      likes: newCount,
      isLiked: newLiked,
      isBoosted: annonce.isBoosted,
      boostedUntil: annonce.boostedUntil,
      isAnonyme: annonce.isAnonyme,
      mediaUrl: annonce.mediaUrl,
      isVideo: annonce.isVideo,
      reponsesCount: annonce.reponsesCount,
      commentsEnabled: annonce.commentsEnabled,
    );

    try {
      if (!newLiked) {
        await _sb
            .from('annonce_likes')
            .delete()
            .eq('annonce_id', annonce.id)
            .eq('user_id', uid);
        await _sb
            .from('annonces')
            .update({'likes_count': newCount}).eq('id', annonce.id);
      } else {
        await _sb
            .from('annonce_likes')
            .insert({'annonce_id': annonce.id, 'user_id': uid});
        await _sb
            .from('annonces')
            .update({'likes_count': newCount}).eq('id', annonce.id);
      }
    } catch (e) {
      debugPrint('toggleLike error: $e');
      annonces[idx] = annonce;
    }
  }

  Future<String?> _uploadMedia(XFile file, bool isVideo) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;

    try {
      final bytes = await file.readAsBytes();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      String ext = 'jpg';
      String contentType = 'image/jpeg';
      if (isVideo) {
        final nameLower = file.name.toLowerCase();
        if (nameLower.endsWith('.mp4')) {
          ext = 'mp4';
          contentType = 'video/mp4';
        } else if (nameLower.endsWith('.mov')) {
          ext = 'mov';
          contentType = 'video/quicktime';
        } else if (nameLower.endsWith('.avi')) {
          ext = 'avi';
          contentType = 'video/x-msvideo';
        } else {
          ext = 'mp4';
          contentType = 'video/mp4';
        }
      } else {
        final nameLower = file.name.toLowerCase();
        if (nameLower.endsWith('.png')) {
          ext = 'png';
          contentType = 'image/png';
        } else if (nameLower.endsWith('.webp')) {
          ext = 'webp';
          contentType = 'image/webp';
        } else {
          ext = 'jpg';
          contentType = 'image/jpeg';
        }
      }

      final path = '$uid/$timestamp.$ext';
      await _sb.storage
          .from(isVideo ? 'annonces-videos' : 'annonces-images')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
      return _sb.storage
          .from(isVideo ? 'annonces-videos' : 'annonces-images')
          .getPublicUrl(path);
    } catch (e) {
      debugPrint('_uploadMedia error: $e');
      Get.snackbar(
        'Erreur upload',
        'Impossible d\'uploader : $e',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red.shade900,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
      return null;
    }
  }

  Future<bool> publierAnnonce({
    required String titre,
    required String description,
    required String categorie,
    String? ville,
    bool anonyme = false,
    XFile? mediaFile,
    bool isVideo = false,
    bool commentsEnabled = true,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return false;

    try {
      String? mediaUrl;
      if (mediaFile != null) {
        mediaUrl = await _uploadMedia(mediaFile, isVideo);
        if (mediaUrl == null) {
          bool publishAnyway = false;
          await Get.dialog(AlertDialog(
            backgroundColor: const Color(0xFF1A1228),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Upload échoué',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
            content: const Text(
                'Le fichier n\'a pas pu être uploadé.\nVoulez-vous publier sans média ?',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            actions: [
              TextButton(
                  onPressed: () {
                    publishAnyway = false;
                    Get.back();
                  },
                  child: const Text('Annuler',
                      style: TextStyle(color: Colors.white54))),
              TextButton(
                  onPressed: () {
                    publishAnyway = true;
                    Get.back();
                  },
                  child: const Text('Publier quand même',
                      style: TextStyle(
                          color: Colors.pinkAccent,
                          fontWeight: FontWeight.w700))),
            ],
          ));
          if (!publishAnyway) return false;
        }
      }

      await _sb.from('annonces').insert({
        'user_id': uid,
        'titre': titre,
        'description': description,
        'categorie': categorie,
        'ville': anonyme ? null : ville,
        'likes_count': 0,
        'reponses_count': 0,
        'is_boosted': false,
        'is_anonyme': anonyme,
        'media_url': mediaUrl,
        'is_video': isVideo,
        'comments_enabled': commentsEnabled,
      });

      await loadAnnonces();
      return true;
    } catch (e) {
      debugPrint('publierAnnonce error: $e');
      Get.snackbar(
        'Erreur',
        'Publication échouée : $e',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red.shade900,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
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

  Future<void> boosterAnnonce(AnnonceModel annonce) async {
    isBoosting.value = true;
    try {
      final until = DateTime.now().add(const Duration(hours: 24));
      await _sb.from('annonces').update({
        'is_boosted': true,
        'boosted_until': until.toIso8601String(),
      }).eq('id', annonce.id);
      await loadAnnonces();
      Get.snackbar(
        '⚡ Annonce boostée !',
        'Visible en tête de liste pendant 24h',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF1A1228),
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      debugPrint('boosterAnnonce error: $e');
    } finally {
      isBoosting.value = false;
    }
  }

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
      Get.snackbar(
        '⚡ Profil boosté !',
        'Tu apparais en premier pendant 30 minutes',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF1A1228),
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      debugPrint('boosterProfil error: $e');
    } finally {
      isBoosting.value = false;
    }
  }
}
