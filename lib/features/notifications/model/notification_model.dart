import 'package:get/get.dart';
class NotificationModel {
  final String id;
  final String userId;
  final String? actorId;
  final String actorName;
  final String? actorPhotoUrl;
  final String type;
  final String? referenceId;
  final String? preview;
  final bool isRead;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.userId,
    this.actorId,
    this.actorName = 'Quelqu\'un',
    this.actorPhotoUrl,
    required this.type,
    this.referenceId,
    this.preview,
    this.isRead = false,
    required this.createdAt,
  });

  String get message {
    switch (type) {
      case 'like':
        return 't\'a liké ❤️'.tr;
      case 'match':
        return 'et toi, c\'est un match 💘'.tr;
      case 'favori_story':
        return 'a publié une story ⭐'.tr;
      case 'album':
        return 't\'a ouvert son album privé 🔓'.tr;
      case 'ami_demande':
        return 'veut être ton ami 👥'.tr;
      case 'ami_accepte':
        return 'a accepté ta demande d\'ami 👥'.tr;
      case 'new_story':
        return 'a publié une nouvelle story'.tr;
      case 'like_story':
        return 'a aimé ta story'.tr;
      case 'new_annonce':
        return 'a publié une nouvelle annonce'.tr;
      case 'annonce_reaction':
        return preview != null
            ? 'a réagi @preview à ton annonce'.trParams({'preview': preview.toString()})
            : 'a réagi à ton annonce'.tr;
      default:
        return '';
    }
  }

  NotificationModel copyWith({bool? isRead}) => NotificationModel(
        id: id,
        userId: userId,
        actorId: actorId,
        actorName: actorName,
        actorPhotoUrl: actorPhotoUrl,
        type: type,
        referenceId: referenceId,
        preview: preview,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
      );
}