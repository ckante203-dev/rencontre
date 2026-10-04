import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/evenements/evenement_model.dart';

/// Une personne qui vient au même événement que moi.
class ParticipantEvenement {
  final String id;
  final String nom;
  final String? photoUrl;
  final String? pseudo;
  final bool enLigne;
  const ParticipantEvenement(
      {required this.id,
      required this.nom,
      this.photoUrl,
      this.pseudo,
      this.enLigne = false});
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

  Future<void> charger() async {
    if (supabase.auth.currentUser == null) return;
    chargement.value = true;
    try {
      final rows = await supabase.rpc('evenements_a_venir') as List;
      evenements.assignAll(rows
          .map((r) => EvenementModel.fromJson(Map<String, dynamic>.from(r))));
      await _chargerMemeEvenement();
    } catch (e) {
      debugPrint('evenements_a_venir : $e'); // script SQL 034 absent ?
    } finally {
      chargement.value = false;
    }
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

  /// « J'y vais » / « Je n'y vais plus ». Renvoie l'événement à jour.
  Future<EvenementModel?> basculerParticipation(EvenementModel ev) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return null;
    final y = !ev.jeParticipe;
    final maj = ev.copyWith(
        jeParticipe: y,
        nbParticipants: (ev.nbParticipants + (y ? 1 : -1)).clamp(0, 1 << 30));
    _remplacer(maj);
    try {
      if (y) {
        await supabase.from('evenement_participants').upsert(
            {'evenement_id': ev.id, 'user_id': uid},
            ignoreDuplicates: true);
      } else {
        await supabase
            .from('evenement_participants')
            .delete()
            .eq('evenement_id', ev.id)
            .eq('user_id', uid);
      }
      _chargerMemeEvenement();
      return maj;
    } catch (e) {
      debugPrint('participation : $e');
      _remplacer(ev);
      Get.snackbar('Oups', 'Impossible d\'enregistrer, vérifie ta connexion',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white);
      return ev;
    }
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
              ))
          .toList();
    } catch (e) {
      debugPrint('participants_evenement : $e');
      return const [];
    }
  }
}
