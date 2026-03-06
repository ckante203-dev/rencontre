import 'dart:io';
import 'package:flutter/material.dart';
import 'package:rencontre/core/services/notification_service.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';

import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/features/chat/model/message_model.dart';

// ══════════════════════════════════════════════════════════════════
//  CHAT LIST CONTROLLER
// ══════════════════════════════════════════════════════════════════

class ChatListController extends GetxController {
  final _service = SupabaseService();
  final RxList<ConversationModel> conversations = <ConversationModel>[].obs;
  final RxBool isLoading = true.obs;
  RealtimeChannel? _channel;

  @override
  void onInit() {
    super.onInit();
    loadConversations();
    _subscribeToConversations();
  }

  Future<void> loadConversations() async {
    isLoading.value = true;
    try {
      final uid = _service.currentUserId!;
      final data = await _service.fetchConversations();

      conversations.value = data.map((row) {
        final isUser1 = row['user1_id'] == uid;
        final otherProfile = isUser1
            ? _extractProfile(row, 'user2')
            : _extractProfile(row, 'user1');

        final msgs = (row['messages'] as List? ?? []);
        msgs.sort((a, b) =>
          (b['created_at'] as String).compareTo(a['created_at'] as String));
        final lastMsg = msgs.isNotEmpty ? msgs.first : null;
        final unread = msgs.where((m) =>
          m['sender_id'] != uid && m['status'] != 'read').length;

        return ConversationModel(
          id: row['id'],
          userId: otherProfile['id'] ?? '',
          userName: otherProfile['name'] ?? 'Utilisateur',
          userPhotoUrl: otherProfile['photo_url'],
          isOnline: otherProfile['is_online'] ?? false,
          unreadCount: unread,
          lastActivity: row['updated_at'] != null
              ? DateTime.tryParse(row['updated_at']) : null,
          lastMessage: lastMsg != null ? MessageModel(
            id: lastMsg['id'] ?? '',
            senderId: lastMsg['sender_id'] ?? '',
            text: lastMsg['content'],
            type: _parseType(lastMsg['type']),
            status: MessageStatus.sent,
            createdAt: DateTime.tryParse(lastMsg['created_at'] ?? '') ?? DateTime.now(),
          ) : null,
        );
      }).toList();

      conversations.sort((a, b) =>
        (b.lastActivity ?? DateTime(0)).compareTo(a.lastActivity ?? DateTime(0)));

    } catch (e) {
      debugPrint('ChatListController error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // Écoute les nouvelles conversations en temps réel
  void _subscribeToConversations() {
    final uid = _service.currentUserId;
    if (uid == null) return;
    _channel = Supabase.instance.client
        .channel('conversations:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (_) => loadConversations(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (_) => loadConversations(),
        )
        .subscribe();
  }

  void openConversation(ConversationModel conv) {
    // Reset unread localement
    final idx = conversations.indexWhere((c) => c.id == conv.id);
    if (idx != -1) {
      conversations[idx] = ConversationModel(
        id: conv.id, userId: conv.userId, userName: conv.userName,
        userPhotoUrl: conv.userPhotoUrl, isOnline: conv.isOnline,
        unreadCount: 0, lastActivity: conv.lastActivity,
        lastMessage: conv.lastMessage,
      );
    }
    Get.toNamed('/chat/conversation', arguments: conv);
  }

  Map<String, dynamic> _extractProfile(Map<String, dynamic> row, String prefix) {
    final key = '${prefix}_profile';
    if (row[key] is Map) return row[key] as Map<String, dynamic>;
    return {'id': row['${prefix}_id'], 'name': 'Utilisateur', 'photo_url': null, 'is_online': false};
  }

  MessageType _parseType(String? t) {
    switch (t) {
      case 'image': return MessageType.image;
      case 'snap': return MessageType.snap;
      case 'audio': return MessageType.audio;
      case 'location': return MessageType.location;
      default: return MessageType.text;
    }
  }

  @override
  void onClose() {
    _channel?.unsubscribe();
    super.onClose();
  }
}

// ══════════════════════════════════════════════════════════════════
//  CONVERSATION CONTROLLER
// ══════════════════════════════════════════════════════════════════

class ConversationController extends GetxController {
  final _service = SupabaseService();

  // ✅ Reçoit la conversation via init() au lieu de Get.arguments
  late ConversationModel conversation;

  final RxList<MessageModel> messages = <MessageModel>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isRecording = false.obs;
  final RxBool showAttachMenu = false.obs;
  final textController = TextEditingController();
  final RxString inputText = ''.obs;
  RealtimeChannel? _channel;

  // Audio
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _audioPlayer = FlutterSoundPlayer();
  final RxInt recordingSeconds = 0.obs;
  String? _recordingPath;

  // Media
  final _imagePicker = ImagePicker();

  // ✅ Appelé depuis la vue après Get.put()
  void init(ConversationModel conv) {
    conversation = conv;
    textController.addListener(() => inputText.value = textController.text);
    _loadMessages();
    _subscribeToMessages();
    _service.markMessagesAsRead(conversation.id);
  }

  // ─── CHARGER MESSAGES ─────────────────────────────────────────

  Future<void> _loadMessages() async {
    isLoading.value = true;
    try {
      final data = await _service.fetchMessages(conversation.id);
      messages.value = data.map((row) => _rowToMessage(row)).toList();
    } catch (e) {
      debugPrint('Load messages error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // ─── REALTIME ─────────────────────────────────────────────────

  void _subscribeToMessages() {
    _channel = _service.listenToMessages(conversation.id, (record) {
      final newMsg = MessageModel(
        id: record['id'] ?? '',
        senderId: record['sender_id'] ?? '',
        text: record['content'],
        mediaUrl: record['media_url'],
        type: _parseType(record['type']),
        status: _parseStatus(record['status']),
        createdAt: DateTime.tryParse(record['created_at'] ?? '') ?? DateTime.now(),
        isOpened: record['is_opened'] ?? false,
        audioDurationSec: record['audio_duration'],
      );
      // Évite doublons et remplace le message optimiste
      messages.removeWhere((m) => m.id.startsWith('temp_') &&
        m.text == newMsg.text && m.senderId == newMsg.senderId);
      if (!messages.any((m) => m.id == newMsg.id)) {
        messages.add(newMsg);
      }
      // Notification si message d'un autre utilisateur
      if (newMsg.senderId != myId) {
        NotificationService.showMessageNotification(
          senderName: conversation.userName,
          message: newMsg.text ?? '📷 Photo',
          senderPhoto: conversation.userPhotoUrl,
          conversationId: conversation.id,
        );
      }
      // Marque comme lu si on est dans la conv, sinon delivered
      _service.markMessagesAsRead(conversation.id);
    });
    // Marque les messages existants comme delivered au chargement
    _service.markMessagesAsDelivered(conversation.id);
  }

  // ─── ENVOYER TEXTE ────────────────────────────────────────────

  Future<void> sendText() async {
    final text = textController.text.trim();
    if (text.isEmpty) return;
    textController.clear();

    // Optimistic UI
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    messages.add(MessageModel(
      id: tempId,
      senderId: _service.currentUserId!,
      text: text,
      type: MessageType.text,
      status: MessageStatus.sending,
      createdAt: DateTime.now(),
    ));

    try {
      await _service.sendMessage(
        conversationId: conversation.id,
        content: text,
        type: 'text',
      );
    } catch (_) {
      // En cas d'erreur, retire le message optimiste
      messages.removeWhere((m) => m.id == tempId);
      Get.snackbar('Erreur', 'Message non envoyé',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF13131A),
        colorText: Colors.white);
    }
  }

  // ─── SNAP ─────────────────────────────────────────────────────

  Future<void> sendSnap() async {
    showAttachMenu.value = false;
    try {
      await _service.sendMessage(
        conversationId: conversation.id,
        content: '📸 Snap',
        type: 'snap',
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
      );
    } catch (_) {}
  }

  Future<void> openSnap(MessageModel msg) async {
    final idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx != -1) {
      messages[idx] = MessageModel(
        id: msg.id, senderId: msg.senderId, text: msg.text,
        type: msg.type, status: msg.status, createdAt: msg.createdAt,
        isOpened: true,
        expiresAt: DateTime.now().add(const Duration(seconds: 10)),
      );
    }
    await Supabase.instance.client
        .from('messages').update({'is_opened': true}).eq('id', msg.id);
  }

  void toggleAttachMenu() => showAttachMenu.toggle();

  // ─── AUDIO ────────────────────────────────────────────────────

  Future<void> startRecording() async {
    // Permission gérée par permission_handler
    
    final dir = await getTemporaryDirectory();
    _recordingPath = '\${dir.path}/audio_\${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.openRecorder();
    await _recorder.startRecorder(toFile: _recordingPath!, codec: Codec.aacADTS);
    isRecording.value = true;
    recordingSeconds.value = 0;
    // Compteur secondes
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!isRecording.value) return false;
      recordingSeconds.value++;
      return recordingSeconds.value < 120; // max 2 min
    });
  }

  Future<void> stopRecording() async {
    if (!isRecording.value) return;
    final path = await _recorder.stopRecorder();
    isRecording.value = false;
    if (path == null || recordingSeconds.value < 1) return;

    await _sendAudio(File(path), recordingSeconds.value);
  }

  void cancelRecording() async {
    await _recorder.stopRecorder();
    isRecording.value = false;
    recordingSeconds.value = 0;
  }

  Future<void> _sendAudio(File file, int duration) async {
    final uid = _service.currentUserId!;
    final path = 'audio/$uid/${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await Supabase.instance.client.storage
          .from('snaps').upload(path, file,
          fileOptions: const FileOptions(upsert: true, contentType: 'audio/m4a'));
      final url = Supabase.instance.client.storage.from('snaps').getPublicUrl(path);
      await _service.sendMessage(
        conversationId: conversation.id,
        content: '🎤 Message vocal',
        type: 'audio',
        mediaUrl: url,
        audioDuration: duration,
      );
    } catch (e) {
      Get.snackbar('Erreur', "Impossible d'envoyer le vocal",
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF13131A), colorText: Colors.white);
    }
  }

  Future<void> playAudio(String url) async {
    await _audioPlayer.openPlayer();
    await _audioPlayer.startPlayer(fromURI: url, codec: Codec.aacADTS);
  }

  void toggleRecording() {
    if (isRecording.value) {
      stopRecording();
    } else {
      startRecording();
    }
  }

  // ─── PHOTO ────────────────────────────────────────────────────

  Future<void> envoyerPhoto({bool camera = false}) async {
    showAttachMenu.value = false;
    final picked = await _imagePicker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1080, maxHeight: 1080, imageQuality: 80,
    );
    if (picked == null) return;

    final uid = _service.currentUserId!;
    final path = 'photos/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      final file = File(picked.path);
      await Supabase.instance.client.storage
          .from('snaps').upload(path, file,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'));
      final url = Supabase.instance.client.storage.from('snaps').getPublicUrl(path);
      await _service.sendMessage(
        conversationId: conversation.id,
        content: '📷 Photo',
        type: 'image',
        mediaUrl: url,
      );
    } catch (e) {
      Get.snackbar('Erreur', "Impossible d'envoyer la photo",
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF13131A), colorText: Colors.white);
    }
  }

  // ─── LOCALISATION ────────────────────────────────────────────

  Future<void> envoyerLocalisation() async {
    showAttachMenu.value = false;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        Get.snackbar('GPS désactivé', 'Active la localisation',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A), colorText: Colors.white);
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      final position = await Geolocator.getCurrentPosition();
      final lat = position.latitude.toStringAsFixed(6);
      final lng = position.longitude.toStringAsFixed(6);
      final mapsUrl = 'https://maps.google.com/?q=$lat,$lng';

      await _service.sendMessage(
        conversationId: conversation.id,
        content: mapsUrl,
        type: 'location',
      );
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de récupérer la position',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF13131A), colorText: Colors.white);
    }
  }

  String get myId => _service.currentUserId ?? '';

  // ─── HELPERS ──────────────────────────────────────────────────

  MessageModel _rowToMessage(Map<String, dynamic> row) => MessageModel(
    id: row['id'] ?? '',
    senderId: row['sender_id'] ?? '',
    text: row['content'],
    mediaUrl: row['media_url'],
    type: _parseType(row['type']),
    status: _parseStatus(row['status']),
    createdAt: DateTime.tryParse(row['created_at'] ?? '') ?? DateTime.now(),
    isOpened: row['is_opened'] ?? false,
    audioDurationSec: row['audio_duration'],
    expiresAt: row['expires_at'] != null
        ? DateTime.tryParse(row['expires_at']) : null,
  );

  MessageType _parseType(String? t) {
    switch (t) {
      case 'image': return MessageType.image;
      case 'snap': return MessageType.snap;
      case 'audio': return MessageType.audio;
      case 'location': return MessageType.location;
      default: return MessageType.text;
    }
  }

  MessageStatus _parseStatus(String? s) {
    switch (s) {
      case 'sending': return MessageStatus.sending;
      case 'delivered': return MessageStatus.delivered;
      case 'read': return MessageStatus.read;
      default: return MessageStatus.sent;
    }
  }

  @override
  void onClose() {
    _channel?.unsubscribe();
    _recorder.closeRecorder();
    _audioPlayer.closePlayer();
    textController.dispose();
    super.onClose();
  }
}