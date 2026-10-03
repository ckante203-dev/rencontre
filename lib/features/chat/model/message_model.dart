// ═══════════════════════════════════════════════════════════════════
//  ENUMS
// ═══════════════════════════════════════════════════════════════════

enum MessageType { text, image, snap, audio, location, annonceReply }

enum MessageStatus { sending, sent, delivered, read }

// ═══════════════════════════════════════════════════════════════════
//  STORY REPLY DATA
// ═══════════════════════════════════════════════════════════════════

class StoryReplyData {
  final String storyId;
  final String storyPreviewUrl;
  final bool storyIsVideo;
  final String storyOwnerName;
  // Story texte : texte et couleur de fond conservés dans le message
  // (colonnes messages.story_text / story_bg_color).
  final String? storyText;
  final String? storyBgColor;

  const StoryReplyData({
    required this.storyId,
    required this.storyPreviewUrl,
    required this.storyIsVideo,
    required this.storyOwnerName,
    this.storyText,
    this.storyBgColor,
  });

  bool get isTextStory => storyPreviewUrl.isEmpty;

  /// Colonnes de `messages` décrivant la story à laquelle on répond.
  Map<String, dynamic> toColumns({bool withText = true}) => {
        'story_id': storyId,
        'story_preview_url': storyPreviewUrl,
        'story_is_video': storyIsVideo,
        'topic': '📸 Story de $storyOwnerName',
        if (withText && storyText != null) 'story_text': storyText,
        if (withText && storyBgColor != null) 'story_bg_color': storyBgColor,
      };
}

// ═══════════════════════════════════════════════════════════════════
//  ANNONCE REPLY DATA — comme répondre à un statut WhatsApp
// ═══════════════════════════════════════════════════════════════════

class AnnonceReplyData {
  final String annonceId;
  final String annonceTitre;
  final String annonceDescription;
  final String? annonceMediaUrl;
  final bool annonceIsVideo;
  final String annonceAuteur;
  final String annonceCategorie;

  const AnnonceReplyData({
    required this.annonceId,
    required this.annonceTitre,
    required this.annonceDescription,
    this.annonceMediaUrl,
    this.annonceIsVideo = false,
    required this.annonceAuteur,
    required this.annonceCategorie,
  });

  Map<String, dynamic> toJson() => {
        'annonceId': annonceId,
        'annonceTitre': annonceTitre,
        'annonceDescription': annonceDescription,
        'annonceMediaUrl': annonceMediaUrl,
        'annonceIsVideo': annonceIsVideo,
        'annonceAuteur': annonceAuteur,
        'annonceCategorie': annonceCategorie,
      };

  factory AnnonceReplyData.fromJson(Map<String, dynamic> json) =>
      AnnonceReplyData(
        annonceId: json['annonceId'] ?? '',
        annonceTitre: json['annonceTitre'] ?? '',
        annonceDescription: json['annonceDescription'] ?? '',
        annonceMediaUrl: json['annonceMediaUrl'],
        annonceIsVideo: json['annonceIsVideo'] ?? false,
        annonceAuteur: json['annonceAuteur'] ?? '',
        annonceCategorie: json['annonceCategorie'] ?? 'rencontre',
      );
}

// ═══════════════════════════════════════════════════════════════════
//  MESSAGE MODEL
// ═══════════════════════════════════════════════════════════════════

class MessageModel {
  final String id;
  final String senderId;
  final String? text;
  final String? mediaUrl;
  final MessageType type;
  final MessageStatus status;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? disappearsAt;
  // Date de lecture par le destinataire (remplie par le serveur).
  final DateTime? readAt;
  final bool isOpened;
  final int? audioDurationSec;
  final int? snapDurationSec;
  final Map<String, List<String>> reactions;
  final MessageModel? replyTo;
  final StoryReplyData? storyReply;
  // Date de modification du texte (null = jamais modifié)
  final DateTime? modifieLe;

  // Réponse à une annonce (style WhatsApp statut)
  final AnnonceReplyData? annonceReply;

  const MessageModel({
    required this.id,
    required this.senderId,
    this.text,
    this.mediaUrl,
    required this.type,
    this.status = MessageStatus.sent,
    required this.createdAt,
    this.expiresAt,
    this.disappearsAt,
    this.readAt,
    this.isOpened = false,
    this.audioDurationSec,
    this.snapDurationSec,
    this.reactions = const {},
    this.replyTo,
    this.storyReply,
    this.annonceReply,
    this.modifieLe,
  });

  /// On peut modifier son message texte pendant 15 minutes (WhatsApp).
  static const delaiModification = Duration(minutes: 15);
  bool get modifiable =>
      type == MessageType.text &&
      storyReply == null &&
      !id.startsWith('temp_') &&
      DateTime.now().difference(createdAt) < delaiModification;

  bool get isSnap => type == MessageType.snap;
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  // ✅ Règle éphémère : un message disparaît 24h après avoir été lu
  // (le serveur le supprime ensuite, fichier compris).
  static const dureeApresLecture = Duration(hours: 24);
  bool get isDisappeared =>
      (disappearsAt != null && DateTime.now().isAfter(disappearsAt!)) ||
      (readAt != null &&
          DateTime.now().isAfter(readAt!.add(dureeApresLecture)));

  // ✅ FIX : "isMine" ne peut pas être un getter sans argument — il ne
  // connaît jamais l'utilisateur courant. L'ancienne version comparait
  // senderId à la chaîne littérale "me", qui ne correspond à aucun vrai
  // UUID Supabase, donc elle renvoyait toujours false. On la transforme
  // en méthode qui reçoit l'ID de l'utilisateur courant.
  bool isMine(String? currentUserId) =>
      currentUserId != null && senderId == currentUserId;

  bool get isStoryReply => storyReply != null;
  bool get isAnnonceReply => annonceReply != null;
  bool get hasReactions =>
      reactions.isNotEmpty && reactions.values.any((v) => v.isNotEmpty);

  bool hasReacted(String emoji, String userId) =>
      reactions[emoji]?.contains(userId) ?? false;

  MessageModel copyWith({
    String? id,
    String? senderId,
    String? text,
    String? mediaUrl,
    MessageType? type,
    MessageStatus? status,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? disappearsAt,
    DateTime? readAt,
    bool? isOpened,
    int? audioDurationSec,
    int? snapDurationSec,
    Map<String, List<String>>? reactions,
    MessageModel? replyTo,
    StoryReplyData? storyReply,
    AnnonceReplyData? annonceReply,
    DateTime? modifieLe,
    bool clearPhoto = false,
  }) {
    return MessageModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      mediaUrl: clearPhoto ? null : (mediaUrl ?? this.mediaUrl),
      type: type ?? this.type,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      disappearsAt: disappearsAt ?? this.disappearsAt,
      readAt: readAt ?? this.readAt,
      isOpened: isOpened ?? this.isOpened,
      audioDurationSec: audioDurationSec ?? this.audioDurationSec,
      snapDurationSec: snapDurationSec ?? this.snapDurationSec,
      reactions: reactions ?? this.reactions,
      replyTo: replyTo ?? this.replyTo,
      storyReply: storyReply ?? this.storyReply,
      annonceReply: annonceReply ?? this.annonceReply,
      modifieLe: modifieLe ?? this.modifieLe,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  CONVERSATION MODEL
// ═══════════════════════════════════════════════════════════════════

class ConversationModel {
  final String id;
  final String userId;
  final String userName;
  final String? userPhotoUrl;
  final bool isOnline;
  final MessageModel? lastMessage;
  final int unreadCount;
  final DateTime? lastActivity;
  final bool isPinned;
  // Série 🔥 : jours consécutifs avec au moins un message (calculée par la
  // base, conversations.flamme_compte / flamme_dernier_jour).
  final int flammeCompte;
  final DateTime? flammeDernierJour;

  const ConversationModel({
    required this.id,
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
    this.isOnline = false,
    this.lastMessage,
    this.unreadCount = 0,
    this.lastActivity,
    this.isPinned = false,
    this.flammeCompte = 0,
    this.flammeDernierJour,
  });

  /// « 2026-10-02 » (colonne date, jour d'Abidjan = UTC) → minuit UTC.
  /// DateTime.tryParse la lirait en heure LOCALE : hors UTC (France…), la
  /// série était décalée d'un jour.
  static DateTime? jourDepuisBase(dynamic valeur) {
    final d = DateTime.tryParse(valeur?.toString() ?? '');
    return d == null ? null : DateTime.utc(d.year, d.month, d.day);
  }

  static DateTime _jour(DateTime d) {
    final u = d.toUtc(); // jour d'Abidjan = jour UTC
    return DateTime.utc(u.year, u.month, u.day);
  }

  /// Série encore vivante : dernier message aujourd'hui ou hier.
  int get flammes {
    final dernier = flammeDernierJour;
    if (dernier == null) return 0;
    final ecart = _jour(DateTime.now()).difference(_jour(dernier)).inDays;
    return ecart <= 1 ? flammeCompte : 0;
  }

  /// Personne n'a encore écrit aujourd'hui : la série s'éteint à minuit.
  bool get flammeEnDanger {
    final dernier = flammeDernierJour;
    if (dernier == null || flammes < 2) return false;
    return _jour(DateTime.now()).difference(_jour(dernier)).inDays == 1;
  }

  /// Même règle que le trigger SQL, appliquée tout de suite à l'écran
  /// quand un message part ou arrive.
  ConversationModel avecMessageAujourdhui() {
    final aujourdhui = _jour(DateTime.now());
    final dernier =
        flammeDernierJour == null ? null : _jour(flammeDernierJour!);
    if (dernier == aujourdhui) return this;
    final suite = dernier != null && aujourdhui.difference(dernier).inDays == 1;
    return copyWith(
      flammeCompte: suite ? flammeCompte + 1 : 1,
      flammeDernierJour: aujourdhui,
    );
  }

  ConversationModel copyWith({
    String? userName,
    String? userPhotoUrl,
    bool? isOnline,
    MessageModel? lastMessage,
    int? unreadCount,
    DateTime? lastActivity,
    bool? isPinned,
    int? flammeCompte,
    DateTime? flammeDernierJour,
  }) {
    return ConversationModel(
      id: id,
      userId: userId,
      userName: userName ?? this.userName,
      userPhotoUrl: userPhotoUrl ?? this.userPhotoUrl,
      isOnline: isOnline ?? this.isOnline,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      lastActivity: lastActivity ?? this.lastActivity,
      isPinned: isPinned ?? this.isPinned,
      flammeCompte: flammeCompte ?? this.flammeCompte,
      flammeDernierJour: flammeDernierJour ?? this.flammeDernierJour,
    );
  }
}
