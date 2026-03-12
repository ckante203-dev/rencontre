import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/shared/models/user_model.dart';

final supabase = Supabase.instance.client;

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._();
  factory SupabaseService() => _instance;
  SupabaseService._();

  String? get currentUserId => supabase.auth.currentUser?.id;

  // ─── PROFILS ───────────────────────────────────────────────────

  // Charger tous les profils selon l'orientation
  Future<List<UserModel>> fetchProfiles({
    String? genderFilter, // filtre genre cible
    String? lookingFor, // orientation de l'utilisateur connecté
    double? maxDistanceKm, // filtre distance
    double? myLat,
    double? myLng,
  }) async {
    final uid = currentUserId;

    final data = await supabase
        .from('profiles')
        .select()
        .neq('id', uid ?? '')
        .order('created_at', ascending: false);

    List<UserModel> users =
        (data as List).map((row) => _profileToUser(row)).toList();

    // ✅ Filtre genre côté client (évite les problèmes de type Postgrest)
    if (genderFilter != null && genderFilter != 'all') {
      users = users
          .where((u) => u.gender?.toLowerCase() == genderFilter.toLowerCase())
          .toList();
    }

    // ✅ Filtre distance côté client (si coords disponibles)
    if (maxDistanceKm != null && myLat != null && myLng != null) {
      users = users.where((u) {
        if (u.latitude == null || u.longitude == null) return false;
        final dist = _distanceKm(myLat, myLng, u.latitude!, u.longitude!);
        return dist <= maxDistanceKm;
      }).toList();

      // Trier par distance
      users.sort((a, b) {
        final da = _distanceKm(myLat, myLng, a.latitude ?? 0, a.longitude ?? 0);
        final db = _distanceKm(myLat, myLng, b.latitude ?? 0, b.longitude ?? 0);
        return da.compareTo(db);
      });
    }

    return users;
  }

  // Distance Haversine simplifiée en km
  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = (dLat / 2) * (dLat / 2) +
        _deg2rad(lat1) * _deg2rad(lat2) * (dLon / 2) * (dLon / 2);
    return r * 2 * (a < 1 ? a : 1);
  }

  double _deg2rad(double deg) => deg * 3.141592653589793 / 180;

  // Charger son propre profil
  Future<UserModel?> fetchMyProfile() async {
    final uid = currentUserId;
    if (uid == null) return null;
    final data =
        await supabase.from('profiles').select().eq('id', uid).maybeSingle();
    if (data == null) return null;
    return _profileToUser(data);
  }

  // Mettre à jour is_online
  Future<void> setOnline(bool isOnline) async {
    final uid = currentUserId;
    if (uid == null) return;
    await supabase.from('profiles').update({
      'is_online': isOnline,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', uid);
  }

  // Mettre à jour la position
  Future<void> updateLocation(double lat, double lng) async {
    final uid = currentUserId;
    if (uid == null) return;
    await supabase.from('profiles').update({
      'latitude': lat,
      'longitude': lng,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', uid);
  }

  // ─── CONVERSATIONS ─────────────────────────────────────────────

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
        .insert({
          'user1_id': uid,
          'user2_id': otherUserId,
        })
        .select('id')
        .single();

    return created['id'] as String;
  }

  // ✅ FIX BADGE : on ne ramène que les messages non lus reçus (sender_id != moi)
  Future<List<Map<String, dynamic>>> fetchConversations() async {
    final uid = currentUserId;
    if (uid == null) return [];

    final data = await supabase
        .from('conversations')
        .select('''
          id,
          updated_at,
          user1_id,
          user2_id,
          user1_profile:profiles!conversations_user1_id_fkey(id, name, photo_url, is_online),
          user2_profile:profiles!conversations_user2_id_fkey(id, name, photo_url, is_online),
          messages(id, type, content, sender_id, created_at, status, is_read)
        ''')
        .or('user1_id.eq.$uid,user2_id.eq.$uid')
        .order('updated_at', ascending: false);

    final result = List<Map<String, dynamic>>.from(data);

    // ✅ FIX BADGE : exclure ses propres messages + vérifier is_read ET status
    // La BDD a is_read (boolean) et status (text 'sent'/'delivered'/'read')
    // Un message est "non lu" seulement si : reçu (pas envoyé par moi)
    //   ET is_read == false ET status != 'read'
    for (final conv in result) {
      final msgs = (conv['messages'] as List? ?? []);
      final unreadMsgs = msgs.where((m) {
        if (m['sender_id'] == uid) return false; // jamais compter mes envois
        final isRead = m['is_read'] == true || m['status'] == 'read';
        return !isRead;
      }).toList();
      conv['_unread_count'] = unreadMsgs.length;
    }

    return result;
  }

  // ─── MESSAGES ──────────────────────────────────────────────────

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
    String? replyToId, // ✅ prêt pour plus tard
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
      'status': 'sent',
      if (replyToId != null) 'reply_to_id': replyToId,
    });

    await supabase.from('conversations').update({
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', conversationId);
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
        .update({'status': 'read', 'is_read': true}) // ✅ les deux champs
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

  // ─── HELPER ────────────────────────────────────────────────────

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
      lookingFor: row['looking_for'], // ✅ orientation cible
      isOnline: row['is_online'] ?? false,
      followersCount: row['followers_count'] ?? 0,
      followingCount: row['following_count'] ?? 0,
      matchesCount: row['matches_count'] ?? 0,
    );
  }
}
