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
  final bool isOnline;
  final DateTime? lastSeen;
  final double? distanceMeters;
  final int followersCount;
  final int followingCount;
  final int matchesCount;

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
    this.isOnline = false,
    this.lastSeen,
    this.distanceMeters,
    this.followersCount = 0,
    this.followingCount = 0,
    this.matchesCount = 0,
  });

  UserModel copyWith({double? distanceMeters, bool? isOnline, String? gender}) => UserModel(
        id: id,
        name: name,
        age: age,
        bio: bio,
        photoUrl: photoUrl,
        photoUrls: photoUrls,
        interests: interests,
        latitude: latitude,
        longitude: longitude,
        gender: gender ?? this.gender,
        isOnline: isOnline ?? this.isOnline,
        lastSeen: lastSeen,
        distanceMeters: distanceMeters ?? this.distanceMeters,
        followersCount: followersCount,
        followingCount: followingCount,
        matchesCount: matchesCount,
      );

  String get distanceLabel {
    if (distanceMeters == null) return '';
    if (distanceMeters! < 1000) return '${distanceMeters!.toInt()}m';
    return '${(distanceMeters! / 1000).toStringAsFixed(1)}km';
  }
}