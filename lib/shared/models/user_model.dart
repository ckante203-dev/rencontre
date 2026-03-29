// lib/shared/models/user_model.dart

class UserModel {
  final String id;
  final String name;
  final int age;
  final String? bio;
  final String? photoUrl;
  final List<String> photoUrls;
  final List<String> interests;
  final double? latitude;
  final double? longitude;
  final String? gender;
  final String? lookingFor;
  final bool isOnline;
  final DateTime? lastSeen;
  final double? distanceMeters;
  final int followersCount;
  final int followingCount;
  final int matchesCount;
  final int? taille;
  final int? poids;
  final String? morphologie;
  final String? lieuRencontre;
  // ✅ Nouveau — date d'inscription pour le badge "Nouveau membre"
  final DateTime? createdAt;

  const UserModel({
    required this.id,
    required this.name,
    required this.age,
    this.bio,
    this.photoUrl,
    this.photoUrls = const [],
    this.interests = const [],
    this.latitude,
    this.longitude,
    this.gender,
    this.lookingFor,
    this.isOnline = false,
    this.lastSeen,
    this.distanceMeters,
    this.followersCount = 0,
    this.followingCount = 0,
    this.matchesCount = 0,
    this.taille,
    this.poids,
    this.morphologie,
    this.lieuRencontre,
    this.createdAt,
  });

  // ✅ Nouveau membre = inscrit depuis moins de 7 jours
  bool get isNewMember {
    if (createdAt == null) return false;
    return DateTime.now().difference(createdAt!).inDays < 7;
  }

  UserModel copyWith({
    String? id,
    String? name,
    int? age,
    String? bio,
    String? photoUrl,
    bool clearPhoto = false,
    List<String>? photoUrls,
    List<String>? interests,
    double? latitude,
    double? longitude,
    String? gender,
    String? lookingFor,
    bool? isOnline,
    DateTime? lastSeen,
    double? distanceMeters,
    int? followersCount,
    int? followingCount,
    int? matchesCount,
    int? taille,
    int? poids,
    String? morphologie,
    String? lieuRencontre,
    DateTime? createdAt,
  }) =>
      UserModel(
        id: id ?? this.id,
        name: name ?? this.name,
        age: age ?? this.age,
        bio: bio ?? this.bio,
        photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
        photoUrls: photoUrls ?? this.photoUrls,
        interests: interests ?? this.interests,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        gender: gender ?? this.gender,
        lookingFor: lookingFor ?? this.lookingFor,
        isOnline: isOnline ?? this.isOnline,
        lastSeen: lastSeen ?? this.lastSeen,
        distanceMeters: distanceMeters ?? this.distanceMeters,
        followersCount: followersCount ?? this.followersCount,
        followingCount: followingCount ?? this.followingCount,
        matchesCount: matchesCount ?? this.matchesCount,
        taille: taille ?? this.taille,
        poids: poids ?? this.poids,
        morphologie: morphologie ?? this.morphologie,
        lieuRencontre: lieuRencontre ?? this.lieuRencontre,
        createdAt: createdAt ?? this.createdAt,
      );

  /// "175cm · 70kg"
  String get corpsMesures {
    final parts = <String>[];
    if (taille != null) parts.add('${taille}cm');
    if (poids != null) parts.add('${poids}kg');
    return parts.join(' · ');
  }

  String get distanceLabel {
    if (distanceMeters == null) return '';
    if (distanceMeters! < 1000) return '${distanceMeters!.toInt()}m';
    return '${(distanceMeters! / 1000).toStringAsFixed(1)}km';
  }
}
