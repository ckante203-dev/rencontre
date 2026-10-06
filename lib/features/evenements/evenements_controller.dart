import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/evenements/ecran_evenement.dart';
import 'package:rencontre/features/evenements/evenement_model.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';

/// Une personne qui participe au même événement que moi.
class ParticipantEvenement {
  final String id;
  final String nom;
  final String? photoUrl;
  final String? pseudo;
  final bool enLigne;
  final bool surPlace;
  final bool interesse; // « Intéressé » (sinon « J'y vais »)
  final bool estMatch;
  final bool jeLike;
  final bool dispo;
  const ParticipantEvenement({
    required this.id,
    required this.nom,
    this.photoUrl,
    this.pseudo,
    this.enLigne = false,
    this.surPlace = false,
    this.interesse = false,
    this.estMatch = false,
    this.jeLike = false,
    this.dispo = false,
  });
}

class EvenementsController extends GetxController {
  static EvenementsController get to => Get.find<EvenementsController>();

  final RxList<EvenementModel> evenements = <EvenementModel>[].obs;
  final RxBool chargement = false.obs;

  /// Personnes qui vont aux mêmes événements que moi : id → titre.
  /// Sert au badge 📅 et au filtre « Même événement » de l'accueil.
  final RxMap<String, String> memeEvenement = <String, String>{}.obs;

  @override
  void onInit() {
    super.onInit();
    charger();
  }

  void _snack(String titre, String msg) => Get.snackbar(titre, msg,
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface,
      colorText: AppColors.textPrimary);

  Future<void> charger() async {
    if (supabase.auth.currentUser == null) return;
    chargement.value = true;
    try {
      final rows = await supabase.rpc('evenements_a_venir') as List;
      final liste = rows
          .map((r) => EvenementModel.fromJson(Map<String, dynamic>.from(r)))
          .toList();
      evenements.assignAll(_trierParDistance(liste));
      await _chargerMemeEvenement();
    } catch (e) {
      debugPrint('evenements_a_venir : $e'); // script SQL 034 / 035 absent ?
    } finally {
      chargement.value = false;
    }
  }

  /// En cours d'abord ; puis ceux à moins de 100 km (ou sans position),
  /// par date ; puis les lointains, par date.
  List<EvenementModel> _trierParDistance(List<EvenementModel> liste) {
    final moi = Get.isRegistered<HomeController>()
        ? Get.find<HomeController>().myProfile
        : null;
    final lat = moi?.latitude, lng = moi?.longitude;
    final avecDistance = [
      for (final e in liste)
        (lat != null && lng != null && e.latitude != null && e.longitude != null)
            ? e.copyWith(
                distanceKm: _km(lat, lng, e.latitude!, e.longitude!))
            : e,
    ];
    int rang(EvenementModel e) {
      if (e.enCours) return 0;
      if (e.distanceKm == null || e.distanceKm! <= 100) return 1;
      return 2;
    }

    avecDistance.sort((a, b) {
      final r = rang(a).compareTo(rang(b));
      return r != 0 ? r : a.debut.compareTo(b.debut);
    });
    return avecDistance;
  }

  static double _km(double lat1, double lng1, double lat2, double lng2) {
    double rad(double d) => d * pi / 180;
    final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(rad(lat1)) * cos(rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return 6371 * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  Future<void> _chargerMemeEvenement() async {
    if (!evenements.any((e) => e.jeParticipe)) {
      memeEvenement.clear();
      return;
    }
    try {
      final rows = await supabase.rpc('participants_mes_evenements') as List;
      memeEvenement.assignAll({
        for (final r in rows)
          r['user_id'] as String: (r['titre'] as String?) ?? 'Événement',
      });
    } catch (e) {
      debugPrint('participants_mes_evenements : $e');
    }
  }

  /// Choisir « y_va » / « interesse », ou null pour ne plus participer.
  /// Renvoie l'événement à jour.
  Future<EvenementModel> participer(EvenementModel ev, String? statut) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null || statut == ev.maParticipation) return ev;
    int compte(String s, int n) =>
        n + (statut == s ? 1 : 0) - (ev.maParticipation == s ? 1 : 0);
    final maj = ev.copyWith(
      maParticipation: statut ?? '',
      nbParticipants: max(0, compte('y_va', ev.nbParticipants)),
      nbInteresses: max(0, compte('interesse', ev.nbInteresses)),
      jeSuisSurPlace: statut == null ? false : null,
    );
    _remplacer(maj);
    try {
      if (statut == null) {
        await supabase
            .from('evenement_participants')
            .delete()
            .eq('evenement_id', ev.id)
            .eq('user_id', uid);
      } else if (ev.jeParticipe) {
        await supabase
            .from('evenement_participants')
            .update({'statut': statut})
            .eq('evenement_id', ev.id)
            .eq('user_id', uid);
      } else {
        await supabase.from('evenement_participants').insert(
            {'evenement_id': ev.id, 'user_id': uid, 'statut': statut});
      }
      _chargerMemeEvenement();
      return maj;
    } catch (e) {
      debugPrint('participation : $e');
      _remplacer(ev);
      _snack('Oups', 'Impossible d\'enregistrer, vérifie ta connexion');
      return ev;
    }
  }

  /// « 📍 Je suis sur place » : position GPS vérifiée par la base.
  Future<EvenementModel> marquerSurPlace(EvenementModel ev) async {
    Position? pos;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _snack('Position nécessaire',
            'Autorise la localisation pour confirmer que tu es sur place');
        return ev;
      }
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
    } catch (_) {
      pos = await Geolocator.getLastKnownPosition();
    }
    try {
      final r = await supabase.rpc('marquer_sur_place', params: {
        'p_ev': ev.id,
        'p_lat': pos?.latitude,
        'p_lng': pos?.longitude,
      }) as String?;
      switch (r) {
        case 'ok':
          final maj = ev.copyWith(
            maParticipation: 'y_va',
            jeSuisSurPlace: true,
            nbSurPlace: ev.jeSuisSurPlace ? ev.nbSurPlace : ev.nbSurPlace + 1,
            nbParticipants:
                ev.jYVais ? ev.nbParticipants : ev.nbParticipants + 1,
            nbInteresses: ev.maParticipation == 'interesse'
                ? max(0, ev.nbInteresses - 1)
                : ev.nbInteresses,
          );
          _remplacer(maj);
          _chargerMemeEvenement();
          _snack('📍 Tu es sur place !',
              'Les autres participants le voient maintenant');
          return maj;
        case 'trop_loin':
          _snack('Pas encore sur place',
              'Il faut être à moins de 1,5 km du lieu de l\'événement');
        case 'pas_en_cours':
          _snack('Pas encore commencé',
              'Possible à partir d\'1 h avant le début');
        default:
          _snack('Oups', 'Événement introuvable');
      }
    } catch (e) {
      debugPrint('marquer_sur_place : $e');
      _snack('Oups', 'Impossible de confirmer, vérifie ta connexion');
    }
    return ev;
  }

  void _remplacer(EvenementModel ev) {
    final i = evenements.indexWhere((e) => e.id == ev.id);
    if (i >= 0) evenements[i] = ev;
  }

  /// Qui vient (la base ne répond que si je participe moi-même).
  Future<List<ParticipantEvenement>> participants(String evenementId) async {
    try {
      final rows = await supabase.rpc('participants_evenement',
          params: {'p_ev': evenementId}) as List;
      return rows
          .map((r) => ParticipantEvenement(
                id: r['id'] as String,
                nom: (r['name'] as String?) ?? 'Utilisateur',
                photoUrl: r['photo_url'] as String?,
                pseudo: r['username'] as String?,
                enLigne: r['en_ligne'] == true,
                surPlace: r['sur_place'] == true,
                interesse: r['statut'] == 'interesse',
                estMatch: r['est_match'] == true,
                jeLike: r['je_like'] == true,
                dispo: r['dispo'] == true,
              ))
          .toList();
    } catch (e) {
      debugPrint('participants_evenement : $e');
      return const [];
    }
  }

  /// Notification « événement » touchée : ouvre l'écran de l'événement.
  Future<void> ouvrirParId(String id) async {
    if (!evenements.any((e) => e.id == id)) await charger();
    var ev = evenements.firstWhereOrNull((e) => e.id == id);
    // Événement terminé (« Tu as croisé… ») : chargé à part (SQL 044)
    if (ev == null) {
      try {
        final rows = await supabase
            .rpc('evenement_par_id', params: {'p_ev': id}) as List;
        if (rows.isNotEmpty) {
          ev = EvenementModel.fromJson(Map<String, dynamic>.from(rows.first));
        }
      } catch (e) {
        debugPrint('evenement_par_id : $e');
      }
    }
    if (ev == null) {
      _snack('Événement terminé', 'Cet événement n\'est plus disponible');
      return;
    }
    final aOuvrir = ev;
    Get.to(() => EcranEvenement(evenement: aOuvrir));
  }

  /// Événement auquel je participe et qui a lieu maintenant (pour
  /// rattacher une story), sinon null.
  EvenementModel? get evenementEnCoursPourMoi => evenements
      .firstWhereOrNull((e) => e.jeParticipe && e.surPlacePossible);

  /// Proposition d'un utilisateur : publiée après validation par Zamu.
  Future<bool> proposer({
    required String titre,
    required String categorie,
    required String lieu,
    String? ville,
    String? description,
    required DateTime debut,
    DateTime? fin,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      await supabase.from('evenements').insert({
        'titre': titre,
        'categorie': categorie,
        'lieu': lieu,
        'ville': (ville ?? '').isEmpty ? null : ville,
        'description': (description ?? '').isEmpty ? null : description,
        'debut': debut.toUtc().toIso8601String(),
        'fin': fin?.toUtc().toIso8601String(),
        'statut': 'en_attente',
        'cree_par': uid,
      });
      return true;
    } catch (e) {
      final m = e.toString();
      _snack(
          'Proposition non envoyée',
          m.contains('premium_requis')
              ? 'Proposer un événement est réservé aux membres Premium 👑'
              : m.contains('trop_de_propositions')
              ? 'Tu as déjà 3 propositions en attente de validation'
              : m.contains('date_passee')
                  ? 'La date doit être dans le futur'
                  : 'Vérifie ta connexion et réessaie');
      return false;
    }
  }
}
