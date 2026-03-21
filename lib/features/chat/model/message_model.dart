// ═══════════════════════════════════════════════════════════════════
//  ENUMS
// ═══════════════════════════════════════════════════════════════════

enum MessageType { text, image, snap, audio, location }

enum MessageStatus { sending, sent, delivered, read }

// ═══════════════════════════════════════════════════════════════════
//  STORY REPLY DATA
// ═══════════════════════════════════════════════════════════════════

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
  final DateTime? disappearsAt;
  final bool isOpened;
  final int? audioDurationSec;

  /// Durée d'affichage du snap après ouverture (en secondes)
  /// 0 = vue unique, null = 10s par défaut
  final int? snapDurationSec;

  /// Réactions : { emoji: [userId, ...] }
  final Map<String, List<String>> reactions;

  /// Réponse à un message normal
  final MessageModel? replyTo;

  /// Réponse à une story
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
    this.disappearsAt,
    this.isOpened = false,
    this.audioDurationSec,
    this.snapDurationSec,
    this.reactions = const {},
    this.replyTo,
    this.storyReply,
  });

  bool get isSnap => type == MessageType.snap;
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isDisappeared =>
      disappearsAt != null && DateTime.now().isAfter(disappearsAt!);
  bool get isMine => senderId == 'me';
  bool get isStoryReply => storyReply != null;
  bool get hasReactions =>
      reactions.isNotEmpty && reactions.values.any((v) => v.isNotEmpty);

  bool hasReacted(String emoji, String userId) =>
      reactions[emoji]?.contains(userId) ?? false;

  MessageModel copyWith({
    String? id,
    String? senderId,
    String? text,
    String? mediaUrl,
    MessageType? type,
    MessageStatus? status,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? disappearsAt,
    bool? isOpened,
    int? audioDurationSec,
    int? snapDurationSec,
    Map<String, List<String>>? reactions,
    MessageModel? replyTo,
    StoryReplyData? storyReply,
    bool clearPhoto = false,
  }) {
    return MessageModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      mediaUrl: clearPhoto ? null : (mediaUrl ?? this.mediaUrl),
      type: type ?? this.type,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      disappearsAt: disappearsAt ?? this.disappearsAt,
      isOpened: isOpened ?? this.isOpened,
      audioDurationSec: audioDurationSec ?? this.audioDurationSec,
      snapDurationSec: snapDurationSec ?? this.snapDurationSec,
      reactions: reactions ?? this.reactions,
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
