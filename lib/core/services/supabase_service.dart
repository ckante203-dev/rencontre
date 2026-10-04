import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/features/chat/model/message_model.dart';

final supabase = Supabase.instance.client;

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._();
  factory SupabaseService() => _instance;
  SupabaseService._();

  String? get currentUserId => supabase.auth.currentUser?.id;

  static bool isReallyOnline(dynamic isOnline, dynamic lastSeen) {
    if (lastSeen == null) return false;
    final dt = DateTime.tryParse(lastSeen.toString());
    if (dt == null) return false;
    return DateTime.now().toUtc().difference(dt.toUtc()).inMinutes < 30;
  }

  // ─── PROFILS ────────────────────────────────────────────────────

  Future<List<UserModel>> fetchProfiles({
    String? genderFilter,
    double? maxDistanceKm,
    double? myLat,
    double? myLng,
    int limit = 30,
    int offset = 0,
  }) async {
    final uid = currentUserId;
    if (uid == null) return [];

    final myData = await supabase
        .from('profiles')
        .select('blocked_users')
        .eq('id', uid)
        .maybeSingle();
    final myBlockedIds = List<String>.from(myData?['blocked_users'] ?? []);

    final blockedMeData = await supabase
        .from('profiles')
        .select('id')
        .contains('blocked_users', [uid]);
    final blockedMeIds =
        (blockedMeData as List).map((r) => r['id'] as String).toList();

    final allExcluded = <String>{uid, ...myBlockedIds, ...blockedMeIds};

    // ✅ Pagination : on ne charge plus toute la table d'un coup.
    var query = supabase.from('profiles').select().eq('is_suspended', false);

    final data = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    var rows = List<Map<String, dynamic>>.from(data as List);

    // ⚡ Profils boostés : chargés à part (la pagination par date de
    // création ne les ramènerait pas forcément) et placés en tête.
    if (offset == 0) {
      try {
        final boostes = await supabase
            .from('profiles')
            .select()
            .eq('is_suspended', false)
            .gt('boost_jusqua', DateTime.now().toUtc().toIso8601String())
            .limit(50);
        final ids = rows.map((r) => r['id']).toSet();
        rows = [
          ...List<Map<String, dynamic>>.from(boostes)
              .where((r) => !ids.contains(r['id'])),
          ...rows,
        ];
      } catch (_) {
        // Colonne absente (script 000015 pas appliqué) : liste normale.
      }
    }

    List<UserModel> users = rows
        .map((row) => profileToUser(row))
        .where((u) => !allExcluded.contains(u.id))
        .toList();

    if (genderFilter != null) {
      final normalizedFilter = genderFilter.toLowerCase().trim();
      const showAllValues = {'tout', 'tous', 'all', 'tout le monde'};
      if (!showAllValues.contains(normalizedFilter)) {
        users = users.where((u) {
          final g = u.gender?.toLowerCase().trim();
          return g == normalizedFilter;
        }).toList();
      }
    }

    if (myLat != null && myLng != null) {
      for (int i = 0; i < users.length; i++) {
        final u = users[i];
        if (u.latitude != null && u.longitude != null) {
          final dist = _distanceKm(myLat, myLng, u.latitude!, u.longitude!);
          users[i] = u.copyWith(distanceMeters: dist * 1000);
        }
      }
      if (maxDistanceKm != null) {
        users = users.where((u) {
          if (u.distanceMeters == null) return false;
          return u.distanceMeters! <= maxDistanceKm * 1000;
        }).toList();
      }
    }

    return users;
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    // ✅ Haversine complète (sin/cos/atan2 manquaient : distances ~100x
    // trop petites).
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _deg2rad(double deg) => deg * 3.141592653589793 / 180;

  Future<UserModel?> fetchMyProfile() async {
    final uid = currentUserId;
    if (uid == null) return null;
    final data =
        await supabase.from('profiles').select().eq('id', uid).maybeSingle();
    if (data == null) return null;
    return profileToUser(data);
  }

  Future<void> setOnline(bool isOnline) async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      await supabase.from('profiles').update({
        'is_online': isOnline,
        'last_seen': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
    } catch (_) {}
  }

  Future<void> heartbeat() async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      await supabase.from('profiles').update({
        'is_online': true,
        'last_seen': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
    } catch (_) {}
  }

  Future<void> updateLocation(double lat, double lng) async {
    final uid = currentUserId;
    if (uid == null) return;
    await supabase.from('profiles').update({
      'latitude': lat,
      'longitude': lng,
      // ✅ FIX — horodatage envoyé en UTC (timestamptz)
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', uid);
  }

  // ─── MATCH ──────────────────────────────────────────────────────

  // ✅ NOUVEAU — vérifie si deux utilisateurs sont en match, en
  // interrogeant directement la table `matches` (normalisée
  // user1_id < user2_id, comme dans LikeController._createMatch).
  // Volontairement indépendant de LikeController (pas de dépendance
  // GetX ici) : cette méthode doit pouvoir être appelée depuis
  // n'importe quel contexte (widget non-Get, service, etc).
  Future<bool> _hasMatch(String uidA, String uidB) async {
    final u1 = uidA.compareTo(uidB) < 0 ? uidA : uidB;
    final u2 = uidA.compareTo(uidB) < 0 ? uidB : uidA;
    try {
      final row = await supabase
          .from('matches')
          .select('user1_id')
          .eq('user1_id', u1)
          .eq('user2_id', u2)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }

  // ─── CONVERSATIONS ──────────────────────────────────────────────

  // ✅ MODIFIÉ — point d'entrée UNIQUE pour démarrer/retrouver une
  // conversation. Centralise la règle : sans match, la conversation
  // est créée en 'pending' (demande de message, façon Instagram) au
  // lieu d'être bloquée ou traitée comme une conversation normale.
  // Tout endroit de l'app qui veut ouvrir un chat DOIT passer par
  // cette méthode plutôt que de dupliquer la logique de recherche/
  // création (voir _ReplyBar dans story_screen.dart et
  // discover_feed_viewer.dart, corrigés pour l'utiliser aussi).
  Future<String> getOrCreateConversation(String otherUserId) async {
    final uid = currentUserId!;
    // ✅ Garde-fou — on ne doit jamais pouvoir se conversation avec soi-même,
    // même si un bug d'affichage amont a montré son propre profil par erreur.
    if (uid == otherUserId) {
      throw Exception('Impossible de démarrer une conversation avec soi-même');
    }
    final existing = await supabase
        .from('conversations')
        .select('id')
        .or('and(user1_id.eq.$uid,user2_id.eq.$otherUserId),and(user1_id.eq.$otherUserId,user2_id.eq.$uid)')
        .maybeSingle();
    if (existing != null) return existing['id'] as String;

    final isMatch = await _hasMatch(uid, otherUserId);

    final created = await supabase
        .from('conversations')
        .insert({
          'user1_id': uid,
          'user2_id': otherUserId,
          // ✅ Sans match : la conversation démarre en attente. Elle
          // ne remontera pas dans la liste normale du destinataire
          // tant qu'il n'a pas répondu (voir fetchConversations /
          // fetchMessageRequests) — et sendMessage() la fait passer
          // à 'accepted' dès que le destinataire répond.
          'request_status': isMatch ? 'accepted' : 'pending',
          'initiated_by': uid,
        })
        .select('id')
        .single();
    return created['id'] as String;
  }

  Future<List<Map<String, dynamic>>> fetchConversations() async {
    final uid = currentUserId;
    if (uid == null) return [];

    final myData = await supabase
        .from('profiles')
        .select('blocked_users')
        .eq('id', uid)
        .maybeSingle();
    final myBlockedIds = List<String>.from(myData?['blocked_users'] ?? []);

    final blockedMeData = await supabase
        .from('profiles')
        .select('id')
        .contains('blocked_users', [uid]);
    final blockedMeIds =
        (blockedMeData as List).map((r) => r['id'] as String).toList();

    final allExcluded = <String>{...myBlockedIds, ...blockedMeIds};

    Future<List<dynamic>> conversationsAvec(String colonnesEnPlus) async =>
        await supabase
            .from('conversations')
            .select('''
          id, updated_at, user1_id, user2_id, request_status, initiated_by,$colonnesEnPlus
          user1_profile:profiles!conversations_user1_id_fkey(id, name, photo_url, is_online, last_seen),
          user2_profile:profiles!conversations_user2_id_fkey(id, name, photo_url, is_online, last_seen)
        ''')
            .or('user1_id.eq.$uid,user2_id.eq.$uid')
            .order('updated_at', ascending: false);

    // 🔥 Série : colonnes ajoutées par 20261002000017_flammes.sql. Tant que
    // le script n'est pas exécuté, la liste se charge sans elles.
    List<dynamic> data;
    try {
      data = await conversationsAvec(' flamme_compte, flamme_dernier_jour,');
    } on PostgrestException {
      data = await conversationsAvec('');
    }

    final filtered = data.where((row) {
      final otherId = row['user1_id'] == uid
          ? row['user2_id'] as String
          : row['user1_id'] as String;
      if (allExcluded.contains(otherId)) return false;

      // ✅ Messages directs : les conversations « pending » (sans match,
      // pas encore de réponse) s'affichent aussi chez le destinataire.
      // Avant, elles lui étaient cachées et aucun écran ne les montrait.
      return true;
    }).toList();

    if (filtered.isEmpty) return [];

    final convIds = filtered.map((r) => r['id'] as String).toList();

    // ✅ FIX — on ne télécharge plus TOUS les messages de TOUTES les
    // conversations (plafonné à 1000 lignes par PostgREST : les vieilles
    // conversations perdaient leur dernier message / leurs non-lus).
    // Par conversation : 1 requête limitée au dernier message (hors
    // messages éphémères disparus) + 1 requête de comptage des non-lus.
    // Forme des données retournées inchangée.
    const fullCols =
        'id, conversation_id, type, content, sender_id, created_at, status, is_read, is_opened, audio_duration';
    // ✅ Ne bloque plus la liste des conversations si is_read n'existe pas encore
    const fallbackCols =
        'id, conversation_id, type, content, sender_id, created_at, status, audio_duration';
    final notDisappeared = _notDisappearedFilter();

    Future<Map<String, dynamic>?> lastMessageOf(String cid) async {
      Future<Map<String, dynamic>?> query(String cols) async {
        final rows = await supabase
            .from('messages')
            .select(cols)
            .eq('conversation_id', cid)
            .or(notDisappeared)
            .order('created_at', ascending: false)
            .limit(1);
        return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
      }

      try {
        return await query(fullCols);
      } catch (_) {
        return await query(fallbackCols);
      }
    }

    Future<int> unreadCountOf(String cid) async {
      try {
        return await supabase
            .from('messages')
            .count(CountOption.exact)
            .eq('conversation_id', cid)
            .neq('sender_id', uid)
            .eq('is_read', false)
            .neq('status', 'read');
      } catch (_) {
        return 0;
      }
    }

    final lastMsgs = await Future.wait(convIds.map(lastMessageOf));
    final unreadCounts = await Future.wait(convIds.map(unreadCountOf));

    final Map<String, Map<String, dynamic>> lastMsgByConv = {};
    final Map<String, int> unreadByConv = {};
    for (int i = 0; i < convIds.length; i++) {
      final msg = lastMsgs[i];
      if (msg != null) lastMsgByConv[convIds[i]] = msg;
      unreadByConv[convIds[i]] = unreadCounts[i];
    }

    final result = List<Map<String, dynamic>>.from(filtered);
    for (final conv in result) {
      final cid = conv['id'] as String;
      conv['_last_message'] = lastMsgByConv[cid];
      conv['_unread_count'] = unreadByConv[cid] ?? 0;
    }

    return result;
  }

  // ✅ NOUVEAU — les "demandes de message" reçues : conversations
  // en attente qu'un AUTRE utilisateur a démarrées avec moi (je ne
  // les ai pas encore acceptées en répondant). C'est la liste à
  // afficher dans l'onglet/écran "Demandes" séparé, avec son propre
  // badge — voir la discussion sur l'écran de liste des conversations.
  Future<List<Map<String, dynamic>>> fetchMessageRequests() async {
    final uid = currentUserId;
    if (uid == null) return [];

    final myData = await supabase
        .from('profiles')
        .select('blocked_users')
        .eq('id', uid)
        .maybeSingle();
    final myBlockedIds = List<String>.from(myData?['blocked_users'] ?? []);

    final data = await supabase
        .from('conversations')
        .select('''
          id, updated_at, user1_id, user2_id, request_status, initiated_by,
          user1_profile:profiles!conversations_user1_id_fkey(id, name, photo_url, is_online, last_seen),
          user2_profile:profiles!conversations_user2_id_fkey(id, name, photo_url, is_online, last_seen)
        ''')
        .or('user1_id.eq.$uid,user2_id.eq.$uid')
        .eq('request_status', 'pending')
        .neq('initiated_by', uid)
        .order('updated_at', ascending: false);

    final filtered = (data as List).where((row) {
      final otherId = row['user1_id'] == uid
          ? row['user2_id'] as String
          : row['user1_id'] as String;
      return !myBlockedIds.contains(otherId);
    }).toList();

    if (filtered.isEmpty) return [];

    final convIds = filtered.map((r) => r['id'] as String).toList();
    final lastMsgsData = await supabase
        .from('messages')
        .select('conversation_id, type, content, sender_id, created_at')
        .inFilter('conversation_id', convIds)
        .order('created_at', ascending: false);

    final Map<String, Map<String, dynamic>> lastMsgByConv = {};
    for (final msg in (lastMsgsData as List)) {
      final cid = msg['conversation_id'] as String;
      if (!lastMsgByConv.containsKey(cid)) {
        lastMsgByConv[cid] = msg;
      }
    }

    final result = List<Map<String, dynamic>>.from(filtered);
    for (final conv in result) {
      conv['_last_message'] = lastMsgByConv[conv['id']];
    }
    return result;
  }

  // ✅ NOUVEAU — nombre de demandes de message en attente, pour le
  // badge de notification (même esprit que UnreadMessagesController).
  Future<int> countPendingMessageRequests() async {
    final uid = currentUserId;
    if (uid == null) return 0;
    try {
      final data = await supabase
          .from('conversations')
          .select('id')
          .or('user1_id.eq.$uid,user2_id.eq.$uid')
          .eq('request_status', 'pending')
          .neq('initiated_by', uid);
      return (data as List).length;
    } catch (_) {
      return 0;
    }
  }

  // ✅ NOUVEAU — j'accepte explicitement une demande de message
  // (bouton "Accepter" dans l'écran de demandes), sans forcément
  // avoir encore répondu par un message.
  Future<void> acceptMessageRequest(String conversationId) async {
    try {
      await supabase
          .from('conversations')
          .update({'request_status': 'accepted'}).eq('id', conversationId);
    } catch (_) {}
  }

  // ─── MESSAGES ───────────────────────────────────────────────────

  // ✅ Filtre PostgREST excluant les messages expirés (déjà masqués dans
  // l'écran de conversation) :
  //   (disappears_at vide OU futur) ET (read_at vide OU lu il y a < 24h)
  // Un seul paramètre `or` combinant les 4 cas valides.
  String _notDisappearedFilter() {
    final now = DateTime.now().toUtc();
    final nowUtc = now.toIso8601String();
    final limiteLecture =
        now.subtract(MessageModel.dureeApresLecture).toIso8601String();
    const dNull = 'disappears_at.is.null';
    final dFutur = 'disappears_at.gt."$nowUtc"';
    const rNull = 'read_at.is.null';
    final rRecent = 'read_at.gt."$limiteLecture"';
    return 'and($dNull,$rNull),and($dNull,$rRecent),'
        'and($dFutur,$rNull),and($dFutur,$rRecent)';
  }

  Future<List<Map<String, dynamic>>> fetchMessages(
      String conversationId) async {
    final data = await supabase
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .or(_notDisappearedFilter()) // ✅ FIX — messages disparus exclus
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> sendMessage({
    required String conversationId,
    required String content,
    String type = 'text',
    String? mediaUrl,
    int? audioDuration,
    DateTime? expiresAt,
    DateTime? disappearsAt,
    String? replyToId,
    int? snapDurationSeconds,
  }) async {
    final uid = currentUserId!;
    await supabase.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': uid,
      'type': type,
      'content': content,
      'media_url': mediaUrl,
      'audio_duration': audioDuration,
      // ✅ FIX — horodatages envoyés en UTC (timestamptz)
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      'disappears_at': disappearsAt?.toUtc().toIso8601String(),
      'status': 'sent',
      if (replyToId != null) 'reply_to_id': replyToId,
      if (snapDurationSeconds != null) 'snap_duration': snapDurationSeconds,
    });

    // ✅ FIX — la liste des conversations est triée par updated_at :
    // on le met à jour à chaque envoi (comme _PreviewSheet._envoyer).
    // Ne doit jamais faire échouer l'envoi du message lui-même.
    try {
      await supabase.from('conversations').update({
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', conversationId);
    } catch (_) {}

    // ✅ Si LE DESTINATAIRE (pas l'initiateur) répond à une
    // conversation encore en attente, elle devient acceptée.
    await maybePromoteMessageRequest(conversationId);
  }

  // ✅ NOUVEAU — extrait de sendMessage() pour être réutilisable par
  // tout endroit qui insère un message manuellement plutôt que via
  // sendMessage() (ex: réponse à une story, qui a besoin de champs
  // supplémentaires comme story_id/story_preview_url non gérés par
  // la signature générique de sendMessage). Si LE DESTINATAIRE (pas
  // l'initiateur) vient d'écrire dans une conversation encore en
  // attente, elle passe à 'accepted' et rejoint la liste normale des
  // deux côtés — c'est ainsi qu'une "demande de message" est
  // implicitement acceptée, en plus du bouton explicite
  // acceptMessageRequest().
  Future<void> maybePromoteMessageRequest(String conversationId) async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      final conv = await supabase
          .from('conversations')
          .select('initiated_by, request_status')
          .eq('id', conversationId)
          .maybeSingle();
      if (conv != null &&
          conv['request_status'] == 'pending' &&
          conv['initiated_by'] != uid) {
        await supabase
            .from('conversations')
            .update({'request_status': 'accepted'}).eq('id', conversationId);
      }
    } catch (_) {
      // ✅ Ne doit jamais bloquer l'envoi du message lui-même.
    }
  }

  Future<void> markMessagesAsDelivered(String conversationId) async {
    // ✅ FIX — appelé aussi depuis la liste en arrière-plan : ne doit
    // jamais lever d'exception (ex : déconnexion entre-temps).
    final uid = currentUserId;
    if (uid == null) return;
    try {
      await supabase
          .from('messages')
          .update({'status': 'delivered'})
          .eq('conversation_id', conversationId)
          .neq('sender_id', uid)
          .eq('status', 'sent');
    } catch (e) {
      // ✅ Ne doit jamais bloquer l'ouverture de la conversation
    }
  }

  Future<void> markMessagesAsRead(String conversationId) async {
    final uid = currentUserId!;
    try {
      await supabase
          .from('messages')
          .update({'status': 'read', 'is_read': true})
          .eq('conversation_id', conversationId)
          .neq('sender_id', uid)
          .neq('status', 'read');
    } catch (e) {
      // ✅ Ne doit jamais bloquer l'ouverture de la conversation ni l'envoi
    }
  }

  RealtimeChannel listenToMessages(
    String conversationId,
    void Function(Map<String, dynamic>) onMessage,
  ) {
    return supabase
        .channel('messages:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) => onMessage(payload.newRecord),
        )
        .subscribe();
  }

  // ─── HELPER ─────────────────────────────────────────────────────

  int _calcAge(dynamic birthdate) {
    if (birthdate == null) return 18;
    try {
      DateTime birth;
      if (birthdate is String) {
        if (birthdate.contains('/')) {
          final parts = birthdate.split('/');
          birth = DateTime(
              int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
        } else {
          birth = DateTime.parse(birthdate);
        }
      } else {
        return 18;
      }
      final now = DateTime.now();
      int age = now.year - birth.year;
      if (now.month < birth.month ||
          (now.month == birth.month && now.day < birth.day)) {
        age--;
      }
      return age < 0 ? 18 : age;
    } catch (_) {
      return 18;
    }
  }

  UserModel profileToUser(Map<String, dynamic> row) {
    final online = isReallyOnline(row['is_online'], row['last_seen']);
    return UserModel(
      id: row['id'] ?? '',
      name: row['name'] ?? 'Utilisateur',
      age: _calcAge(row['birthdate'] ?? row['birth_date']),
      bio: row['bio'],
      photoUrl: row['photo_url'],
      photoUrls: List<String>.from(row['photo_urls'] ?? []),
      interests: List<String>.from(row['interests'] ?? []),
      latitude: row['latitude']?.toDouble(),
      longitude: row['longitude']?.toDouble(),
      gender: row['gender'],
      lookingFor: row['looking_for'],
      isOnline: online,
      lastSeen: row['last_seen'] != null
          ? DateTime.tryParse(row['last_seen'].toString())
          : null,
      createdAt: row['created_at'] != null
          ? DateTime.tryParse(row['created_at'].toString())
          : null,
      followersCount: row['followers_count'] ?? 0,
      followingCount: row['following_count'] ?? 0,
      matchesCount: row['matches_count'] ?? 0,
      taille: row['taille'] as int?,
      poids: row['poids'] as int?,
      morphologie: row['morphologie'] as String?,
      lieuRencontre: row['lieu_rencontre'] as String?,
      isPremium: row['is_premium'] ?? false,
      showBirthdate: row['show_birthdate'] ?? true,
      showDistance: row['show_distance'] ?? true,
      boostJusqua: row['boost_jusqua'] != null
          ? DateTime.tryParse(row['boost_jusqua'].toString())?.toLocal()
          : null,
      dispoTexte: row['dispo_texte'] as String?,
      dispoJusqua: row['dispo_jusqua'] != null
          ? DateTime.tryParse(row['dispo_jusqua'].toString())?.toLocal()
          : null,
    );
  }
}
