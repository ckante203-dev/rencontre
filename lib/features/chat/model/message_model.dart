enum MessageType { text, image, snap, audio, location }

enum MessageStatus { sending, sent, delivered, read }

// ── Données d'une réponse à une story ──────────────────────────────
class StoryReplyData {
  final String storyId;
  final String storyPreviewUrl;
  final bool storyIsVideo;
  final String storyOwnerName;

  const StoryReplyData({
    required this.storyId,
    required this.storyPreviewUrl,
    required this.storyIsVideo,
    required this.storyOwnerName,
  });
}

// ═══════════════════════════════════════════════════════════════════
//  MESSAGE MODEL
// ═══════════════════════════════════════════════════════════════════

class MessageModel {
  final String id;
  final String senderId;
  final String? text;
  final String? mediaUrl;
  final MessageType type;
  final MessageStatus status;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool isOpened;
  final int? audioDurationSec;

  /// Réponse à un message normal (long-press → Répondre)
  final MessageModel? replyTo;

  /// Réponse à une story (envoyée depuis le viewer)
  final StoryReplyData? storyReply;

  const MessageModel({
    required this.id,
    required this.senderId,
    this.text,
    this.mediaUrl,
    required this.type,
    this.status = MessageStatus.sent,
    required this.createdAt,
    this.expiresAt,
    this.isOpened = false,
    this.audioDurationSec,
    this.replyTo,
    this.storyReply,
  });

  bool get isSnap => type == MessageType.snap;
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isMine => senderId == 'me';
  bool get isStoryReply => storyReply != null;

  MessageModel copyWith({
    String? id,
    String? senderId,
    String? text,
    String? mediaUrl,
    MessageType? type,
    MessageStatus? status,
    DateTime? createdAt,
    DateTime? expiresAt,
    bool? isOpened,
    int? audioDurationSec,
    MessageModel? replyTo,
    StoryReplyData? storyReply,
  }) {
    return MessageModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      type: type ?? this.type,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      isOpened: isOpened ?? this.isOpened,
      audioDurationSec: audioDurationSec ?? this.audioDurationSec,
      replyTo: replyTo ?? this.replyTo,
      storyReply: storyReply ?? this.storyReply,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  CONVERSATION MODEL
// ═══════════════════════════════════════════════════════════════════

class ConversationModel {
  final String id;
  final String userId;
  final String userName;
  final String? userPhotoUrl;
  final bool isOnline;
  final MessageModel? lastMessage;
  final int unreadCount;
  final DateTime? lastActivity;
  final bool isPinned;

  const ConversationModel({
    required this.id,
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
    this.isOnline = false,
    this.lastMessage,
    this.unreadCount = 0,
    this.lastActivity,
    this.isPinned = false,
  });
}
