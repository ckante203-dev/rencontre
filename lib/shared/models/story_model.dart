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
  final double? distanceKm;
  final bool hasChatted;
  final bool isPinned; // ✅ NOUVEAU

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
    this.distanceKm,
    this.hasChatted = false,
    this.isPinned = false, // ✅ NOUVEAU
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isActive => !isExpired;

  StoryModel copyWith({bool? isSeen, bool? isPinned}) {
    return StoryModel(
      id: id,
      userId: userId,
      userName: userName,
      userPhotoUrl: userPhotoUrl,
      mediaUrl: mediaUrl,
      isVideo: isVideo,
      caption: caption,
      createdAt: createdAt,
      expiresAt: expiresAt,
      viewedBy: viewedBy,
      isSeen: isSeen ?? this.isSeen,
      distanceKm: distanceKm,
      hasChatted: hasChatted,
      isPinned: isPinned ?? this.isPinned, // ✅ NOUVEAU
    );
  }
}
