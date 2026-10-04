// ─── ÉVÉNEMENTS (match, concert, festival…) ───────────────────────
// Créés par Zamu depuis le panneau d'admin. Les utilisateurs indiquent
// « J'y vais » ; seuls les participants voient qui vient (SQL 034).

class EvenementModel {
  final String id;
  final String titre;
  final String? description;
  final String categorie; // sport, concert, soiree, festival, autre
  final String lieu;
  final String? ville;
  final double? latitude;
  final double? longitude;
  final DateTime debut;
  final DateTime? fin;
  final String? imageUrl;
  final bool annule;
  final int nbParticipants;
  final bool jeParticipe;

  const EvenementModel({
    required this.id,
    required this.titre,
    this.description,
    this.categorie = 'autre',
    required this.lieu,
    this.ville,
    this.latitude,
    this.longitude,
    required this.debut,
    this.fin,
    this.imageUrl,
    this.annule = false,
    this.nbParticipants = 0,
    this.jeParticipe = false,
  });

  factory EvenementModel.fromJson(Map<String, dynamic> j) => EvenementModel(
        id: j['id'] as String,
        titre: (j['titre'] as String?) ?? 'Événement',
        description: j['description'] as String?,
        categorie: (j['categorie'] as String?) ?? 'autre',
        lieu: (j['lieu'] as String?) ?? '',
        ville: j['ville'] as String?,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        debut: DateTime.parse(j['debut'] as String).toLocal(),
        fin: j['fin'] == null
            ? null
            : DateTime.parse(j['fin'] as String).toLocal(),
        imageUrl: j['image_url'] as String?,
        annule: j['statut'] == 'annule',
        nbParticipants: (j['nb_participants'] as num?)?.toInt() ?? 0,
        jeParticipe: j['je_participe'] == true,
      );

  EvenementModel copyWith({int? nbParticipants, bool? jeParticipe}) =>
      EvenementModel(
        id: id,
        titre: titre,
        description: description,
        categorie: categorie,
        lieu: lieu,
        ville: ville,
        latitude: latitude,
        longitude: longitude,
        debut: debut,
        fin: fin,
        imageUrl: imageUrl,
        annule: annule,
        nbParticipants: nbParticipants ?? this.nbParticipants,
        jeParticipe: jeParticipe ?? this.jeParticipe,
      );

  /// Fin effective : la fin indiquée, sinon 12 h après le début.
  DateTime get finEffective => fin ?? debut.add(const Duration(hours: 12));
  bool get enCours {
    final n = DateTime.now();
    return !annule && n.isAfter(debut) && n.isBefore(finEffective);
  }

  String get emoji => switch (categorie) {
        'sport' => '⚽',
        'concert' => '🎤',
        'soiree' => '🎉',
        'festival' => '🎪',
        _ => '📅',
      };

  String get libelleCategorie => switch (categorie) {
        'sport' => 'Sport',
        'concert' => 'Concert',
        'soiree' => 'Soirée',
        'festival' => 'Festival',
        _ => 'Événement',
      };

  String get lieuComplet =>
      (ville ?? '').isEmpty ? lieu : '$lieu · $ville';

  static const _jours = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
  static const _mois = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
  ];

  static String heure(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';

  /// « Aujourd'hui · 20h00 », « Demain · 16h00 », « sam. 12 oct. · 20h00 »
  String get dateCourte {
    if (enCours) return 'En ce moment';
    final n = DateTime.now();
    final aujourdhui = DateTime(n.year, n.month, n.day);
    final jour = DateTime(debut.year, debut.month, debut.day);
    final ecart = jour.difference(aujourdhui).inDays;
    final h = heure(debut);
    if (ecart == 0) return 'Aujourd\'hui · $h';
    if (ecart == 1) return 'Demain · $h';
    return '${_jours[debut.weekday - 1]} ${debut.day} ${_mois[debut.month - 1]} · $h';
  }

  /// « samedi 12 octobre, 20h00 – 23h00 » (écran de détail)
  String get dateLongue {
    const jours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
    const mois = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
      'août', 'septembre', 'octobre', 'novembre', 'décembre',
    ];
    final base =
        '${jours[debut.weekday - 1]} ${debut.day} ${mois[debut.month - 1]}, ${heure(debut)}';
    return fin == null ? base : '$base – ${heure(fin!)}';
  }
}
