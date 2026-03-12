// lib/features/annonces/controller/annonce_comment_controller.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/features/annonces/model/annonce_comment_model.dart';
import 'package:rencontre/features/annonces/model/annonce_model.dart';
import 'package:rencontre/core/services/notification_service.dart';

class AnnonceCommentController extends GetxController {
  final AnnonceModel annonce; // ← on garde la publication complète
  AnnonceCommentController({required this.annonce});

  String get annonceId => annonce.id;

  final _db = Supabase.instance.client;
  String? get _myUid => _db.auth.currentUser?.id;

  final RxList<AnnonceCommentModel> comments = <AnnonceCommentModel>[].obs;
  final RxBool loading = true.obs;
  final RxBool sending = false.obs;
  final TextEditingController textCtrl = TextEditingController();
  final RxString replyingToId = ''.obs;
  final RxString replyingToName = ''.obs;

  @override
  void onInit() {
    super.onInit();
    loadComments();
  }

  @override
  void onClose() {
    textCtrl.dispose();
    super.onClose();
  }

  Future<void> loadComments() async {
    loading.value = true;
    try {
      final data = await _db
          .from('annonce_comments')
          .select()
          .eq('annonce_id', annonceId)
          .order('created_at', ascending: true);

      final all = (data as List)
          .map((m) => AnnonceCommentModel.fromMap(
                m as Map<String, dynamic>,
                myUid: _myUid,
              ))
          .toList();

      final parents = all.where((c) => c.parentId == null).toList();
      final result = parents.map((parent) {
        final replies = all.where((c) => c.parentId == parent.id).toList();
        return parent.copyWith(replies: replies);
      }).toList();

      comments.value = result;
    } catch (e) {
      debugPrint('loadComments error: $e');
    } finally {
      loading.value = false;
    }
  }

  void startReply(String commentId, String userName) {
    replyingToId.value = commentId;
    replyingToName.value = userName;
  }

  void cancelReply() {
    replyingToId.value = '';
    replyingToName.value = '';
  }

  Future<void> sendComment() async {
    final texte = textCtrl.text.trim();
    if (texte.isEmpty || sending.value) return;
    final uid = _myUid;
    if (uid == null) return;

    sending.value = true;
    try {
      // Récupérer le profil de l'expéditeur
      final profile = await _db
          .from('profiles')
          .select('name, photo_url')
          .eq('id', uid)
          .maybeSingle();

      final senderName = profile?['name'] ?? 'Utilisateur';
      final senderPhoto = profile?['photo_url'];
      final parentId =
          replyingToId.value.isNotEmpty ? replyingToId.value : null;

      // ── Insérer le commentaire ──
      await _db.from('annonce_comments').insert({
        'annonce_id': annonceId,
        'user_id': uid,
        'user_name': senderName,
        'user_photo_url': senderPhoto,
        'is_anonyme': false, // le commentateur n'est jamais anonyme
        'texte': texte,
        'parent_id': parentId,
        'liked_by': [],
        'created_at': DateTime.now().toIso8601String(),
      });

      // ── Incrémenter reponses_count si commentaire racine ──
      if (parentId == null) {
        try {
          await _db.rpc('increment_annonce_reponses',
              params: {'p_annonce_id': annonceId});
        } catch (_) {
          // Fallback manuel
          final row = await _db
              .from('annonces')
              .select('reponses_count')
              .eq('id', annonceId)
              .maybeSingle();
          final current = (row?['reponses_count'] ?? 0) as int;
          await _db
              .from('annonces')
              .update({'reponses_count': current + 1}).eq('id', annonceId);
        }
      }

      // ── Notification au propriétaire de l'annonce ──
      if (annonce.userId != uid) {
        _sendNotification(
          toUserId: annonce.userId,
          title: '💬 Nouveau commentaire',
          body: '$senderName a commenté ton annonce : "$texte"',
          type: 'comment',
        );
      }

      textCtrl.clear();
      cancelReply();
      await loadComments();
    } catch (e) {
      debugPrint('sendComment error: $e');
      Get.snackbar(
        'Erreur',
        'Impossible d\'envoyer : $e',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF1A0A0A),
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    } finally {
      sending.value = false;
    }
  }

  Future<void> toggleLike(AnnonceCommentModel comment) async {
    final uid = _myUid;
    if (uid == null) return;

    // Optimiste
    _updateCommentInList(
      comment.id,
      comment.isLiked
          ? comment.copyWith(likes: comment.likes - 1, isLiked: false)
          : comment.copyWith(likes: comment.likes + 1, isLiked: true),
    );

    try {
      final row = await _db
          .from('annonce_comments')
          .select('liked_by')
          .eq('id', comment.id)
          .maybeSingle();
      if (row == null) return;

      final liked = List<String>.from(row['liked_by'] ?? []);
      final wasLiked = liked.contains(uid);
      if (wasLiked) {
        liked.remove(uid);
      } else {
        liked.add(uid);
        // Notifier le propriétaire du commentaire
        if (comment.userId != uid) {
          final myProfile = await _db
              .from('profiles')
              .select('name')
              .eq('id', uid)
              .maybeSingle();
          final myName = myProfile?['name'] ?? 'Quelqu\'un';
          _sendNotification(
            toUserId: comment.userId,
            title: '❤️ Ton commentaire a été aimé',
            body: '$myName a aimé ton commentaire',
            type: 'like_comment',
          );
        }
      }

      await _db
          .from('annonce_comments')
          .update({'liked_by': liked}).eq('id', comment.id);
    } catch (e) {
      debugPrint('toggleLike comment error: $e');
      await loadComments(); // rollback
    }
  }

  // ── Notification like sur l'annonce elle-même ──
  Future<void> notifyAnnonceLike({required String likerName}) async {
    final uid = _myUid;
    if (uid == null || annonce.userId == uid) return;
    _sendNotification(
      toUserId: annonce.userId,
      title: '❤️ Quelqu\'un aime ton annonce',
      body: '$likerName a aimé ton annonce "${annonce.titre}"',
      type: 'like_annonce',
    );
  }

  void _updateCommentInList(String id, AnnonceCommentModel updated) {
    final idx = comments.indexWhere((c) => c.id == id);
    if (idx != -1) {
      comments[idx] = updated;
      comments.refresh();
      return;
    }
    for (int i = 0; i < comments.length; i++) {
      final ri = comments[i].replies.indexWhere((r) => r.id == id);
      if (ri != -1) {
        final newReplies = [...comments[i].replies];
        newReplies[ri] = updated;
        comments[i] = comments[i].copyWith(replies: newReplies);
        comments.refresh();
        return;
      }
    }
  }

  Future<void> deleteComment(AnnonceCommentModel comment) async {
    final uid = _myUid;
    if (uid == null) return;
    // Autorisé si : auteur du commentaire OU propriétaire de l'annonce
    final canDelete = comment.userId == uid || annonce.userId == uid;
    if (!canDelete) return;
    try {
      await _db.from('annonce_comments').delete().eq('id', comment.id);
      await loadComments();
    } catch (e) {
      debugPrint('deleteComment error: $e');
    }
  }

  // ── Envoyer une notification locale + FCM ──────────────────────
  Future<void> _sendNotification({
    required String toUserId,
    required String title,
    required String body,
    required String type,
  }) async {
    try {
      final myUid = _myUid;
      // Ne pas notifier soi-même
      if (toUserId == myUid) return;

      // 1. Notification locale (si l'app est en premier plan sur l'appareil)
      await NotificationService.showAnnonceNotification(
        title: title,
        body: body,
      );

      // 2. Notification push via Edge Function (si l'app est fermée/background)
      final row = await _db
          .from('profiles')
          .select('fcm_token')
          .eq('id', toUserId)
          .maybeSingle();

      final token = row?['fcm_token'] as String?;
      if (token == null || token.isEmpty) return;

      await _db.functions.invoke('send-notification', body: {
        'token': token,
        'title': title,
        'body': body,
        'data': {
          'type': type,
          'annonceId': annonceId,
        },
      });
    } catch (e) {
      debugPrint('_sendNotification error (non bloquant): $e');
    }
  }
}
