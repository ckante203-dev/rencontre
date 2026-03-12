import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rencontre/core/services/notification_service.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:rencontre/core/theme/app_theme.dart';

// ══════════════════════════════════════════════════════════════════
//  ENUMS FILTRES
// ══════════════════════════════════════════════════════════════════

enum ChatFilter { all, unread, online, nearby, media }

// ══════════════════════════════════════════════════════════════════
//  CHAT LIST CONTROLLER
// ══════════════════════════════════════════════════════════════════

class ChatListController extends GetxController {
  final _service = SupabaseService();
  final RxList<ConversationModel> conversations = <ConversationModel>[].obs;
  final RxBool isLoading = true.obs;
  final Rx<ChatFilter> activeFilter = ChatFilter.all.obs;
  RealtimeChannel? _channel;

  final RxSet<String> pinnedIds = <String>{}.obs;

  int get totalUnread => conversations.fold(0, (sum, c) => sum + c.unreadCount);

  List<ConversationModel> get filteredConversations {
    switch (activeFilter.value) {
      case ChatFilter.unread:
        return conversations.where((c) => c.unreadCount > 0).toList();
      case ChatFilter.online:
        return conversations.where((c) => c.isOnline).toList();
      case ChatFilter.nearby:
        final cutoff = DateTime.now().subtract(const Duration(hours: 1));
        return conversations
            .where((c) =>
                c.lastActivity != null && c.lastActivity!.isAfter(cutoff))
            .toList();
      case ChatFilter.media:
        return conversations
            .where((c) =>
                c.lastMessage != null &&
                (c.lastMessage!.type == MessageType.image ||
                    c.lastMessage!.type == MessageType.snap))
            .toList();
      case ChatFilter.all:
      default:
        return conversations.toList();
    }
  }

  void setFilter(ChatFilter f) => activeFilter.value = f;

  @override
  void onInit() {
    super.onInit();
    loadConversations();
    _subscribeToMessages();
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

        final unread = (row['_unread_count'] as int?) ??
            msgs
                .where((m) => m['sender_id'] != uid && m['status'] != 'read')
                .length;

        return ConversationModel(
          id: row['id'],
          userId: otherProfile['id'] ?? '',
          userName: otherProfile['name'] ?? 'Utilisateur',
          userPhotoUrl: otherProfile['photo_url'],
          isOnline: otherProfile['is_online'] ?? false,
          unreadCount: unread,
          lastActivity: row['updated_at'] != null
              ? DateTime.tryParse(row['updated_at'])
              : null,
          isPinned: pinnedIds.contains(row['id']),
          lastMessage: lastMsg != null
              ? MessageModel(
                  id: lastMsg['id'] ?? '',
                  senderId: lastMsg['sender_id'] ?? '',
                  text: lastMsg['content'],
                  type: _parseType(lastMsg['type']),
                  status: MessageStatus.sent,
                  createdAt: DateTime.tryParse(lastMsg['created_at'] ?? '') ??
                      DateTime.now(),
                )
              : null,
        );
      }).toList();

      _sortConversations();
    } catch (e) {
      debugPrint('ChatListController error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void _sortConversations() {
    conversations.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return (b.lastActivity ?? DateTime(0))
          .compareTo(a.lastActivity ?? DateTime(0));
    });
  }

  void togglePin(ConversationModel conv) {
    final idx = conversations.indexWhere((c) => c.id == conv.id);
    if (idx == -1) return;
    final nowPinned = !conv.isPinned;
    if (nowPinned) {
      pinnedIds.add(conv.id);
    } else {
      pinnedIds.remove(conv.id);
    }
    conversations[idx] = ConversationModel(
      id: conv.id,
      userId: conv.userId,
      userName: conv.userName,
      userPhotoUrl: conv.userPhotoUrl,
      isOnline: conv.isOnline,
      lastMessage: conv.lastMessage,
      unreadCount: conv.unreadCount,
      lastActivity: conv.lastActivity,
      isPinned: nowPinned,
    );
    _sortConversations();
  }

  void _subscribeToMessages() {
    final uid = _service.currentUserId;
    if (uid == null) return;

    _channel = Supabase.instance.client
        .channel('chatlist:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            final record = payload.newRecord;
            final senderId = record['sender_id'] as String?;
            final convId = record['conversation_id'] as String?;
            if (convId == null) return;

            final isMine = senderId == uid;
            final isConvCurrentlyOpen =
                Get.isRegistered<ConversationController>(tag: convId);

            final idx = conversations.indexWhere((c) => c.id == convId);
            if (idx != -1) {
              final c = conversations[idx];
              if (!isMine && !isConvCurrentlyOpen) {
                await NotificationService.showMessageNotification(
                  senderName: c.userName,
                  message: _getMessagePreview(record),
                  senderPhoto: c.userPhotoUrl,
                  conversationId: convId,
                );
              }
              conversations[idx] = ConversationModel(
                id: c.id,
                userId: c.userId,
                userName: c.userName,
                userPhotoUrl: c.userPhotoUrl,
                isOnline: c.isOnline,
                unreadCount: (!isMine && !isConvCurrentlyOpen)
                    ? c.unreadCount + 1
                    : c.unreadCount,
                lastActivity: DateTime.now(),
                lastMessage: MessageModel(
                  id: record['id'] ?? '',
                  senderId: senderId ?? '',
                  text: record['content'],
                  type: _parseType(record['type']),
                  status: MessageStatus.sent,
                  createdAt: DateTime.now(),
                ),
              );
              _sortConversations();
            } else {
              await loadConversations();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'conversations',
          callback: (_) => loadConversations(),
        )
        .subscribe();
  }

  String _getMessagePreview(Map<String, dynamic> record) {
    // Si c'est une réponse story, afficher "📸 Story" dans la liste
    if (record['story_id'] != null) return '📸 Story';
    switch (record['type'] as String? ?? 'text') {
      case 'image':
        return '📷 Photo';
      case 'audio':
        return '🎤 Message vocal';
      case 'snap':
        return '📸 Snap';
      case 'location':
        return '📍 Localisation';
      default:
        return record['content'] as String? ?? '';
    }
  }

  void openConversation(ConversationModel conv) {
    final idx = conversations.indexWhere((c) => c.id == conv.id);
    if (idx != -1) {
      conversations[idx] = ConversationModel(
        id: conv.id,
        userId: conv.userId,
        userName: conv.userName,
        userPhotoUrl: conv.userPhotoUrl,
        isOnline: conv.isOnline,
        unreadCount: 0,
        lastActivity: conv.lastActivity,
        lastMessage: conv.lastMessage,
      );
    }
    NotificationService.clearConversationNotifications(conv.id);
    Get.toNamed('/chat/conversation', arguments: conv);
  }

  void toggleReadStatus(ConversationModel conv) {
    final idx = conversations.indexWhere((c) => c.id == conv.id);
    if (idx == -1) return;
    final c = conversations[idx];
    conversations[idx] = ConversationModel(
      id: c.id,
      userId: c.userId,
      userName: c.userName,
      userPhotoUrl: c.userPhotoUrl,
      isOnline: c.isOnline,
      unreadCount: c.unreadCount > 0 ? 0 : 1,
      lastActivity: c.lastActivity,
      lastMessage: c.lastMessage,
    );
  }

  Future<void> deleteConversation(String convId) async {
    conversations.removeWhere((c) => c.id == convId);
    try {
      await Supabase.instance.client
          .from('conversations')
          .delete()
          .eq('id', convId);
    } catch (e) {
      debugPrint('deleteConversation error: $e');
    }
  }

  Map<String, dynamic> _extractProfile(
      Map<String, dynamic> row, String prefix) {
    final key = '${prefix}_profile';
    if (row[key] is Map) return row[key] as Map<String, dynamic>;
    return {
      'id': row['${prefix}_id'],
      'name': 'Utilisateur',
      'photo_url': null,
      'is_online': false
    };
  }

  MessageType _parseType(String? t) {
    switch (t) {
      case 'image':
        return MessageType.image;
      case 'snap':
        return MessageType.snap;
      case 'audio':
        return MessageType.audio;
      case 'location':
        return MessageType.location;
      default:
        return MessageType.text;
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
  late ConversationModel conversation;

  final RxList<MessageModel> messages = <MessageModel>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isRecording = false.obs;
  final RxBool showAttachMenu = false.obs;
  final textController = TextEditingController();
  final RxString inputText = ''.obs;

  final Rx<MessageModel?> replyToMessage = Rx<MessageModel?>(null);

  RealtimeChannel? _channel;
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _audioPlayer = FlutterSoundPlayer();
  final RxInt recordingSeconds = 0.obs;
  String? _recordingPath;
  final _imagePicker = ImagePicker();

  void init(ConversationModel conv) {
    conversation = conv;
    textController.addListener(() => inputText.value = textController.text);
    _loadMessages();
    _subscribeToMessages();
    _service.markMessagesAsRead(conversation.id);
  }

  void setReplyTo(MessageModel? msg) {
    replyToMessage.value = msg;
    if (msg != null) {
      Future.delayed(const Duration(milliseconds: 100), () {
        textController.selection = TextSelection.fromPosition(
          TextPosition(offset: textController.text.length),
        );
      });
    }
  }

  void cancelReply() => replyToMessage.value = null;

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

  void _subscribeToMessages() {
    _channel = Supabase.instance.client
        .channel('conv:${conversation.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversation.id,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            final newMsg = _rowToMessage(record);
            messages.removeWhere((m) =>
                m.id.startsWith('temp_') &&
                m.text == newMsg.text &&
                m.senderId == newMsg.senderId);
            if (!messages.any((m) => m.id == newMsg.id)) {
              messages.add(newMsg);
            }
            if (newMsg.senderId != myId) {
              _service.markMessagesAsRead(conversation.id);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversation.id,
          ),
          callback: (payload) {
            final updated = payload.newRecord;
            final idx = messages.indexWhere((m) => m.id == updated['id']);
            if (idx != -1) {
              messages[idx] = messages[idx]
                  .copyWith(status: _parseStatus(updated['status']));
            }
          },
        )
        .subscribe();
    _service.markMessagesAsDelivered(conversation.id);
  }

  Future<void> sendText() async {
    final text = textController.text.trim();
    if (text.isEmpty) return;

    final reply = replyToMessage.value;
    textController.clear();
    replyToMessage.value = null;

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    messages.add(MessageModel(
      id: tempId,
      senderId: _service.currentUserId!,
      text: text,
      type: MessageType.text,
      status: MessageStatus.sending,
      createdAt: DateTime.now(),
      replyTo: reply,
    ));

    try {
      await _service.sendMessage(
        conversationId: conversation.id,
        content: text,
        type: 'text',
        replyToId: reply?.id,
      );
    } catch (_) {
      messages.removeWhere((m) => m.id == tempId);
      Get.snackbar('Erreur', 'Message non envoyé',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white);
    }
  }

  // ── Envoi d'une réponse à une story ──────────────────────────────
  // Appelé depuis StoryViewerScreen._ReplyBar._send()
  // storyData contient les infos de la story pour l'affichage dans le chat
  Future<void> sendStoryReply({
    required String conversationId,
    required String text,
    required StoryReplyData storyData,
  }) async {
    final uid = _service.currentUserId;
    if (uid == null) return;

    // Message optimiste immédiat
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    messages.add(MessageModel(
      id: tempId,
      senderId: uid,
      text: text,
      type: MessageType.text,
      status: MessageStatus.sending,
      createdAt: DateTime.now(),
      storyReply: storyData,
    ));

    // Essai avec colonnes story_* (si elles existent en BDD)
    bool sent = false;
    try {
      await Supabase.instance.client.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': uid,
        'type': 'text',
        'content': text,
        'status': 'sent',
        'story_id': storyData.storyId,
        'story_preview_url': storyData.storyPreviewUrl,
        'story_is_video': storyData.storyIsVideo,
        'topic': '📸 Story de ${storyData.storyOwnerName}',
      });
      sent = true;
    } catch (_) {
      // Colonnes story_* absentes → fallback minimal
    }

    if (!sent) {
      try {
        await Supabase.instance.client.from('messages').insert({
          'conversation_id': conversationId,
          'sender_id': uid,
          'type': 'text',
          'content': text,
          'status': 'sent',
        });
        sent = true;
      } catch (e) {
        messages.removeWhere((m) => m.id == tempId);
        debugPrint('sendStoryReply error: $e');
        rethrow;
      }
    }

    // Mettre à jour la conversation
    await Supabase.instance.client
        .from('conversations')
        .update({'updated_at': DateTime.now().toIso8601String()}).eq(
            'id', conversationId);
  }

  Future<void> deleteMessage(MessageModel msg) async {
    messages.removeWhere((m) => m.id == msg.id);
    if (!msg.id.startsWith('temp_')) {
      try {
        await Supabase.instance.client
            .from('messages')
            .delete()
            .eq('id', msg.id);
      } catch (e) {
        debugPrint('deleteMessage error: $e');
      }
    }
  }

  void copyMessage(MessageModel msg) {
    if (msg.text != null && msg.text!.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: msg.text!));
      Get.snackbar('Copié', 'Message copié dans le presse-papier',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white,
          duration: const Duration(seconds: 2));
    }
  }

  void showMessageOptions(BuildContext context, MessageModel msg) {
    HapticFeedback.mediumImpact();
    final isMine = msg.senderId == myId;
    final canCancel = isMine && msg.status == MessageStatus.sending;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            if (msg.type == MessageType.text && msg.text != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12)),
                child: Text(msg.text!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textMuted)),
              ),
            _MsgOption(
                icon: Icons.reply_rounded,
                label: 'Répondre',
                onTap: () {
                  Get.back();
                  setReplyTo(msg);
                }),
            if (msg.type == MessageType.text)
              _MsgOption(
                  icon: Icons.copy_rounded,
                  label: 'Copier',
                  onTap: () {
                    Get.back();
                    copyMessage(msg);
                  }),
            if (canCancel)
              _MsgOption(
                  icon: Icons.cancel_outlined,
                  label: "Annuler l'envoi",
                  onTap: () {
                    Get.back();
                    messages.removeWhere((m) => m.id == msg.id);
                  }),
            if (isMine)
              _MsgOption(
                  icon: Icons.delete_outline_rounded,
                  label: 'Supprimer',
                  color: const Color(0xFFFF3B30),
                  onTap: () {
                    Get.back();
                    deleteMessage(msg);
                  }),
            if (!isMine)
              _MsgOption(
                  icon: Icons.flag_outlined,
                  label: 'Signaler',
                  color: const Color(0xFFFF9500),
                  onTap: () => Get.back()),
          ],
        ),
      ),
    );
  }

  Future<void> sendSnap() async {
    showAttachMenu.value = false;
    try {
      await _service.sendMessage(
          conversationId: conversation.id,
          content: '📸 Snap',
          type: 'snap',
          expiresAt: DateTime.now().add(const Duration(hours: 24)));
    } catch (_) {}
  }

  Future<void> openSnap(MessageModel msg) async {
    final idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx != -1) {
      messages[idx] = MessageModel(
          id: msg.id,
          senderId: msg.senderId,
          text: msg.text,
          type: msg.type,
          status: msg.status,
          createdAt: msg.createdAt,
          isOpened: true,
          expiresAt: DateTime.now().add(const Duration(seconds: 10)));
    }
    await Supabase.instance.client
        .from('messages')
        .update({'is_opened': true}).eq('id', msg.id);
  }

  void toggleAttachMenu() => showAttachMenu.toggle();

  Future<void> startRecording() async {
    final dir = await getTemporaryDirectory();
    _recordingPath =
        '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.openRecorder();
    await _recorder.startRecorder(
        toFile: _recordingPath!, codec: Codec.aacADTS);
    isRecording.value = true;
    recordingSeconds.value = 0;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!isRecording.value) return false;
      recordingSeconds.value++;
      return recordingSeconds.value < 120;
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
      await Supabase.instance.client.storage.from('snaps').upload(path, file,
          fileOptions:
              const FileOptions(upsert: true, contentType: 'audio/m4a'));
      final url =
          Supabase.instance.client.storage.from('snaps').getPublicUrl(path);
      await _service.sendMessage(
          conversationId: conversation.id,
          content: '🎤 Message vocal',
          type: 'audio',
          mediaUrl: url,
          audioDuration: duration);
    } catch (e) {
      Get.snackbar('Erreur', "Impossible d'envoyer le vocal",
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white);
    }
  }

  Future<void> playAudio(String url) async {
    try {
      await _audioPlayer.openPlayer();
      await _audioPlayer.startPlayer(fromURI: url, codec: Codec.aacADTS);
    } catch (e) {
      debugPrint('playAudio error: $e');
    }
  }

  Future<void> stopAudio() async {
    try {
      await _audioPlayer.stopPlayer();
    } catch (_) {}
  }

  Future<void> envoyerPhoto({bool camera = false}) async {
    showAttachMenu.value = false;
    final picked = await _imagePicker.pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 80);
    if (picked == null) return;
    final uid = _service.currentUserId!;
    final path = 'photos/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      final file = File(picked.path);
      await Supabase.instance.client.storage.from('snaps').upload(path, file,
          fileOptions:
              const FileOptions(upsert: true, contentType: 'image/jpeg'));
      final url =
          Supabase.instance.client.storage.from('snaps').getPublicUrl(path);
      await _service.sendMessage(
          conversationId: conversation.id,
          content: '📷 Photo',
          type: 'image',
          mediaUrl: url);
    } catch (e) {
      Get.snackbar('Erreur', "Impossible d'envoyer la photo",
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white);
    }
  }

  Future<void> envoyerLocalisation() async {
    showAttachMenu.value = false;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        Get.snackbar('GPS désactivé', 'Active la localisation',
            snackPosition: SnackPosition.TOP,
            backgroundColor: const Color(0xFF13131A),
            colorText: Colors.white);
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
      await _service.sendMessage(
          conversationId: conversation.id,
          content: 'https://maps.google.com/?q=$lat,$lng',
          type: 'location');
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de récupérer la position',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white);
    }
  }

  String get myId => _service.currentUserId ?? '';

  // ── Convertit une row Supabase en MessageModel ─────────────────
  MessageModel _rowToMessage(Map<String, dynamic> row) {
    // Lecture des champs story optionnels
    StoryReplyData? storyReply;
    final storyId = row['story_id'] as String?;
    final storyPreviewUrl = row['story_preview_url'] as String?;
    if (storyId != null && storyPreviewUrl != null) {
      storyReply = StoryReplyData(
        storyId: storyId,
        storyPreviewUrl: storyPreviewUrl,
        storyIsVideo: row['story_is_video'] as bool? ?? false,
        storyOwnerName: _parseStoryOwnerName(row['topic'] as String?),
      );
    }

    return MessageModel(
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
          ? DateTime.tryParse(row['expires_at'])
          : null,
      storyReply: storyReply,
    );
  }

  // Extrait le nom du proprio depuis le champ topic "📸 Story de Prénom"
  String _parseStoryOwnerName(String? topic) {
    if (topic == null) return '';
    const prefix = '📸 Story de ';
    if (topic.startsWith(prefix)) return topic.substring(prefix.length);
    return topic;
  }

  MessageType _parseType(String? t) {
    switch (t) {
      case 'image':
        return MessageType.image;
      case 'snap':
        return MessageType.snap;
      case 'audio':
        return MessageType.audio;
      case 'location':
        return MessageType.location;
      default:
        return MessageType.text;
    }
  }

  MessageStatus _parseStatus(String? s) {
    switch (s) {
      case 'sending':
        return MessageStatus.sending;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read':
        return MessageStatus.read;
      default:
        return MessageStatus.sent;
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

// ─── OPTION WIDGET ────────────────────────────────────────────────

class _MsgOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const _MsgOption(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: c, size: 22),
      title: Text(label,
          style:
              TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.w500)),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
