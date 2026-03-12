// lib/features/annonces/model/annonce_comment_model.dart

class AnnonceCommentModel {
  final String id;
  final String annonceId;
  final String userId;
  final String userName;
  final String? userPhotoUrl;
  final bool isAnonyme;
  final String texte;
  final DateTime createdAt;
  final int likes;
  final bool isLiked;
  final String? parentId;
  final List<AnnonceCommentModel> replies;

  const AnnonceCommentModel({
    required this.id,
    required this.annonceId,
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
    this.isAnonyme = false,
    required this.texte,
    required this.createdAt,
    this.likes = 0,
    this.isLiked = false,
    this.parentId,
    this.replies = const [],
  });

  factory AnnonceCommentModel.fromMap(
    Map<String, dynamic> m, {
    String? myUid,
    List<AnnonceCommentModel> replies = const [],
  }) {
    final likedBy = List<String>.from(m['liked_by'] ?? []);
    return AnnonceCommentModel(
      id: m['id'] as String,
      annonceId: m['annonce_id'] as String,
      userId: m['user_id'] as String,
      userName: m['is_anonyme'] == true
          ? 'Anonyme'
          : (m['user_name'] ?? 'Utilisateur'),
      userPhotoUrl: m['is_anonyme'] == true ? null : m['user_photo_url'],
      isAnonyme: m['is_anonyme'] == true,
      texte: m['texte'] as String,
      createdAt: DateTime.parse(m['created_at'] as String),
      likes: likedBy.length,
      isLiked: myUid != null && likedBy.contains(myUid),
      parentId: m['parent_id'] as String?,
      replies: replies,
    );
  }

  AnnonceCommentModel copyWith({
    int? likes,
    bool? isLiked,
    List<AnnonceCommentModel>? replies,
  }) {
    return AnnonceCommentModel(
      id: id,
      annonceId: annonceId,
      userId: userId,
      userName: userName,
      userPhotoUrl: userPhotoUrl,
      isAnonyme: isAnonyme,
      texte: texte,
      createdAt: createdAt,
      parentId: parentId,
      likes: likes ?? this.likes,
      isLiked: isLiked ?? this.isLiked,
      replies: replies ?? this.replies,
    );
  }
}
