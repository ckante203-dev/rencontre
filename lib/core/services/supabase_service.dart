import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/shared/models/user_model.dart';

final supabase = Supabase.instance.client;

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._();
  factory SupabaseService() => _instance;
  SupabaseService._();

  String? get currentUserId => supabase.auth.currentUser?.id;

  // ─── PROFILS ───────────────────────────────────────────────────

  // Charger tous les profils sauf le sien
  Future<List<UserModel>> fetchProfiles() async {
    final uid = currentUserId;
    final data = await supabase
        .from('profiles')
        .select()
        .neq('id', uid ?? '')
        //.eq('onboarding_complete', true)
        .order('created_at', ascending: false);

    return (data as List).map((row) => _profileToUser(row)).toList();
  }

  // Charger son propre profil
  Future<UserModel?> fetchMyProfile() async {
    final uid = currentUserId;
    if (uid == null) return null;
    final data = await supabase
        .from('profiles')
        .select()
        .eq('id', uid)
        .maybeSingle();
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

  // Récupérer ou créer une conversation entre 2 users
  Future<String> getOrCreateConversation(String otherUserId) async {
    final uid = currentUserId!;

    // Cherche conversation existante
    final existing = await supabase
        .from('conversations')
        .select('id')
        .or('and(user1_id.eq.$uid,user2_id.eq.$otherUserId),and(user1_id.eq.$otherUserId,user2_id.eq.$uid)')
        .maybeSingle();

    if (existing != null) return existing['id'] as String;

    // Crée une nouvelle conversation
    final created = await supabase.from('conversations').insert({
      'user1_id': uid,
      'user2_id': otherUserId,
    }).select('id').single();

    return created['id'] as String;
  }

  // Lister toutes les conversations avec le dernier message
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
          messages(id, type, content, sender_id, created_at, status)
        ''')
        .or('user1_id.eq.$uid,user2_id.eq.$uid')
        .order('updated_at', ascending: false);

    return List<Map<String, dynamic>>.from(data);
  }

  // ─── MESSAGES ──────────────────────────────────────────────────

  // Charger les messages d'une conversation
  Future<List<Map<String, dynamic>>> fetchMessages(String conversationId) async {
    final data = await supabase
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(data);
  }

  // Envoyer un message texte
  Future<void> sendMessage({
    required String conversationId,
    required String content,
    String type = 'text',
    String? mediaUrl,
    int? audioDuration,
    DateTime? expiresAt,
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
    });

    // Met à jour updated_at de la conversation
    await supabase.from('conversations').update({
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', conversationId);
  }

  // Marquer les messages comme délivrés (reçus mais pas lus)
  Future<void> markMessagesAsDelivered(String conversationId) async {
    final uid = currentUserId!;
    await supabase
        .from('messages')
        .update({'status': 'delivered'})
        .eq('conversation_id', conversationId)
        .neq('sender_id', uid)
        .eq('status', 'sent');
  }

  // Marquer les messages comme lus
  Future<void> markMessagesAsRead(String conversationId) async {
    final uid = currentUserId!;
    await supabase
        .from('messages')
        .update({'status': 'read'})
        .eq('conversation_id', conversationId)
        .neq('sender_id', uid)
        .neq('status', 'read');
  }

  // Écouter les nouveaux messages en temps réel
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

  // Calcule l'âge depuis la date de naissance
  int _calcAge(dynamic birthdate) {
    if (birthdate == null) return 18;
    try {
      DateTime birth;
      if (birthdate is String) {
        // Format JJ/MM/AAAA ou ISO
        if (birthdate.contains('/')) {
          final parts = birthdate.split('/');
          birth = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
        } else {
          birth = DateTime.parse(birthdate);
        }
      } else {
        return 18;
      }
      final now = DateTime.now();
      int age = now.year - birth.year;
      if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) {
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
      isOnline: row['is_online'] ?? false,
      followersCount: row['followers_count'] ?? 0,
      followingCount: row['following_count'] ?? 0,
      matchesCount: row['matches_count'] ?? 0,
    );
  }
}