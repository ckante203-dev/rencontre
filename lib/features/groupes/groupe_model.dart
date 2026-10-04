// ─── DISCUSSIONS DE GROUPE ────────────────────────────────────────
// Groupes d'amis (50 membres max) ou groupe automatique d'un événement
// (SQL 036). Messages gardés 7 jours.

/// Un groupe dans la liste « Groupes » de Messages (RPC mes_groupes).
class GroupeResume {
  final String id;
  final String nom;
  final String? photoUrl;
  final String? evenementId;
  final int nbMembres;
  final bool suisAdmin;
  final bool sourdine;
  final String? dernierType;
  final String? dernierContenu;
  final String? dernierAuteur;
  final DateTime derniereActivite;
  final int nonLus;

  const GroupeResume({
    required this.id,
    required this.nom,
    this.photoUrl,
    this.evenementId,
    this.nbMembres = 0,
    this.suisAdmin = false,
    this.sourdine = false,
    this.dernierType,
    this.dernierContenu,
    this.dernierAuteur,
    required this.derniereActivite,
    this.nonLus = 0,
  });

  bool get estEvenement => evenementId != null;

  factory GroupeResume.fromJson(Map<String, dynamic> j) => GroupeResume(
        id: j['id'] as String,
        nom: (j['nom'] as String?) ?? 'Groupe',
        photoUrl: j['photo_url'] as String?,
        evenementId: j['evenement_id'] as String?,
        nbMembres: (j['nb_membres'] as num?)?.toInt() ?? 0,
        suisAdmin: j['mon_role'] == 'admin',
        sourdine: j['sourdine'] == true,
        dernierType: j['dernier_type'] as String?,
        dernierContenu: j['dernier_contenu'] as String?,
        dernierAuteur: j['dernier_auteur'] as String?,
        derniereActivite:
            DateTime.tryParse(j['derniere_activite']?.toString() ?? '')
                    ?.toLocal() ??
                DateTime.now(),
        nonLus: (j['non_lus'] as num?)?.toInt() ?? 0,
      );

  /// « Awa : on se retrouve à l'entrée », « 📷 Photo », « GIF »…
  String get apercu {
    switch (dernierType) {
      case null:
        return 'Aucun message';
      case 'systeme':
        return dernierContenu ?? '';
      case 'image':
        return '${dernierAuteur ?? 'Quelqu\'un'} : 📷 Photo';
      case 'giphy':
        return '${dernierAuteur ?? 'Quelqu\'un'} : GIF';
      default:
        return '${dernierAuteur ?? 'Quelqu\'un'} : ${dernierContenu ?? ''}';
    }
  }
}

/// Un message de groupe.
class MessageGroupe {
  final String id;
  final String groupeId;
  final String? senderId; // null = message système
  final String type; // texte, image, giphy, systeme
  final String? contenu;
  final String? mediaPath;
  final DateTime createdAt;

  const MessageGroupe({
    required this.id,
    required this.groupeId,
    this.senderId,
    this.type = 'texte',
    this.contenu,
    this.mediaPath,
    required this.createdAt,
  });

  bool get estSysteme => type == 'systeme';

  factory MessageGroupe.fromJson(Map<String, dynamic> j) => MessageGroupe(
        id: j['id'] as String,
        groupeId: j['groupe_id'] as String,
        senderId: j['sender_id'] as String?,
        type: (j['type'] as String?) ?? 'texte',
        contenu: j['contenu'] as String?,
        mediaPath: j['media_path'] as String?,
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '')
                ?.toLocal() ??
            DateTime.now(),
      );
}

/// Un membre du groupe (nom / photo pour afficher les messages).
class MembreGroupe {
  final String id;
  final String nom;
  final String? photoUrl;
  final bool admin;
  const MembreGroupe(
      {required this.id, required this.nom, this.photoUrl, this.admin = false});
}
