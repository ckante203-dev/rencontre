import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/shared/models/user_model.dart';

final supabase = Supabase.instance.client;

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._();
  factory SupabaseService() => _instance;
  SupabaseService._();

  String? get currentUserId => supabase.auth.currentUser?.id;

  // ══════════════════════════════════════════════════════════════════
  // ✅ ALGORITHME EN LIGNE
  // Une personne est EN LIGNE si :
  //   - is_online = true
  //   - ET last_seen < 3 minutes
  // Sinon elle est HORS LIGNE, même si is_online=true en BDD
  // (protection contre les crashs / heartbeat manqué)
  // ══════════════════════════════════════════════════════════════════
  static bool isReallyOnline(dynamic isOnline, dynamic lastSeen) {
    if (isOnline != true) return false;
    if (lastSeen == null) return false;
    final dt = DateTime.tryParse(lastSeen.toString());
    if (dt == null) return false;
    // En ligne = last_seen il y a moins de 3 minutes
    return DateTime.now().toUtc().difference(dt.toUtc()).inMinutes < 3;
  }

  // ─── PROFILS ────────────────────────────────────────────────────

  Future<List<UserModel>> fetchProfiles({
    String? genderFilter,
    double? maxDistanceKm,
    double? myLat,
    double? myLng,
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

    // ✅ Inclure last_seen dans la query
    final data = await supabase
        .from('profiles')
        .select()
        .eq('is_suspended', false)
        .order('created_at', ascending: false);

    List<UserModel> users = (data as List)
        .map((row) => _profileToUser(row))
        .where((u) => !allExcluded.contains(u.id))
        .toList();

    if (genderFilter != null &&
        genderFilter != 'all' &&
        genderFilter != 'tout le monde') {
      users = users.where((u) {
        final g = u.gender?.toLowerCase();
        return g == genderFilter.toLowerCase() ||
            g == null ||
            g == 'non précisé' ||
            g.isEmpty;
      }).toList();
    }

    if (maxDistanceKm != null && myLat != null && myLng != null) {
      users = users.where((u) {
        if (u.latitude == null || u.longitude == null) return false;
        final dist = _distanceKm(myLat, myLng, u.latitude!, u.longitude!);
        return dist <= maxDistanceKm;
      }).toList();

      users.sort((a, b) {
        final da = _distanceKm(myLat, myLng, a.latitude ?? 0, a.longitude ?? 0);
        final db = _distanceKm(myLat, myLng, b.latitude ?? 0, b.longitude ?? 0);
        return da.compareTo(db);
      });
    }

    return users;
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = (dLat / 2) * (dLat / 2) +
        _deg2rad(lat1) * _deg2rad(lat2) * (dLon / 2) * (dLon / 2);
    return r * 2 * (a < 1 ? a : 1);
  }

  double _deg2rad(double deg) => deg * 3.141592653589793 / 180;

  Future<UserModel?> fetchMyProfile() async {
    final uid = currentUserId;
    if (uid == null) return null;
    final data =
        await supabase.from('profiles').select().eq('id', uid).maybeSingle();
    if (data == null) return null;
    return _profileToUser(data);
  }

  // ✅ setOnline met à jour is_online ET last_seen ensemble
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

  // ✅ Heartbeat — met juste à jour last_seen pour confirmer qu'on est actif
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
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', uid);
  }

  // ─── CONVERSATIONS ──────────────────────────────────────────────

  Future<String> getOrCreateConversation(String otherUserId) async {
    final uid = currentUserId!;
    final existing = await supabase
        .from('conversations')
        .select('id')
        .or('and(user1_id.eq.$uid,user2_id.eq.$otherUserId),and(user1_id.eq.$otherUserId,user2_id.eq.$uid)')
        .maybeSingle();
    if (existing != null) return existing['id'] as String;
    final created = await supabase
        .from('conversations')
        .insert({'user1_id': uid, 'user2_id': otherUserId})
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

    // ✅ Inclure last_seen dans la query des profils liés aux conversations
    final data = await supabase
        .from('conversations')
        .select('''
          id, updated_at, user1_id, user2_id,
          user1_profile:profiles!conversations_user1_id_fkey(id, name, photo_url, is_online, last_seen),
          user2_profile:profiles!conversations_user2_id_fkey(id, name, photo_url, is_online, last_seen)
        ''')
        .or('user1_id.eq.$uid,user2_id.eq.$uid')
        .order('updated_at', ascending: false);

    final filtered = (data as List).where((row) {
      final otherId = row['user1_id'] == uid
          ? row['user2_id'] as String
          : row['user1_id'] as String;
      return !allExcluded.contains(otherId);
    }).toList();

    if (filtered.isEmpty) return [];

    final convIds = filtered.map((r) => r['id'] as String).toList();

    final lastMsgsData = await supabase
        .from('messages')
        .select(
            'id, conversation_id, type, content, sender_id, created_at, status, is_read, is_opened, audio_duration')
        .inFilter('conversation_id', convIds)
        .order('created_at', ascending: false);

    final Map<String, Map<String, dynamic>> lastMsgByConv = {};
    for (final msg in (lastMsgsData as List)) {
      final cid = msg['conversation_id'] as String;
      if (!lastMsgByConv.containsKey(cid)) {
        lastMsgByConv[cid] = msg;
      }
    }

    final unreadData = await supabase
        .from('messages')
        .select('conversation_id')
        .inFilter('conversation_id', convIds)
        .neq('sender_id', uid)
        .eq('is_read', false)
        .neq('status', 'read');

    final Map<String, int> unreadByConv = {};
    for (final msg in (unreadData as List)) {
      final cid = msg['conversation_id'] as String;
      unreadByConv[cid] = (unreadByConv[cid] ?? 0) + 1;
    }

    final result = List<Map<String, dynamic>>.from(filtered);
    for (final conv in result) {
      final cid = conv['id'] as String;
      conv['_last_message'] = lastMsgByConv[cid];
      conv['_unread_count'] = unreadByConv[cid] ?? 0;
    }

    return result;
  }

  // ─── MESSAGES ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchMessages(
      String conversationId) async {
    final data = await supabase
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
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
      'expires_at': expiresAt?.toIso8601String(),
      'disappears_at': disappearsAt?.toIso8601String(),
      'status': 'sent',
      if (replyToId != null) 'reply_to_id': replyToId,
      if (snapDurationSeconds != null) 'snap_duration': snapDurationSeconds,
    });
  }

  Future<void> markMessagesAsDelivered(String conversationId) async {
    final uid = currentUserId!;
    await supabase
        .from('messages')
        .update({'status': 'delivered'})
        .eq('conversation_id', conversationId)
        .neq('sender_id', uid)
        .eq('status', 'sent');
  }

  Future<void> markMessagesAsRead(String conversationId) async {
    final uid = currentUserId!;
    await supabase
        .from('messages')
        .update({'status': 'read', 'is_read': true})
        .eq('conversation_id', conversationId)
        .neq('sender_id', uid)
        .neq('status', 'read');
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

  UserModel _profileToUser(Map<String, dynamic> row) {
    // ✅ isOnline calculé avec la règle is_online + last_seen < 3 min
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
      followersCount: row['followers_count'] ?? 0,
      followingCount: row['following_count'] ?? 0,
      matchesCount: row['matches_count'] ?? 0,
      taille: row['taille'] as int?,
      poids: row['poids'] as int?,
      morphologie: row['morphologie'] as String?,
      lieuRencontre: row['lieu_rencontre'] as String?,
    );
  }
}
