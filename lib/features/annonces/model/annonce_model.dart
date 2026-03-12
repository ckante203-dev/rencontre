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
  final bool isBoosted;
  final DateTime? boostedUntil;
  final bool isAnonyme;
  final String? mediaUrl;
  final bool isVideo;
  final int reponsesCount;
  final bool commentsEnabled;

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
    this.isBoosted = false,
    this.boostedUntil,
    this.isAnonyme = false,
    this.mediaUrl,
    this.isVideo = false,
    this.reponsesCount = 0,
    this.commentsEnabled = true,
  });

  bool get isActive =>
      boostedUntil == null || DateTime.now().isBefore(boostedUntil!);
}
