import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rencontre/core/services/notification_service.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:rencontre/features/chat/view/conversation_screen.dart';
import 'package:rencontre/core/theme/app_theme.dart';

enum ChatFilter { all, unread, online, nearby, media }

class ChatListController extends GetxController {
  final _service = SupabaseService();
  final RxList<ConversationModel> conversations = <ConversationModel>[].obs;
  final RxBool isLoading = true.obs;
  final Rx<ChatFilter> activeFilter = ChatFilter.all.obs;
  final RxBool isSearching = false.obs;
  final RxString searchQuery = ''.obs;
  RealtimeChannel? _channel;
  final RxSet<String> pinnedIds = <String>{}.obs;
  // ✅ NOUVEAU — expose l'ID de l'utilisateur courant pour que
  // chat_list_screen.dart puisse appeler msg.isMine(controller.myId)
  String? get myId => _service.currentUserId;

  // ✅ FIX Realtime — polling de secours + horodatage de la dernière sync
  Timer? _pollingTimer;
  Timer? _watchdogTimer;
  DateTime? _lastSyncAt;

  int get totalUnread => conversations.fold(0, (sum, c) => sum + c.unreadCount);

  List<ConversationModel> get filteredConversations {
    List<ConversationModel> list;
    switch (activeFilter.value) {
      case ChatFilter.unread:
        list = conversations.where((c) => c.unreadCount > 0).toList();
        break;
      case ChatFilter.online:
        list = conversations.where((c) => c.isOnline).toList();
        break;
      case ChatFilter.nearby:
        final cutoff = DateTime.now().subtract(const Duration(hours: 1));
        list = conversations
            .where((c) =>
                c.lastActivity != null && c.lastActivity!.isAfter(cutoff))
            .toList();
        break;
      case ChatFilter.media:
        list = conversations
            .where((c) =>
                c.lastMessage != null &&
                (c.lastMessage!.type == MessageType.image ||
                    c.lastMessage!.type == MessageType.snap))
            .toList();
        break;
      case ChatFilter.all:
      default:
        list = conversations.toList();
    }
    final q = searchQuery.value.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((c) => c.userName.toLowerCase().contains(q)).toList();
    }
    return list;
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
        final lastMsg = row['_last_message'] as Map<String, dynamic>?;
        final unread = (row['_unread_count'] as int?) ?? 0;
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
                  status: _parseStatus(lastMsg['status']),
                  createdAt: DateTime.tryParse(lastMsg['created_at'] ?? '') ??
                      DateTime.now(),
                  isOpened: lastMsg['is_opened'] ?? false,
                  audioDurationSec: lastMsg['audio_duration'],
                )
              : null,
        );
      }).toList();
      _sortConversations();
      // ✅ FIX Realtime — on marque l'heure de la dernière synchro réussie
      _lastSyncAt = DateTime.now();
    } catch (e) {
      debugPrint('ChatListController error: $e');
    } finally {
      isLoading.value = false;
    }
    update();
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
    nowPinned ? pinnedIds.add(conv.id) : pinnedIds.remove(conv.id);
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
    update();
  }

  // ✅ FIX Realtime — abonnement avec callback de statut, logs de debug,
  // fallback de polling automatique, et watchdog périodique.
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
            // ✅ Log de debug : confirme que le Realtime arrive bien
            debugPrint(
                '📨 [Realtime ChatList] Nouveau message — conv=$convId sender=$senderId');
            if (convId == null) return;
            final isMine = senderId == uid;
            final isConvOpen =
                Get.isRegistered<ConversationController>(tag: convId);
            final idx = conversations.indexWhere((c) => c.id == convId);
            if (idx != -1) {
              final c = conversations[idx];
              if (!isMine && !isConvOpen) {
                await NotificationService.showMessageNotification(
                  senderName: c.userName,
                  message: _getMessagePreview(record),
                  senderPhoto: c.userPhotoUrl,
                  conversationId: convId,
                );
              }
              conversations.removeAt(idx);
              conversations.insert(
                  0,
                  ConversationModel(
                    id: c.id,
                    userId: c.userId,
                    userName: c.userName,
                    userPhotoUrl: c.userPhotoUrl,
                    isOnline: c.isOnline,
                    isPinned: c.isPinned,
                    unreadCount: (!isMine && !isConvOpen)
                        ? c.unreadCount + 1
                        : c.unreadCount,
                    lastActivity: DateTime.now().toUtc(),
                    lastMessage: MessageModel(
                      id: record['id'] ?? '',
                      senderId: senderId ?? '',
                      text: record['content'],
                      type: _parseType(record['type']),
                      status: MessageStatus.sent,
                      createdAt: DateTime.now(),
                    ),
                  ));
              _sortConversations();
              update();
            } else {
              await loadConversations();
            }
            _lastSyncAt = DateTime.now();
          },
        )
        .subscribe((status, [error]) {
      // ✅ Log de debug : confirme l'état de la connexion Realtime
      debugPrint('🔌 [Realtime ChatList] status=$status error=$error');
      if (status == RealtimeSubscribeStatus.subscribed) {
        // Connexion OK : on arrête le polling de secours s'il tournait
        _pollingTimer?.cancel();
        _pollingTimer = null;
        _lastSyncAt = DateTime.now();
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.closed) {
        // ✅ Fallback : Realtime en panne, on repasse en polling
        _startPolling();
      }
    });

    // ✅ Watchdog — même si le statut Realtime reste "subscribed" sans
    // jamais rien recevoir, on resynchronise automatiquement si rien
    // n'est arrivé depuis plus de 15s. Filet de sécurité léger.
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 20), (t) {
      if (!Get.isRegistered<ChatListController>()) {
        t.cancel();
        return;
      }
      final last = _lastSyncAt;
      if (last == null || DateTime.now().difference(last).inSeconds > 15) {
        debugPrint('⏱️ [ChatList] Resynchronisation périodique de sécurité');
        loadConversations();
      }
    });
  }

  // ✅ FIX Realtime — polling de secours (3s) si le canal tombe en panne
  void _startPolling() {
    if (_pollingTimer != null) return; // déjà en cours
    debugPrint('⚠️ [ChatList] Realtime indisponible → passage en polling (3s)');
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      await loadConversations();
    });
  }

  String _getMessagePreview(Map<String, dynamic> r) {
    if (r['story_id'] != null) return '📸 Story';
    switch (r['type'] as String? ?? 'text') {
      case 'image':
        return '📷 Photo';
      case 'audio':
        return '🎤 Vocal';
      case 'snap':
        return '📸 Snap';
      case 'location':
        return '📍 Position';
      // ✅ Aperçu pour réponse annonce
      case 'annonce_reply':
        return '📢 A répondu à une annonce';
      default:
        return r['content'] as String? ?? '';
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
        isPinned: conv.isPinned,
        unreadCount: 0,
        lastActivity: conv.lastActivity,
        lastMessage: conv.lastMessage,
      );
      update();
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
      isPinned: c.isPinned,
      unreadCount: c.unreadCount > 0 ? 0 : 1,
      lastActivity: c.lastActivity,
      lastMessage: c.lastMessage,
    );
    update();
  }

  Future<void> deleteConversation(String convId) async {
    conversations.removeWhere((c) => c.id == convId);
    update();
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

  // ✅ _parseType avec annonce_reply ajouté
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
      case 'annonce_reply':
        return MessageType.annonceReply;
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
    _pollingTimer?.cancel(); // ✅ FIX Realtime
    _watchdogTimer?.cancel(); // ✅ FIX Realtime
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
  final RxBool isLoading = false.obs;
  final ScrollController scrollController = ScrollController();
  final RxBool isRecording = false.obs;
  final RxBool showAttachMenu = false.obs;
  late TextEditingController textController;
  final RxString inputText = ''.obs;
  final Rx<MessageModel?> replyToMessage = Rx<MessageModel?>(null);
  final RxBool isOtherOnline = false.obs;
  final RxBool isOtherTyping = false.obs;
  final RxBool ephemeralMode = false.obs;
  final Rx<DateTime?> lastReadAt = Rx<DateTime?>(null);

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _recorderOpen = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final RxInt recordingSeconds = 0.obs;
  final RxDouble recordingDb = 0.0.obs;
  String? _recordingPath;
  final RxString currentlyPlayingId = ''.obs;
  Timer? _recordingSecondsTimer;
  Codec? _detectedCodec;
  String? _detectedExt;
  RealtimeChannel? _channel;
  RealtimeChannel? _presenceChannel;
  RealtimeChannel? _typingChannel;
  Timer? _typingTimer;
  Timer? _myTypingTimer;
  bool _isCurrentlyTyping = false;
  Timer? _pollingTimer;
  final _imagePicker = ImagePicker();

  static const List<String> availableEmojis = [
    '❤️',
    '😂',
    '👍',
    '😮',
    '😢',
    '🔥'
  ];

  void init(ConversationModel conv) {
    conversation = conv;
    isOtherOnline.value = conv.isOnline;
    _audioPlayer.onPlayerComplete.listen((_) => currentlyPlayingId.value = '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMessages();
      _subscribeToMessages();
      _subscribeToPresence(conv.userId);
      _subscribeToTyping(conv.id, conv.userId);
      _markReadAndUpdateBadge(conv.id);
      _fetchOtherOnlineStatus(conv.userId);
    });
  }

  Future<void> _fetchOtherOnlineStatus(String otherUserId) async {
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('is_online')
          .eq('id', otherUserId)
          .maybeSingle();
      if (data != null) {
        isOtherOnline.value = data['is_online'] == true;
      }
    } catch (_) {}
  }

  static const List<_CodecOption> _codecCandidates = [
    _CodecOption(Codec.aacMP4, '.mp4', 'audio/mp4'),
    _CodecOption(Codec.aacADTS, '.aac', 'audio/aac'),
    _CodecOption(Codec.opusOGG, '.ogg', 'audio/ogg'),
  ];

  Future<bool> _detectCodec(FlutterSoundRecorder recorder) async {
    if (_detectedCodec != null) return true;
    final dir = await getTemporaryDirectory();
    for (final candidate in _codecCandidates) {
      try {
        final testPath = '${dir.path}/test_codec${candidate.ext}';
        await recorder.startRecorder(toFile: testPath, codec: candidate.codec);
        await Future.delayed(const Duration(milliseconds: 200));
        await recorder.stopRecorder();
        _detectedCodec = candidate.codec;
        _detectedExt = candidate.ext;
        try {
          File(testPath).deleteSync();
        } catch (_) {}
        return true;
      } catch (_) {}
    }
    return false;
  }

  void onTextChanged() {
    inputText.value = textController.text;
    _handleMyTyping();
  }

  void _handleMyTyping() {
    if (textController.text.trim().isNotEmpty && !_isCurrentlyTyping) {
      _isCurrentlyTyping = true;
      _updateTypingStatus(true);
    }
    _myTypingTimer?.cancel();
    _myTypingTimer = Timer(const Duration(seconds: 2), () {
      if (_isCurrentlyTyping) {
        _isCurrentlyTyping = false;
        _updateTypingStatus(false);
      }
    });
  }

  Future<void> _updateTypingStatus(bool typing) async {
    final uid = _service.currentUserId;
    if (uid == null) return;
    try {
      await Supabase.instance.client.from('typing_status').upsert({
        'conversation_id': conversation.id,
        'user_id': uid,
        'is_typing': typing,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  void _subscribeToTyping(String convId, String otherUserId) {
    _typingChannel = Supabase.instance.client
        .channel('typing:$convId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'typing_status',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: convId,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (record['user_id'] != otherUserId) return;
            final typing = record['is_typing'] == true;
            if (typing) {
              isOtherTyping.value = true;
              _typingTimer?.cancel();
              _typingTimer = Timer(const Duration(seconds: 4),
                  () => isOtherTyping.value = false);
            } else {
              _typingTimer?.cancel();
              isOtherTyping.value = false;
            }
          },
        )
        .subscribe();
  }

  Future<void> toggleReaction(MessageModel msg, String emoji) async {
    final uid = _service.currentUserId!;
    final currentReactions = Map<String, List<String>>.from(
        msg.reactions.map((k, v) => MapEntry(k, List<String>.from(v))));
    final users = currentReactions[emoji] ?? [];
    if (users.contains(uid)) {
      users.remove(uid);
      if (users.isEmpty) currentReactions.remove(emoji);
    } else {
      users.add(uid);
      currentReactions[emoji] = users;
    }
    final idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx != -1)
      messages[idx] = messages[idx].copyWith(reactions: currentReactions);
    try {
      await Supabase.instance.client.from('messages').update({
        'reactions': currentReactions.map((k, v) => MapEntry(k, v))
      }).eq('id', msg.id);
    } catch (_) {
      if (idx != -1)
        messages[idx] = messages[idx].copyWith(reactions: msg.reactions);
    }
  }

  void toggleEphemeralMode() {
    ephemeralMode.toggle();
    Get.snackbar(
      ephemeralMode.value
          ? '🔥 Mode éphémère activé'
          : 'Mode éphémère désactivé',
      ephemeralMode.value
          ? 'Les nouveaux messages disparaîtront après 24h'
          : 'Les messages ne disparaîtront plus',
      snackPosition: SnackPosition.TOP,
      backgroundColor: ephemeralMode.value
          ? AppColors.accent.withOpacity(0.9)
          : AppColors.surface2,
      colorText: Colors.white,
      duration: const Duration(seconds: 2),
    );
  }

  void _subscribeToPresence(String otherUserId) {
    _presenceChannel = Supabase.instance.client
        .channel('presence:$otherUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: otherUserId,
          ),
          callback: (payload) {
            isOtherOnline.value = payload.newRecord['is_online'] == true;
          },
        )
        .subscribe();
  }

  void _markReadAndUpdateBadge(String convId) {
    _service.markMessagesAsRead(convId);
    NotificationService.clearConversationNotifications(convId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!Get.isRegistered<ChatListController>()) return;
      final listCtrl = Get.find<ChatListController>();
      final idx = listCtrl.conversations.indexWhere((c) => c.id == convId);
      if (idx != -1) {
        final c = listCtrl.conversations[idx];
        listCtrl.conversations[idx] = ConversationModel(
          id: c.id,
          userId: c.userId,
          userName: c.userName,
          userPhotoUrl: c.userPhotoUrl,
          isOnline: c.isOnline,
          isPinned: c.isPinned,
          unreadCount: 0,
          lastActivity: c.lastActivity,
          lastMessage: c.lastMessage,
        );
        listCtrl.update();
      }
    });
  }

  void setReplyTo(MessageModel? msg) {
    replyToMessage.value = msg;
    if (msg != null) {
      Future.delayed(const Duration(milliseconds: 100), () {
        textController.selection = TextSelection.fromPosition(
            TextPosition(offset: textController.text.length));
      });
    }
  }

  void cancelReply() => replyToMessage.value = null;

  Future<void> _loadMessages() async {
    isLoading.value = true;
    try {
      final data = await _service.fetchMessages(conversation.id);
      final rawMessages = data.map((row) => _rowToMessage(row)).toList();
      final msgById = {for (final m in rawMessages) m.id: m};
      messages.value = data.map((row) {
        final msg = _rowToMessage(row);
        final replyId = row['reply_to_id'] as String?;
        if (replyId != null && msgById.containsKey(replyId)) {
          return msg.copyWith(replyTo: msgById[replyId]);
        }
        return msg;
      }).toList();
      _updateLastReadAt();
    } catch (e) {
      debugPrint('Load messages error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void _updateLastReadAt() {
    final myMsgs = messages
        .where((m) => m.senderId == myId && m.status == MessageStatus.read)
        .toList();
    if (myMsgs.isNotEmpty) {
      myMsgs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      lastReadAt.value = myMsgs.first.createdAt;
    }
  }

  void _subscribeToMessages() {
    final convId = conversation.id;
    _channel = Supabase.instance.client
        .channel('conv_screen:$convId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: convId,
          ),
          callback: (payload) async {
            final record = payload.newRecord;
            MessageModel? replyTo;
            final replyId = record['reply_to_id'] as String?;
            if (replyId != null) {
              replyTo = messages.firstWhereOrNull((m) => m.id == replyId);
              if (replyTo == null) {
                try {
                  final rd = await Supabase.instance.client
                      .from('messages')
                      .select()
                      .eq('id', replyId)
                      .maybeSingle();
                  if (rd != null) replyTo = _rowToMessage(rd);
                } catch (_) {}
              }
            }
            final newMsg = _rowToMessage(record, replyTo: replyTo);
            messages.removeWhere((m) =>
                m.id.startsWith('temp_') &&
                m.text == newMsg.text &&
                m.senderId == newMsg.senderId);
            if (!messages.any((m) => m.id == newMsg.id)) {
              messages.add(newMsg);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (scrollController.hasClients) {
                  scrollController.animateTo(0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut);
                }
              });
              if (newMsg.senderId != myId) {
                HapticFeedback.lightImpact();
                try {
                  final player = AudioPlayer();
                  await player.play(AssetSource('sounds/message_sound.mp3'));
                  player.onPlayerComplete.listen((_) => player.dispose());
                } catch (_) {}
              }
            }
            if (newMsg.senderId != myId) _markReadAndUpdateBadge(convId);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: convId,
          ),
          callback: (payload) {
            final updated = payload.newRecord;
            final idx = messages.indexWhere((m) => m.id == updated['id']);
            if (idx != -1) {
              final rawReactions =
                  updated['reactions'] as Map<String, dynamic>? ?? {};
              final reactions = rawReactions.map(
                  (k, v) => MapEntry(k, List<String>.from(v as List? ?? [])));
              final newStatus = _parseStatus(updated['status']);
              messages[idx] = messages[idx].copyWith(
                status: newStatus,
                reactions: reactions,
                isOpened: updated['is_opened'] ?? messages[idx].isOpened,
              );
              if (newStatus == MessageStatus.read &&
                  messages[idx].senderId == myId) {
                lastReadAt.value = DateTime.now();
              }
            }
          },
        )
        .subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        _startPolling();
      }
    });
    _service.markMessagesAsDelivered(convId);
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final data = await _service.fetchMessages(conversation.id);
        final msgById = {for (final m in messages) m.id: m};
        for (final row in data) {
          final msg = _rowToMessage(row);
          if (!messages.any((m) => m.id == msg.id)) {
            final replyId = row['reply_to_id'] as String?;
            messages.add(msg.copyWith(
                replyTo: replyId != null ? msgById[replyId] : null));
          }
        }
      } catch (_) {}
    });
  }

  Future<void> sendText() async {
    final text = textController.text.trim();
    if (text.isEmpty) return;
    final reply = replyToMessage.value;
    textController.clear();
    replyToMessage.value = null;
    _isCurrentlyTyping = false;
    _updateTypingStatus(false);
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    messages.add(MessageModel(
      id: tempId,
      senderId: _service.currentUserId!,
      text: text,
      type: MessageType.text,
      status: MessageStatus.sending,
      createdAt: DateTime.now(),
      replyTo: reply,
      disappearsAt: ephemeralMode.value
          ? DateTime.now().add(const Duration(hours: 24))
          : null,
    ));
    try {
      await _service.sendMessage(
        conversationId: conversation.id,
        content: text,
        type: 'text',
        replyToId: reply?.id,
        disappearsAt: ephemeralMode.value
            ? DateTime.now().add(const Duration(hours: 24))
            : null,
      );
    } catch (_) {
      messages.removeWhere((m) => m.id == tempId);
      Get.snackbar('Erreur', 'Message non envoyé',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white);
    }
  }

  // ✅ Envoyer une réponse à une annonce
  Future<void> sendAnnonceReply({
    required String conversationId,
    required String text,
    required AnnonceReplyData annonceData,
  }) async {
    final uid = _service.currentUserId;
    if (uid == null) return;
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    messages.add(MessageModel(
      id: tempId,
      senderId: uid,
      text: text,
      type: MessageType.annonceReply,
      status: MessageStatus.sending,
      createdAt: DateTime.now(),
      annonceReply: annonceData,
    ));
    try {
      await Supabase.instance.client.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': uid,
        'type': 'annonce_reply',
        'content': text,
        'status': 'sent',
        // ✅ Sérialise les données de l'annonce dans le champ payload
        'payload': annonceData.toJson(),
      });
    } catch (e) {
      messages.removeWhere((m) => m.id == tempId);
      Get.snackbar('Erreur', "Impossible d'envoyer la réponse",
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white);
    }
  }

  Future<void> sendStoryReply({
    required String conversationId,
    required String text,
    required StoryReplyData storyData,
  }) async {
    final uid = _service.currentUserId;
    if (uid == null) return;
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
    } catch (_) {
      try {
        await Supabase.instance.client.from('messages').insert({
          'conversation_id': conversationId,
          'sender_id': uid,
          'type': 'text',
          'content': text,
          'status': 'sent',
        });
      } catch (e) {
        messages.removeWhere((m) => m.id == tempId);
      }
    }
  }

  Future<void> deleteMessage(MessageModel msg) async {
    messages.removeWhere((m) => m.id == msg.id);
    if (!msg.id.startsWith('temp_')) {
      try {
        await Supabase.instance.client
            .from('messages')
            .delete()
            .eq('id', msg.id);
      } catch (_) {}
    }
  }

  void copyMessage(MessageModel msg) {
    if (msg.text != null && msg.text!.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: msg.text!));
      Get.snackbar('Copié', 'Message copié',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white,
          duration: const Duration(seconds: 2));
    }
  }

  void showMessageOptions(BuildContext context, MessageModel msg) {
    HapticFeedback.mediumImpact();
    final isMine = msg.senderId == myId;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(32)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: availableEmojis.map((emoji) {
                final uid = _service.currentUserId ?? '';
                final hasReacted = msg.hasReacted(emoji, uid);
                return GestureDetector(
                  onTap: () {
                    Get.back();
                    toggleReaction(msg, emoji);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: hasReacted
                          ? AppColors.accent.withOpacity(0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: hasReacted
                          ? Border.all(color: AppColors.accent)
                          : null,
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                );
              }).toList(),
            ),
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
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
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
        ]),
      ),
    );
  }

  Future<void> openSnap(MessageModel msg) async {
    if (msg.isOpened) return;
    final duration = msg.snapDurationSec ?? 10;
    final idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx != -1) {
      messages[idx] = messages[idx].copyWith(
        isOpened: true,
        expiresAt: duration == 0
            ? DateTime.now()
            : DateTime.now().add(Duration(seconds: duration)),
      );
    }
    try {
      await Supabase.instance.client.from('messages').update({
        'is_opened': true,
        'expires_at': (duration == 0
                ? DateTime.now()
                : DateTime.now().add(Duration(seconds: duration)))
            .toIso8601String(),
      }).eq('id', msg.id);
    } catch (_) {}
    if (duration > 0) {
      Timer(Duration(seconds: duration), () {
        final i = messages.indexWhere((m) => m.id == msg.id);
        if (i != -1) messages.removeAt(i);
      });
    } else {
      Timer(const Duration(milliseconds: 500), () {
        final i = messages.indexWhere((m) => m.id == msg.id);
        if (i != -1) messages.removeAt(i);
      });
    }
  }

  Future<void> envoyerPhotoEphemere() async {
    showAttachMenu.value = false;
    final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 85);
    if (picked == null) return;
    final uid = _service.currentUserId!;
    final path = 'snaps/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      final file = File(picked.path);
      await Supabase.instance.client.storage.from('snaps').upload(path, file,
          fileOptions:
              const FileOptions(upsert: true, contentType: 'image/jpeg'));
      final url =
          Supabase.instance.client.storage.from('snaps').getPublicUrl(path);
      await _service.sendMessage(
        conversationId: conversation.id,
        content: '📸 Photo éphémère',
        type: 'snap',
        mediaUrl: url,
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        snapDurationSeconds: 10,
      );
    } catch (e) {
      Get.snackbar('Erreur', "Impossible d'envoyer le snap",
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white);
    }
  }

  Future<void> envoyerPhotoAvecDuree(
      {required bool camera, required SnapDuration duree}) async {
    showAttachMenu.value = false;
    final picked = await _imagePicker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked == null) return;
    final uid = _service.currentUserId!;
    final isSnap = duree != SnapDuration.none;
    final path =
        '${isSnap ? 'snaps' : 'photos'}/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      final file = File(picked.path);
      await Supabase.instance.client.storage.from('snaps').upload(path, file,
          fileOptions:
              const FileOptions(upsert: true, contentType: 'image/jpeg'));
      final url =
          Supabase.instance.client.storage.from('snaps').getPublicUrl(path);
      await _service.sendMessage(
        conversationId: conversation.id,
        content: isSnap ? '📸 Photo éphémère' : '📷 Photo',
        type: isSnap ? 'snap' : 'image',
        mediaUrl: url,
        disappearsAt: ephemeralMode.value
            ? DateTime.now().add(const Duration(hours: 24))
            : null,
        snapDurationSeconds: duree.seconds,
      );
    } catch (e) {
      Get.snackbar('Erreur', "Impossible d'envoyer la photo",
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white);
    }
  }

  void toggleAttachMenu() => showAttachMenu.toggle();

  Future<void> startRecording() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      Get.snackbar(
          'Permission refusée', 'Active le microphone dans les paramètres',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white,
          mainButton: TextButton(
              onPressed: () => openAppSettings(),
              child: Text('Paramètres',
                  style: TextStyle(color: AppColors.accent))));
      return;
    }
    if (_recorderOpen) {
      try {
        await _recorder.closeRecorder();
      } catch (_) {}
      _recorderOpen = false;
    }
    try {
      await _recorder.openRecorder();
      _recorderOpen = true;
      final codecFound = await _detectCodec(_recorder);
      if (!codecFound) {
        await _recorder.closeRecorder();
        _recorderOpen = false;
        Get.snackbar('Erreur', 'Enregistrement non supporté sur cet appareil',
            snackPosition: SnackPosition.TOP,
            backgroundColor: const Color(0xFF13131A),
            colorText: Colors.white);
        return;
      }
      final dir = await getTemporaryDirectory();
      _recordingPath =
          '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}$_detectedExt';
      await _recorder
          .setSubscriptionDuration(const Duration(milliseconds: 150));
      await _recorder.startRecorder(
          toFile: _recordingPath!, codec: _detectedCodec!);
      isRecording.value = true;
      recordingSeconds.value = 0;
      recordingDb.value = 0;
      _recorder.onProgress!.listen((e) {
        if (!isRecording.value) return;
        if (e.decibels != null)
          recordingDb.value = (e.decibels! + 60).clamp(0.0, 80.0);
      });
      _recordingSecondsTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!isRecording.value) {
          t.cancel();
          return;
        }
        recordingSeconds.value++;
        if (recordingSeconds.value >= 120) {
          t.cancel();
          stopRecording();
        }
      });
    } catch (e) {
      _recorderOpen = false;
      isRecording.value = false;
    }
  }

  Future<void> stopRecording() async {
    if (!isRecording.value) return;
    try {
      _recordingSecondsTimer?.cancel();
      final path = await _recorder.stopRecorder();
      await _recorder.closeRecorder();
      _recorderOpen = false;
      isRecording.value = false;
      recordingDb.value = 0;
      if (path == null || recordingSeconds.value < 1) return;
      await _sendAudio(File(path), recordingSeconds.value);
    } catch (e) {
      _recorderOpen = false;
      isRecording.value = false;
    }
  }

  void cancelRecording() async {
    _recordingSecondsTimer?.cancel();
    try {
      await _recorder.stopRecorder();
      await _recorder.closeRecorder();
      _recorderOpen = false;
    } catch (_) {}
    isRecording.value = false;
    recordingSeconds.value = 0;
    recordingDb.value = 0;
  }

  Future<void> _sendAudio(File file, int duration) async {
    final uid = _service.currentUserId!;
    final ext = _detectedExt ?? '.mp4';
    final contentType = ext == '.ogg'
        ? 'audio/ogg'
        : ext == '.aac'
            ? 'audio/aac'
            : 'audio/mp4';
    final path = 'audio/$uid/${DateTime.now().millisecondsSinceEpoch}$ext';
    try {
      await Supabase.instance.client.storage.from('snaps').upload(path, file,
          fileOptions: FileOptions(upsert: true, contentType: contentType));
      final url =
          Supabase.instance.client.storage.from('snaps').getPublicUrl(path);
      await _service.sendMessage(
        conversationId: conversation.id,
        content: '🎤 Message vocal',
        type: 'audio',
        mediaUrl: url,
        audioDuration: duration,
        disappearsAt: ephemeralMode.value
            ? DateTime.now().add(const Duration(hours: 24))
            : null,
      );
    } catch (e) {
      Get.snackbar('Erreur', "Impossible d'envoyer le vocal",
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white);
    }
  }

  Future<void> playAudio(String url, String messageId) async {
    try {
      if (currentlyPlayingId.value == messageId) {
        await _audioPlayer.stop();
        currentlyPlayingId.value = '';
        return;
      }
      if (currentlyPlayingId.value.isNotEmpty) await _audioPlayer.stop();
      currentlyPlayingId.value = messageId;
      await _audioPlayer.play(UrlSource(url));
    } catch (e) {
      currentlyPlayingId.value = '';
    }
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
        mediaUrl: url,
        disappearsAt: ephemeralMode.value
            ? DateTime.now().add(const Duration(hours: 24))
            : null,
      );
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
      Get.snackbar('📍', 'Récupération en cours...',
          snackPosition: SnackPosition.TOP,
          duration: const Duration(seconds: 1),
          backgroundColor: AppColors.surface2,
          colorText: Colors.white);
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      await _service.sendMessage(
        conversationId: conversation.id,
        content:
            '${position.latitude.toStringAsFixed(6)},${position.longitude.toStringAsFixed(6)}',
        type: 'location',
      );
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de récupérer la position',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white);
    }
  }

  String get myId => _service.currentUserId ?? '';

  // ✅ _rowToMessage avec parsing AnnonceReplyData
  MessageModel _rowToMessage(Map<String, dynamic> row,
      {MessageModel? replyTo}) {
    // ── Story reply ──────────────────────────────────────────────
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

    // ✅ Annonce reply — parse depuis le champ payload
    AnnonceReplyData? annonceReply;
    final type = _parseType(row['type'] as String?);
    if (type == MessageType.annonceReply && row['payload'] != null) {
      try {
        annonceReply = AnnonceReplyData.fromJson(
            Map<String, dynamic>.from(row['payload'] as Map));
      } catch (e) {
        debugPrint('AnnonceReplyData parse error: $e');
      }
    }

    final rawReactions = row['reactions'] as Map<String, dynamic>? ?? {};
    final reactions = rawReactions
        .map((k, v) => MapEntry(k, List<String>.from(v as List? ?? [])));

    return MessageModel(
      id: row['id'] ?? '',
      senderId: row['sender_id'] ?? '',
      text: row['content'],
      mediaUrl: row['media_url'],
      type: type,
      status: _parseStatus(row['status']),
      createdAt: DateTime.tryParse(row['created_at'] ?? '') ?? DateTime.now(),
      isOpened: row['is_opened'] ?? false,
      audioDurationSec: row['audio_duration'],
      snapDurationSec: row['snap_duration'] as int?,
      expiresAt: row['expires_at'] != null
          ? DateTime.tryParse(row['expires_at'])
          : null,
      disappearsAt: row['disappears_at'] != null
          ? DateTime.tryParse(row['disappears_at'])
          : null,
      reactions: reactions,
      storyReply: storyReply,
      annonceReply: annonceReply, // ✅
      replyTo: replyTo,
    );
  }

  String _parseStoryOwnerName(String? topic) {
    if (topic == null) return '';
    const prefix = '📸 Story de ';
    if (topic.startsWith(prefix)) return topic.substring(prefix.length);
    return topic;
  }

  // ✅ _parseType avec annonce_reply
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
      case 'annonce_reply':
        return MessageType.annonceReply;
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
    _presenceChannel?.unsubscribe();
    _typingChannel?.unsubscribe();
    _typingTimer?.cancel();
    _myTypingTimer?.cancel();
    _pollingTimer?.cancel();
    _recordingSecondsTimer?.cancel();
    _updateTypingStatus(false);
    if (_recorderOpen) _recorder.closeRecorder().catchError((_) {});
    _audioPlayer.dispose();
    scrollController.dispose();
    if (ephemeralMode.value) {
      ephemeralMode.value = false;
      Supabase.instance.client
          .from('conversations')
          .update({'ephemeral_mode': false})
          .eq('id', conversation.id)
          .catchError((_) {});
    }
    super.onClose();
  }
}

class _CodecOption {
  final Codec codec;
  final String ext;
  final String mimeType;
  const _CodecOption(this.codec, this.ext, this.mimeType);
}

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
