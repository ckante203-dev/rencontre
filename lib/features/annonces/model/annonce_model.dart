// lib/features/annonces/model/annonce_model.dart

class AnnonceModel {
  final String id;
  final String userId;
  final String userName;
  final String? userPhotoUrl;
  final int userAge;
  final String titre;
  final String description;
  final String categorie;
  final String? ville;
  final DateTime createdAt;
  final int likes;
  final bool isLiked;
  final String myReaction; // ✅ réaction de l'utilisateur ('', '❤️', '😂', etc.)
  final Map<String, int> reactionCounts; // ✅ {'❤️': 5, '😂': 2}
  final bool isBoosted;
  final DateTime? boostedUntil;
  final bool isAnonyme;
  final String? mediaUrl;
  final bool isVideo;
  final int reponsesCount;
  final bool commentsEnabled;
  final int viewsCount; // ✅ compteur de vues
  final bool isViewed; // ✅ déjà vue par l'utilisateur
  final String? pinnedCommentId; // ✅ commentaire épinglé

  const AnnonceModel({
    required this.id,
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
    required this.userAge,
    required this.titre,
    required this.description,
    required this.categorie,
    this.ville,
    required this.createdAt,
    this.likes = 0,
    this.isLiked = false,
    this.myReaction = '',
    this.reactionCounts = const {},
    this.isBoosted = false,
    this.boostedUntil,
    this.isAnonyme = false,
    this.mediaUrl,
    this.isVideo = false,
    this.reponsesCount = 0,
    this.commentsEnabled = true,
    this.viewsCount = 0,
    this.isViewed = false,
    this.pinnedCommentId,
  });

  bool get isActive =>
      boostedUntil == null || DateTime.now().isBefore(boostedUntil!);

  // Emoji le plus utilisé
  String get topReactionEmoji {
    if (reactionCounts.isEmpty) return '❤️';
    return reactionCounts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }

  AnnonceModel copyWith({
    int? likes,
    bool? isLiked,
    String? myReaction,
    Map<String, int>? reactionCounts,
    int? reponsesCount,
    int? viewsCount,
    bool? isViewed,
    String? pinnedCommentId,
    bool clearPinnedComment = false,
  }) {
    return AnnonceModel(
      id: id,
      userId: userId,
      userName: userName,
      userPhotoUrl: userPhotoUrl,
      userAge: userAge,
      titre: titre,
      description: description,
      categorie: categorie,
      ville: ville,
      createdAt: createdAt,
      likes: likes ?? this.likes,
      isLiked: isLiked ?? this.isLiked,
      myReaction: myReaction ?? this.myReaction,
      reactionCounts: reactionCounts ?? this.reactionCounts,
      isBoosted: isBoosted,
      boostedUntil: boostedUntil,
      isAnonyme: isAnonyme,
      mediaUrl: mediaUrl,
      isVideo: isVideo,
      reponsesCount: reponsesCount ?? this.reponsesCount,
      commentsEnabled: commentsEnabled,
      viewsCount: viewsCount ?? this.viewsCount,
      isViewed: isViewed ?? this.isViewed,
      pinnedCommentId:
          clearPinnedComment ? null : (pinnedCommentId ?? this.pinnedCommentId),
    );
  }
}
