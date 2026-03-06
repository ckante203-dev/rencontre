class StoryModel {
  final String id;
  final String userId;
  final String userName;
  final String? userPhotoUrl;
  final String mediaUrl;
  final bool isVideo;
  final String? caption;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<String> viewedBy;
  final bool isSeen;

  const StoryModel({
    required this.id,
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
    required this.mediaUrl,
    this.isVideo = false,
    this.caption,
    required this.createdAt,
    required this.expiresAt,
    this.viewedBy = const [],
    this.isSeen = false,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isActive => !isExpired;
  Duration get remainingTime => expiresAt.difference(DateTime.now());
}