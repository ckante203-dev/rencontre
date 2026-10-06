import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/groupes/ecran_groupe.dart';
import 'package:rencontre/features/groupes/groupe_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Liste de mes groupes (onglet « Groupes » de Messages), à jour en temps
/// réel : un nouveau message dans un de mes groupes recharge la liste.
class GroupesController extends GetxController {
  static GroupesController get to => Get.find<GroupesController>();

  final RxList<GroupeResume> groupes = <GroupeResume>[].obs;
  final RxBool chargement = false.obs;

  /// Groupe ouvert à l'écran (pas de notification pour lui).
  static String? groupeOuvert;

  RealtimeChannel? _canal;
  Timer? _attente;

  int get totalNonLus => groupes
      .where((g) => !g.sourdine)
      .fold(0, (n, g) => n + g.nonLus);

  @override
  void onInit() {
    super.onInit();
    charger();
    _ecouter();
  }

  @override
  void onClose() {
    _attente?.cancel();
    final c = _canal;
    _canal = null;
    if (c != null) supabase.removeChannel(c).catchError((_) => '');
    super.onClose();
  }

  Future<void> charger() async {
    if (supabase.auth.currentUser == null) return;
    chargement.value = groupes.isEmpty;
    try {
      final rows = await supabase.rpc('mes_groupes') as List;
      groupes.assignAll(
          rows.map((r) => GroupeResume.fromJson(Map<String, dynamic>.from(r))));
    } catch (e) {
      debugPrint('mes_groupes : $e'); // script SQL 036 absent ?
    } finally {
      chargement.value = false;
    }
  }

  // La base ne transmet que les messages de MES groupes (RLS)
  void _ecouter() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    _canal = supabase
        .channel('groupes-liste:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'groupe_messages',
          callback: (_) => _rechargerBientot(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'groupe_membres',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: uid),
          callback: (_) => _rechargerBientot(),
        )
        .subscribe();
  }

  void _rechargerBientot() {
    _attente?.cancel();
    _attente = Timer(const Duration(milliseconds: 600), charger);
  }

  /// Crée un groupe d'amis et l'ouvre. Renvoie son id.
  Future<String?> creer(String nom, List<String> membres) async {
    try {
      final id = await supabase.rpc('creer_groupe',
          params: {'p_nom': nom, 'p_membres': membres}) as String;
      await charger();
      return id;
    } catch (e) {
      debugPrint('creer_groupe : $e');
      Get.snackbar('Groupe non créé', 'Vérifie ta connexion et réessaie',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
      return null;
    }
  }

  /// Ouvre un groupe depuis son id (notification, événement…).
  Future<void> ouvrirParId(String id) async {
    var g = groupes.firstWhereOrNull((x) => x.id == id);
    if (g == null) {
      await charger();
      g = groupes.firstWhereOrNull((x) => x.id == id);
    }
    if (g == null) {
      Get.snackbar('Groupe introuvable',
          'Ce groupe n\'existe plus ou tu n\'en fais plus partie',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
      return;
    }
    Get.to(() => EcranGroupe(groupe: g!));
  }

  /// Groupe de discussion d'un événement (si j'y participe).
  Future<void> ouvrirGroupeEvenement(String evenementId) async {
    try {
      final id = await supabase.rpc('groupe_evenement',
          params: {'p_ev': evenementId}) as String?;
      if (id == null) {
        Get.snackbar('Discussion indisponible',
            'Indique « J\'y vais » ou « Intéressé » pour rejoindre la discussion',
            snackPosition: SnackPosition.TOP,
            backgroundColor: AppColors.surface,
            colorText: AppColors.textPrimary);
        return;
      }
      await ouvrirParId(id);
    } catch (e) {
      debugPrint('groupe_evenement : $e');
    }
  }

  void marquerLu(String groupeId) {
    final i = groupes.indexWhere((g) => g.id == groupeId);
    if (i < 0 || groupes[i].nonLus == 0) return;
    final g = groupes[i];
    groupes[i] = GroupeResume(
      id: g.id,
      nom: g.nom,
      photoUrl: g.photoUrl,
      evenementId: g.evenementId,
      nbMembres: g.nbMembres,
      suisAdmin: g.suisAdmin,
      sourdine: g.sourdine,
      dernierType: g.dernierType,
      dernierContenu: g.dernierContenu,
      dernierAuteur: g.dernierAuteur,
      derniereActivite: g.derniereActivite,
      nonLus: 0,
    );
  }
}
