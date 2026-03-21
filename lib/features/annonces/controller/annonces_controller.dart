// lib/features/annonces/controller/annonces_controller.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/features/annonces/model/annonce_model.dart';

class AnnoncesController extends GetxController {
  final _sb = Supabase.instance.client;

  final RxList<AnnonceModel> annonces = <AnnonceModel>[].obs;
  final RxList<AnnonceModel> mesAnnonces = <AnnonceModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool isLoadingMesAnnonces = false.obs;
  final RxBool hasMore = true.obs;
  final RxString filterCategorie = 'toutes'.obs;
  final RxString searchQuery = ''.obs;
  final RxBool isBoosting = false.obs;
  final RxInt unseenCount = 0.obs;
  DateTime? _lastSeenAt;

  // ✅ Pagination
  static const _pageSize = 20;
  int _offset = 0;

  // ✅ Realtime
  RealtimeChannel? _realtimeAnnonces;
  RealtimeChannel? _realtimeReactions;

  // ✅ Debounce likes
  final Set<String> _reactingIds = {};

  // ✅ Emojis réactions disponibles
  static const List<String> reactions = ['❤️', '😂', '😮', '😢', '👏', '🔥'];

  final categories = ['toutes', 'rencontre', 'amitie', 'sortie', 'voyage'];

  @override
  void onInit() {
    super.onInit();
    loadAnnonces();
    _subscribeRealtime();
  }

  @override
  void onClose() {
    _realtimeAnnonces?.unsubscribe();
    _realtimeReactions?.unsubscribe();
    super.onClose();
  }

  // ═══════════════════════════════════════════════════════════════
  // REALTIME
  // ═══════════════════════════════════════════════════════════════

  void _subscribeRealtime() {
    // ✅ Nouvelles annonces en temps réel
    _realtimeAnnonces = _sb
        .channel('annonces_feed_rt')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'annonces',
          callback: (payload) async {
            await loadAnnonces(silent: true);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'annonces',
          callback: (payload) {
            final updated = payload.newRecord;
            final id = updated['id'] as String?;
            if (id == null) return;
            final idx = annonces.indexWhere((a) => a.id == id);
            if (idx != -1) {
              annonces[idx] = annonces[idx].copyWith(
                likes: updated['likes_count'] ?? annonces[idx].likes,
                reponsesCount:
                    updated['reponses_count'] ?? annonces[idx].reponsesCount,
                viewsCount: updated['views_count'] ?? annonces[idx].viewsCount,
              );
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'annonces',
          callback: (payload) {
            final id = payload.oldRecord['id'] as String?;
            if (id != null) {
              annonces.removeWhere((a) => a.id == id);
              mesAnnonces.removeWhere((a) => a.id == id);
            }
          },
        )
        .subscribe();

    // ✅ Réactions en temps réel
    _realtimeReactions = _sb
        .channel('annonce_reactions_rt')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'annonce_reactions',
          callback: (payload) {
            final annonceId = payload.newRecord['annonce_id'] as String?;
            if (annonceId == null) return;
            _refreshReactionCounts(annonceId);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'annonce_reactions',
          callback: (payload) {
            final annonceId = payload.oldRecord['annonce_id'] as String?;
            if (annonceId == null) return;
            _refreshReactionCounts(annonceId);
          },
        )
        .subscribe();
  }

  // ✅ Refresh les compteurs de réactions d'une annonce spécifique
  Future<void> _refreshReactionCounts(String annonceId) async {
    try {
      final uid = _sb.auth.currentUser?.id;
      final data = await _sb
          .from('annonce_reactions')
          .select('reaction, user_id')
          .eq('annonce_id', annonceId);

      final counts = <String, int>{};
      String myReaction = '';
      for (final r in (data as List)) {
        final emoji = r['reaction'] as String;
        counts[emoji] = (counts[emoji] ?? 0) + 1;
        if (r['user_id'] == uid) myReaction = emoji;
      }

      final totalLikes = counts.values.fold(0, (s, v) => s + v);

      final idx = annonces.indexWhere((a) => a.id == annonceId);
      if (idx != -1) {
        annonces[idx] = annonces[idx].copyWith(
          likes: totalLikes,
          isLiked: myReaction.isNotEmpty,
          myReaction: myReaction,
          reactionCounts: counts,
        );
      }
    } catch (e) {
      debugPrint('_refreshReactionCounts error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // CHARGEMENT
  // ═══════════════════════════════════════════════════════════════

  List<AnnonceModel> get filtered {
    var list = filterCategorie.value == 'toutes'
        ? annonces.toList()
        : annonces.where((a) => a.categorie == filterCategorie.value).toList();

    // ✅ Filtre recherche
    if (searchQuery.value.isNotEmpty) {
      final q = searchQuery.value.toLowerCase();
      list = list
          .where((a) =>
              a.titre.toLowerCase().contains(q) ||
              a.description.toLowerCase().contains(q) ||
              (a.ville?.toLowerCase().contains(q) ?? false) ||
              a.userName.toLowerCase().contains(q))
          .toList();
    }

    return list;
  }

  Future<void> loadAnnonces({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    _offset = 0;
    hasMore.value = true;
    try {
      final uid = _sb.auth.currentUser?.id;

      final data = await _sb
          .from('annonces')
          .select('*, profiles(name, photo_url, age)')
          .order('is_boosted', ascending: false)
          .order('created_at', ascending: false)
          .range(0, _pageSize - 1);

      // ✅ Réactions de l'utilisateur
      Map<String, String> myReactions = {};
      Map<String, Map<String, int>> allReactionCounts = {};

      if (uid != null) {
        final reactData = await _sb
            .from('annonce_reactions')
            .select('annonce_id, reaction, user_id');

        for (final r in (reactData as List)) {
          final aId = r['annonce_id'] as String;
          final emoji = r['reaction'] as String;
          if (r['user_id'] == uid) myReactions[aId] = emoji;
          allReactionCounts[aId] ??= {};
          allReactionCounts[aId]![emoji] =
              (allReactionCounts[aId]![emoji] ?? 0) + 1;
        }
      }

      annonces.value = (data as List).map((row) {
        final aId = row['id'] as String;
        return _rowToModel(
          row,
          myReaction: myReactions[aId] ?? '',
          reactionCounts: allReactionCounts[aId] ?? {},
          uid: uid,
        );
      }).toList();

      _offset = annonces.length;
      hasMore.value = annonces.length >= _pageSize;
      _updateUnseenCount();
    } catch (e) {
      debugPrint('loadAnnonces error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // ✅ Infinite scroll
  Future<void> loadMore() async {
    if (isLoadingMore.value || !hasMore.value) return;
    isLoadingMore.value = true;
    try {
      final uid = _sb.auth.currentUser?.id;
      final data = await _sb
          .from('annonces')
          .select('*, profiles(name, photo_url, age)')
          .order('is_boosted', ascending: false)
          .order('created_at', ascending: false)
          .range(_offset, _offset + _pageSize - 1);

      if ((data as List).isEmpty) {
        hasMore.value = false;
        return;
      }

      final ids = data.map((r) => r['id'].toString()).toList();
      Map<String, String> myReactions = {};
      Map<String, Map<String, int>> allReactionCounts = {};

      if (uid != null) {
        final reactData = await _sb
            .from('annonce_reactions')
            .select('annonce_id, reaction, user_id')
            .inFilter('annonce_id', ids);

        for (final r in (reactData as List)) {
          final aId = r['annonce_id'] as String;
          final emoji = r['reaction'] as String;
          if (r['user_id'] == uid) myReactions[aId] = emoji;
          allReactionCounts[aId] ??= {};
          allReactionCounts[aId]![emoji] =
              (allReactionCounts[aId]![emoji] ?? 0) + 1;
        }
      }

      final newItems = data.map((row) {
        final aId = row['id'] as String;
        return _rowToModel(
          row,
          myReaction: myReactions[aId] ?? '',
          reactionCounts: allReactionCounts[aId] ?? {},
          uid: uid,
        );
      }).toList();

      annonces.addAll(newItems);
      _offset += newItems.length;
      hasMore.value = newItems.length >= _pageSize;
    } catch (e) {
      debugPrint('loadMore error: $e');
    } finally {
      isLoadingMore.value = false;
    }
  }

  // ✅ Mes annonces
  Future<void> loadMesAnnonces() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    isLoadingMesAnnonces.value = true;
    try {
      final data = await _sb
          .from('annonces')
          .select('*, profiles(name, photo_url, age)')
          .eq('user_id', uid)
          .order('created_at', ascending: false);

      mesAnnonces.value = (data as List)
          .map((row) =>
              _rowToModel(row, myReaction: '', reactionCounts: {}, uid: uid))
          .toList();
    } catch (e) {
      debugPrint('loadMesAnnonces error: $e');
    } finally {
      isLoadingMesAnnonces.value = false;
    }
  }

  AnnonceModel _rowToModel(
    Map<String, dynamic> row, {
    required String myReaction,
    required Map<String, int> reactionCounts,
    String? uid,
  }) {
    final p = row['profiles'] as Map<String, dynamic>?;
    final isAnon = row['is_anonyme'] ?? false;
    final totalLikes = reactionCounts.values.fold(0, (s, v) => s + v);
    final viewedBy = List<String>.from(row['viewed_by'] ?? []);

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
      likes: totalLikes > 0 ? totalLikes : (row['likes_count'] ?? 0),
      isLiked: myReaction.isNotEmpty,
      myReaction: myReaction,
      reactionCounts: reactionCounts,
      isBoosted: row['is_boosted'] ?? false,
      boostedUntil: row['boosted_until'] != null
          ? DateTime.parse(row['boosted_until'])
          : null,
      isAnonyme: isAnon,
      mediaUrl: row['media_url'],
      isVideo: row['is_video'] ?? false,
      reponsesCount: row['reponses_count'] ?? 0,
      commentsEnabled: row['comments_enabled'] ?? true,
      viewsCount: row['views_count'] ?? 0,
      isViewed: uid != null && viewedBy.contains(uid),
      pinnedCommentId: row['pinned_comment_id'],
    );
  }

  // ✅ Refresh silencieux — ne vide pas la liste existante
  // Utilisé quand on revient sur la page (données déjà en mémoire)
  Future<void> refreshSilent() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      final data = await _sb
          .from('annonces')
          .select('*, profiles(name, photo_url, age)')
          .order('is_boosted', ascending: false)
          .order('created_at', ascending: false)
          .range(0, _pageSize - 1);

      Map<String, String> myReactions = {};
      Map<String, Map<String, int>> allReactionCounts = {};

      if (uid != null) {
        final reactData = await _sb
            .from('annonce_reactions')
            .select('annonce_id, reaction, user_id');
        for (final r in (reactData as List)) {
          final aId = r['annonce_id'] as String;
          final emoji = r['reaction'] as String;
          if (r['user_id'] == uid) myReactions[aId] = emoji;
          allReactionCounts[aId] ??= {};
          allReactionCounts[aId]![emoji] =
              (allReactionCounts[aId]![emoji] ?? 0) + 1;
        }
      }

      final newList = (data as List).map((row) {
        final aId = row['id'] as String;
        return _rowToModel(row,
            myReaction: myReactions[aId] ?? '',
            reactionCounts: allReactionCounts[aId] ?? {},
            uid: uid);
      }).toList();

      // ✅ Mise à jour douce — seulement si des changements existent
      if (newList.length != annonces.length) {
        annonces.value = newList;
        _offset = newList.length;
      } else {
        // Mettre à jour uniquement les compteurs (likes, vues, réactions)
        for (int i = 0; i < newList.length; i++) {
          if (i < annonces.length) {
            final old = annonces[i];
            final fresh = newList[i];
            if (old.likes != fresh.likes ||
                old.reponsesCount != fresh.reponsesCount ||
                old.viewsCount != fresh.viewsCount) {
              annonces[i] = fresh;
            }
          }
        }
      }
      _updateUnseenCount();
    } catch (e) {
      debugPrint('refreshSilent error: $e');
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

  // ═══════════════════════════════════════════════════════════════
  // RÉACTIONS
  // ═══════════════════════════════════════════════════════════════

  // ✅ Réaction — remplace toggleLike
  Future<void> toggleReaction(AnnonceModel annonce, String emoji) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    if (_reactingIds.contains(annonce.id)) return;
    _reactingIds.add(annonce.id);

    final idx = annonces.indexWhere((a) => a.id == annonce.id);
    if (idx < 0) {
      _reactingIds.remove(annonce.id);
      return;
    }

    final wasMyReaction = annonce.myReaction == emoji;
    final newCounts = Map<String, int>.from(annonce.reactionCounts);

    if (wasMyReaction) {
      // Retirer la réaction
      newCounts[emoji] = (newCounts[emoji] ?? 1) - 1;
      if ((newCounts[emoji] ?? 0) <= 0) newCounts.remove(emoji);
      final newTotal = newCounts.values.fold(0, (s, v) => s + v);
      annonces[idx] = annonce.copyWith(
        likes: newTotal,
        isLiked: false,
        myReaction: '',
        reactionCounts: newCounts,
      );
    } else {
      // Changer ou ajouter la réaction
      if (annonce.myReaction.isNotEmpty) {
        // Retirer l'ancienne
        final old = annonce.myReaction;
        newCounts[old] = (newCounts[old] ?? 1) - 1;
        if ((newCounts[old] ?? 0) <= 0) newCounts.remove(old);
      }
      newCounts[emoji] = (newCounts[emoji] ?? 0) + 1;
      final newTotal = newCounts.values.fold(0, (s, v) => s + v);
      annonces[idx] = annonce.copyWith(
        likes: newTotal,
        isLiked: true,
        myReaction: emoji,
        reactionCounts: newCounts,
      );
    }

    try {
      if (wasMyReaction) {
        await _sb
            .from('annonce_reactions')
            .delete()
            .eq('annonce_id', annonce.id)
            .eq('user_id', uid);
      } else {
        // Upsert — remplace l'ancienne réaction ou en crée une
        await _sb.from('annonce_reactions').upsert({
          'annonce_id': annonce.id,
          'user_id': uid,
          'reaction': emoji,
        }, onConflict: 'annonce_id,user_id');
      }

      // Notifier si nouveau like
      if (!wasMyReaction && annonce.userId != uid) {
        _notifyReaction(annonce: annonce, emoji: emoji, uid: uid);
      }
    } catch (e) {
      debugPrint('toggleReaction error: $e');
      if (idx < annonces.length) annonces[idx] = annonce; // rollback
    } finally {
      _reactingIds.remove(annonce.id);
    }
  }

  // ✅ Rétrocompatibilité avec toggleLike existant
  Future<void> toggleLike(AnnonceModel annonce) async {
    await toggleReaction(annonce, '❤️');
  }

  void _notifyReaction({
    required AnnonceModel annonce,
    required String emoji,
    required String uid,
  }) {
    _sb
        .from('profiles')
        .select('name')
        .eq('id', uid)
        .maybeSingle()
        .then((myProfile) async {
      final myName = myProfile?['name'] ?? 'Quelqu\'un';
      final ownerProfile = await _sb
          .from('profiles')
          .select('fcm_token, notif_annonces')
          .eq('id', annonce.userId)
          .maybeSingle();
      if (ownerProfile == null) return;
      if (!(ownerProfile['notif_annonces'] ?? true)) return;
      final token = ownerProfile['fcm_token'] as String?;
      if (token == null || token.isEmpty) return;
      await _sb.functions.invoke('send-notification', body: {
        'token': token,
        'title': '$emoji $myName a réagi à ton annonce',
        'body': '"${annonce.titre}"',
        'data': {'type': 'reaction_annonce', 'annonceId': annonce.id},
      });
    }).catchError((e) => debugPrint('_notifyReaction error: $e'));
  }

  // ═══════════════════════════════════════════════════════════════
  // VUES
  // ═══════════════════════════════════════════════════════════════

  // ✅ Marquer une annonce comme vue
  Future<void> marquerVue(AnnonceModel annonce) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null || annonce.isViewed || annonce.userId == uid) return;

    // Mise à jour optimiste locale
    final idx = annonces.indexWhere((a) => a.id == annonce.id);
    if (idx != -1) {
      annonces[idx] = annonces[idx].copyWith(
        viewsCount: annonces[idx].viewsCount + 1,
        isViewed: true,
      );
    }

    try {
      await _sb.rpc('increment_annonce_view', params: {
        'p_annonce_id': annonce.id,
        'p_user_id': uid,
      });
    } catch (e) {
      debugPrint('marquerVue error (non bloquant): $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // MODIFIER UNE ANNONCE
  // ═══════════════════════════════════════════════════════════════

  Future<bool> modifierAnnonce({
    required String id,
    required String titre,
    required String description,
    String? ville,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      await _sb
          .from('annonces')
          .update({
            'titre': titre,
            'description': description,
            'ville': ville,
          })
          .eq('id', id)
          .eq('user_id', uid);

      // Mettre à jour localement
      final idx = annonces.indexWhere((a) => a.id == id);
      if (idx != -1) {
        final a = annonces[idx];
        annonces[idx] = AnnonceModel(
          id: a.id,
          userId: a.userId,
          userName: a.userName,
          userPhotoUrl: a.userPhotoUrl,
          userAge: a.userAge,
          titre: titre,
          description: description,
          categorie: a.categorie,
          ville: ville,
          createdAt: a.createdAt,
          likes: a.likes,
          isLiked: a.isLiked,
          myReaction: a.myReaction,
          reactionCounts: a.reactionCounts,
          isBoosted: a.isBoosted,
          boostedUntil: a.boostedUntil,
          isAnonyme: a.isAnonyme,
          mediaUrl: a.mediaUrl,
          isVideo: a.isVideo,
          reponsesCount: a.reponsesCount,
          commentsEnabled: a.commentsEnabled,
          viewsCount: a.viewsCount,
          isViewed: a.isViewed,
          pinnedCommentId: a.pinnedCommentId,
        );
      }
      await loadMesAnnonces();
      return true;
    } catch (e) {
      debugPrint('modifierAnnonce error: $e');
      Get.snackbar('Erreur', 'Impossible de modifier : $e',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.red.shade900,
          colorText: Colors.white);
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ÉPINGLER COMMENTAIRE
  // ═══════════════════════════════════════════════════════════════

  Future<void> epinglerCommentaire(
      AnnonceModel annonce, String? commentId) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null || annonce.userId != uid) return;
    try {
      await _sb
          .from('annonces')
          .update({'pinned_comment_id': commentId}).eq('id', annonce.id);

      final idx = annonces.indexWhere((a) => a.id == annonce.id);
      if (idx != -1) {
        annonces[idx] = annonces[idx].copyWith(
          pinnedCommentId: commentId,
          clearPinnedComment: commentId == null,
        );
      }
      Get.snackbar(
        commentId != null ? '📌 Commentaire épinglé' : 'Épingle retirée',
        '',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF1A1228),
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      debugPrint('epinglerCommentaire error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // PARTAGER EN MESSAGE PRIVÉ
  // ═══════════════════════════════════════════════════════════════

  Future<void> partagerAnnonce(
      AnnonceModel annonce, String targetUserId) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      // Récupérer ou créer la conversation
      final existing = await _sb
          .from('conversations')
          .select('id')
          .or('and(user1_id.eq.$uid,user2_id.eq.$targetUserId),and(user1_id.eq.$targetUserId,user2_id.eq.$uid)')
          .maybeSingle();

      String convId;
      if (existing != null) {
        convId = existing['id'] as String;
      } else {
        final created = await _sb
            .from('conversations')
            .insert({'user1_id': uid, 'user2_id': targetUserId})
            .select('id')
            .single();
        convId = created['id'] as String;
      }

      // Envoyer l'annonce comme message
      final shareText =
          '📢 *${annonce.titre}*\n${annonce.description.length > 100 ? annonce.description.substring(0, 100) + '...' : annonce.description}';

      await _sb.from('messages').insert({
        'conversation_id': convId,
        'sender_id': uid,
        'type': 'text',
        'content': shareText,
        'status': 'sent',
        'created_at': DateTime.now().toIso8601String(),
      });

      await _sb.from('conversations').update(
          {'updated_at': DateTime.now().toIso8601String()}).eq('id', convId);

      Get.snackbar('✅ Annonce partagée', 'Message envoyé avec succès',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF1A1228),
          colorText: Colors.white,
          duration: const Duration(seconds: 2));
    } catch (e) {
      debugPrint('partagerAnnonce error: $e');
      Get.snackbar('Erreur', 'Impossible de partager',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.red.shade900,
          colorText: Colors.white);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // PUBLICATION
  // ═══════════════════════════════════════════════════════════════

  Future<String?> _uploadMedia(XFile file, bool isVideo) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final bytes = await file.readAsBytes();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final nameLower = file.name.toLowerCase();
      String ext, contentType, bucket;

      if (isVideo) {
        bucket = 'annonces-videos';
        ext = nameLower.endsWith('.mov') ? 'mov' : 'mp4';
        contentType =
            nameLower.endsWith('.mov') ? 'video/quicktime' : 'video/mp4';
      } else {
        bucket = 'annonces-images';
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
      await _sb.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
      return _sb.storage.from(bucket).getPublicUrl(path);
    } catch (e) {
      debugPrint('_uploadMedia error: $e');
      Get.snackbar('Erreur upload', 'Impossible d\'uploader : $e',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.red.shade900,
          colorText: Colors.white,
          duration: const Duration(seconds: 5));
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
        'views_count': 0,
        'viewed_by': [],
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
      Get.snackbar('Erreur', 'Publication échouée : $e',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.red.shade900,
          colorText: Colors.white,
          duration: const Duration(seconds: 5));
      return false;
    }
  }

  // ✅ Suppression avec nettoyage du bucket
  Future<void> supprimerAnnonce(String id) async {
    try {
      final row = await _sb
          .from('annonces')
          .select('media_url, is_video, user_id')
          .eq('id', id)
          .maybeSingle();

      await _sb.from('annonces').delete().eq('id', id);
      annonces.removeWhere((a) => a.id == id);
      mesAnnonces.removeWhere((a) => a.id == id);

      if (row != null && row['media_url'] != null) {
        try {
          final url = row['media_url'] as String;
          final bucket = (row['is_video'] ?? false)
              ? 'annonces-videos'
              : 'annonces-images';
          final uri = Uri.parse(url);
          final segments = uri.pathSegments;
          final fileIdx = segments.indexOf(bucket);
          if (fileIdx != -1 && fileIdx + 1 < segments.length) {
            final filePath = segments.sublist(fileIdx + 1).join('/');
            await _sb.storage.from(bucket).remove([filePath]);
          }
        } catch (e) {
          debugPrint('Suppression media bucket error: $e');
        }
      }
    } catch (e) {
      debugPrint('supprimerAnnonce error: $e');
    }
  }

  // ✅ Signalement fonctionnel
  Future<void> signalerAnnonce(String annonceId, String reason) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _sb.from('reports').insert({
        'reporter_id': uid,
        'reported_id': annonceId,
        'reason': reason,
        'type': 'annonce',
        'created_at': DateTime.now().toIso8601String(),
      });
      Get.snackbar(
          'Signalement envoyé', 'Merci, nous allons examiner cette annonce.',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF1A1228),
          colorText: Colors.white,
          duration: const Duration(seconds: 3));
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        Get.snackbar('Déjà signalé', 'Tu as déjà signalé cette annonce.',
            snackPosition: SnackPosition.TOP,
            backgroundColor: const Color(0xFF1A1228),
            colorText: Colors.white);
      }
    } catch (e) {
      debugPrint('signalerAnnonce error: $e');
    }
  }

  // ✅ Boost
  Future<void> boosterAnnonce(AnnonceModel annonce) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null || uid != annonce.userId) return;
    if (annonce.isBoosted &&
        annonce.boostedUntil != null &&
        DateTime.now().isBefore(annonce.boostedUntil!)) {
      Get.snackbar('Déjà boostée', 'Cette annonce est déjà boostée.',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF1A1228),
          colorText: Colors.white);
      return;
    }
    isBoosting.value = true;
    try {
      final until = DateTime.now().add(const Duration(hours: 24));
      await _sb.from('annonces').update({
        'is_boosted': true,
        'boosted_until': until.toIso8601String(),
      }).eq('id', annonce.id);
      await loadAnnonces();
      Get.snackbar(
          '⚡ Annonce boostée !', 'Visible en tête de liste pendant 24h',
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
          '⚡ Profil boosté !', 'Tu apparais en premier pendant 30 minutes',
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
