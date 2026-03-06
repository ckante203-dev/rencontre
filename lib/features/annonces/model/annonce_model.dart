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
  final bool isAnonyme;      // ← nouveau
  final String? mediaUrl;    // ← nouveau
  final bool isVideo;        // ← nouveau

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
  });

  bool get isActive =>
    boostedUntil == null || DateTime.now().isBefore(boostedUntil!);
}