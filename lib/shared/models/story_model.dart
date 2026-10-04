import 'package:rencontre/features/home/widget/stickers_story.dart';

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
  final bool isPinned;
  final bool isPremium;
  final String visibility;
  // Auteur : en ligne (last_seen < 30 min) et accepte d'afficher sa distance.
  final bool isOnline;
  final bool showDistance;

  // ✅ NOUVEAU — story texte pur (pas de photo/vidéo)
  final String? textContent;
  final String? bgColor; // ex: "#FF3CAC", stocké en hex

  // Éditeur façon Snap : légende placée par l'auteur (centre, en fraction
  // de l'écran 0–1) et agrandie (échelle). null = légende classique en bas.
  final double? legendeX;
  final double? legendeY;
  final double? legendeEchelle;
  // Vidéo raccourcie : seul le passage [début, fin] est joué (ms).
  final int? videoDebutMs;
  final int? videoFinMs;
  // Stickers / emoji / GIF posés par l'auteur
  final List<StickerStory> stickers;

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
    this.isPinned = false,
    this.isPremium = false,
    this.visibility = 'public',
    this.isOnline = false,
    this.showDistance = true,
    this.textContent, // ✅ NOUVEAU
    this.bgColor, // ✅ NOUVEAU
    this.legendeX,
    this.legendeY,
    this.legendeEchelle,
    this.videoDebutMs,
    this.videoFinMs,
    this.stickers = const [],
  });

  bool get legendePlacee => legendeX != null && legendeY != null;

  /// Passage de la vidéo à jouer (null = toute la vidéo).
  Duration? get videoDebut =>
      videoDebutMs == null ? null : Duration(milliseconds: videoDebutMs!);
  Duration? get videoFin =>
      videoFinMs == null ? null : Duration(milliseconds: videoFinMs!);

  // ✅ Parse un horodatage renvoyé par Supabase. Si la chaîne n'a pas
  // d'indicateur de fuseau (colonne `timestamp` sans tz), Dart la lirait
  // comme heure LOCALE alors qu'elle est en UTC : on force alors l'UTC,
  // pour que les comparaisons avec DateTime.now() (expiration) soient
  // justes quel que soit le fuseau de l'appareil.
  static final RegExp _tzSuffix = RegExp(r'(Z|z|[+-]\d{2}(:?\d{2})?)$');

  static DateTime? tryParseDbTimestamp(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    final hasTime = s.contains('T') || s.contains(' ');
    if (hasTime && !_tzSuffix.hasMatch(s)) {
      return DateTime.tryParse('${s}Z');
    }
    return DateTime.tryParse(s);
  }

  static DateTime parseDbTimestamp(String raw) {
    final d = tryParseDbTimestamp(raw);
    if (d == null) throw FormatException('Horodatage invalide', raw);
    return d;
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isActive => !isExpired;

  // ✅ NOUVEAU — une story est "texte" si elle n'a pas de média mais
  // a bien du texte. Permet de distinguer facilement dans l'UI.
  bool get isTextStory =>
      mediaUrl.isEmpty && (textContent?.isNotEmpty ?? false);

  StoryModel copyWith({
    bool? isSeen,
    bool? isPinned,
    bool? isPremium,
    String? visibility,
    List<String>? viewedBy,
  }) {
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
      viewedBy: viewedBy ?? this.viewedBy,
      isSeen: isSeen ?? this.isSeen,
      distanceKm: distanceKm,
      hasChatted: hasChatted,
      isPinned: isPinned ?? this.isPinned,
      isPremium: isPremium ?? this.isPremium,
      visibility: visibility ?? this.visibility,
      isOnline: isOnline,
      showDistance: showDistance,
      textContent: textContent,
      bgColor: bgColor,
      legendeX: legendeX,
      legendeY: legendeY,
      legendeEchelle: legendeEchelle,
      videoDebutMs: videoDebutMs,
      videoFinMs: videoFinMs,
      stickers: stickers,
    );
  }
}
