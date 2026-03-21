// lib/features/annonces/controller/annonce_comment_controller.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/features/annonces/model/annonce_comment_model.dart';
import 'package:rencontre/features/annonces/model/annonce_model.dart';
import 'package:rencontre/features/annonces/controller/annonces_controller.dart';

class AnnonceCommentController extends GetxController {
  final AnnonceModel annonce;
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

  // ✅ Debounce likes commentaires
  final Set<String> _likingCommentIds = {};

  // ✅ Realtime commentaires
  RealtimeChannel? _commentsChannel;

  @override
  void onInit() {
    super.onInit();
    loadComments();
    _subscribeRealtime();
  }

  @override
  void onClose() {
    textCtrl.dispose();
    _commentsChannel?.unsubscribe();
    super.onClose();
  }

  // ═══════════════════════════════════════════════════════════════
  // REALTIME COMMENTAIRES
  // ═══════════════════════════════════════════════════════════════

  // ✅ Flag pour ignorer le prochain INSERT realtime (le nôtre)
  bool _ignoreNextInsert = false;

  void _subscribeRealtime() {
    _commentsChannel = _db
        .channel('comments_$annonceId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'annonce_comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'annonce_id',
            value: annonceId,
          ),
          callback: (payload) async {
            // ✅ Ignorer notre propre INSERT — déjà ajouté en optimiste
            if (_ignoreNextInsert) {
              _ignoreNextInsert = false;
              return;
            }
            // Commentaire d'un autre utilisateur → recharger
            await loadComments();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'annonce_comments',
          callback: (payload) async {
            await loadComments();
          },
        )
        .subscribe();
  }

  // ═══════════════════════════════════════════════════════════════
  // CHARGEMENT
  // ═══════════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════════
  // ENVOYER COMMENTAIRE
  // ═══════════════════════════════════════════════════════════════

  Future<void> sendComment() async {
    final texte = textCtrl.text.trim();
    if (texte.isEmpty || sending.value) return;
    final uid = _myUid;
    if (uid == null) return;

    sending.value = true;
    try {
      final profile = await _db
          .from('profiles')
          .select('name, photo_url')
          .eq('id', uid)
          .maybeSingle();

      final senderName = profile?['name'] ?? 'Utilisateur';
      final senderPhoto = profile?['photo_url'];
      final parentId =
          replyingToId.value.isNotEmpty ? replyingToId.value : null;
      final now = DateTime.now();

      // ✅ Ajout optimiste immédiat — pas de rechargement
      final optimistic = AnnonceCommentModel(
        id: 'temp_${now.millisecondsSinceEpoch}',
        annonceId: annonceId,
        userId: uid,
        userName: senderName,
        userPhotoUrl: senderPhoto,
        isAnonyme: false,
        texte: texte,
        createdAt: now,
        likes: 0,
        isLiked: false,
        parentId: parentId,
        replies: const [],
      );

      if (parentId == null) {
        // Commentaire racine → ajouter à la fin
        comments.add(optimistic);
      } else {
        // Réponse → ajouter dans les replies du parent
        final parentIdx = comments.indexWhere((c) => c.id == parentId);
        if (parentIdx != -1) {
          final parent = comments[parentIdx];
          comments[parentIdx] = parent.copyWith(
            replies: [...parent.replies, optimistic],
          );
          comments.refresh();
        }
      }

      textCtrl.clear();
      cancelReply();

      // ✅ Marquer pour ignorer notre propre INSERT realtime
      _ignoreNextInsert = true;

      // Envoyer en BDD
      await _db.from('annonce_comments').insert({
        'annonce_id': annonceId,
        'user_id': uid,
        'user_name': senderName,
        'user_photo_url': senderPhoto,
        'is_anonyme': false,
        'texte': texte,
        'parent_id': parentId,
        'liked_by': [],
        'created_at': now.toIso8601String(),
      });

      // ✅ Recharger silencieusement pour remplacer le commentaire temp_ par le vrai
      // (sans passer loading=true pour ne pas flasher)
      final data = await _db
          .from('annonce_comments')
          .select()
          .eq('annonce_id', annonceId)
          .order('created_at', ascending: true);

      final all = (data as List)
          .map((m) => AnnonceCommentModel.fromMap(m as Map<String, dynamic>,
              myUid: _myUid))
          .toList();
      final parents = all.where((c) => c.parentId == null).toList();
      final result = parents.map((parent) {
        final replies = all.where((c) => c.parentId == parent.id).toList();
        return parent.copyWith(replies: replies);
      }).toList();
      comments.value = result;

      // Notification
      if (annonce.userId != uid) {
        await _sendNotificationIfEnabled(
          toUserId: annonce.userId,
          title: '💬 Nouveau commentaire',
          body: '$senderName a commenté ton annonce : "$texte"',
          type: 'comment',
        );
      }
    } catch (e) {
      debugPrint('sendComment error: $e');
      // Rollback — retirer le commentaire optimiste
      comments.removeWhere((c) => c.id.startsWith('temp_'));
      _ignoreNextInsert = false;
      Get.snackbar('Erreur', 'Impossible d\'envoyer : $e',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF1A0A0A),
          colorText: Colors.white,
          duration: const Duration(seconds: 4));
    } finally {
      sending.value = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // LIKES COMMENTAIRES
  // ═══════════════════════════════════════════════════════════════

  Future<void> toggleLike(AnnonceCommentModel comment) async {
    final uid = _myUid;
    if (uid == null) return;
    if (_likingCommentIds.contains(comment.id)) return;
    _likingCommentIds.add(comment.id);

    // Mise à jour optimiste
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
        if (comment.userId != uid) {
          final myProfile = await _db
              .from('profiles')
              .select('name')
              .eq('id', uid)
              .maybeSingle();
          final myName = myProfile?['name'] ?? 'Quelqu\'un';
          await _sendNotificationIfEnabled(
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
    } finally {
      _likingCommentIds.remove(comment.id);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ÉPINGLER COMMENTAIRE
  // ═══════════════════════════════════════════════════════════════

  Future<void> epinglerOuDesepingler(AnnonceCommentModel comment) async {
    final uid = _myUid;
    if (uid == null || annonce.userId != uid) return;

    final isPinned = annonce.pinnedCommentId == comment.id;
    // Si déjà épinglé → désépingler, sinon épingler
    final newPinnedId = isPinned ? null : comment.id;

    if (Get.isRegistered<AnnoncesController>()) {
      await Get.find<AnnoncesController>()
          .epinglerCommentaire(annonce, newPinnedId);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SUPPRIMER
  // ═══════════════════════════════════════════════════════════════

  Future<void> deleteComment(AnnonceCommentModel comment) async {
    final uid = _myUid;
    if (uid == null) return;
    final canDelete = comment.userId == uid || annonce.userId == uid;
    if (!canDelete) return;
    try {
      await _db.from('annonce_comments').delete().eq('id', comment.id);
      // ✅ Le trigger sync reponses_count + realtime recharge
    } catch (e) {
      debugPrint('deleteComment error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════

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

  Future<void> _sendNotificationIfEnabled({
    required String toUserId,
    required String title,
    required String body,
    required String type,
  }) async {
    try {
      final myUid = _myUid;
      if (toUserId == myUid) return;

      final profile = await _db
          .from('profiles')
          .select('fcm_token, notif_messages, notif_annonces')
          .eq('id', toUserId)
          .maybeSingle();
      if (profile == null) return;

      final notifsEnabled = type == 'comment' || type == 'like_annonce'
          ? (profile['notif_annonces'] ?? true)
          : (profile['notif_messages'] ?? true);
      if (!notifsEnabled) return;

      final token = profile['fcm_token'] as String?;
      if (token == null || token.isEmpty) return;

      await _db.functions.invoke('send-notification', body: {
        'token': token,
        'title': title,
        'body': body,
        'data': {'type': type, 'annonceId': annonceId},
      });
    } catch (e) {
      debugPrint('_sendNotificationIfEnabled error: $e');
    }
  }
}
