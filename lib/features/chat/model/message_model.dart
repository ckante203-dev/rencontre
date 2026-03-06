enum MessageType { text, image, snap, audio, location }
enum MessageStatus { sending, sent, delivered, read }

class MessageModel {
  final String id;
  final String senderId;
  final String? text;
  final String? mediaUrl;
  final MessageType type;
  final MessageStatus status;
  final DateTime createdAt;
  final DateTime? expiresAt; // pour les snaps éphémères
  final bool isOpened;       // snap ouvert ou non
  final int? audioDurationSec;

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
  });

  bool get isSnap => type == MessageType.snap;
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isMine => senderId == 'me'; // TODO: remplacer par Auth userId
}

class ConversationModel {
  final String id;
  final String userId;
  final String userName;
  final String? userPhotoUrl;
  final bool isOnline;
  final MessageModel? lastMessage;
  final int unreadCount;
  final DateTime? lastActivity;

  const ConversationModel({
    required this.id,
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
    this.isOnline = false,
    this.lastMessage,
    this.unreadCount = 0,
    this.lastActivity,
  });
}