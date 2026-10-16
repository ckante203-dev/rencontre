import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
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

  // ── Actions au maintien (comme les conversations) ──
  // Épinglés / archivés : gardés sur le téléphone, comme pour les
  // conversations. Sourdine, « lu » et quitter : enregistrés sur le serveur.
  final _box = GetStorage();
  static const _cleEpingles = 'groupes_epingles';
  static const _cleArchives = 'groupes_archives';
  late final RxSet<String> epingles =
      <String>{...List<String>.from(_box.read<List>(_cleEpingles) ?? [])}.obs;
  late final RxSet<String> archives =
      <String>{...List<String>.from(_box.read<List>(_cleArchives) ?? [])}.obs;

  void basculerEpingle(String id) {
    epingles.contains(id) ? epingles.remove(id) : epingles.add(id);
    _box.write(_cleEpingles, epingles.toList());
  }

  void basculerArchive(String id) {
    if (archives.contains(id)) {
      archives.remove(id);
    } else {
      archives.add(id);
      epingles.remove(id);
      _box.write(_cleEpingles, epingles.toList());
    }
    _box.write(_cleArchives, archives.toList());
  }

  String? get _moi => supabase.auth.currentUser?.id;

  Future<void> basculerSourdine(GroupeResume g) async {
    try {
      await supabase
          .from('groupe_membres')
          .update({'sourdine': !g.sourdine})
          .eq('groupe_id', g.id)
          .eq('user_id', _moi!);
      await charger();
    } catch (_) {
      _snackErreur('Réglage non enregistré'.tr);
    }
  }

  Future<void> marquerCommeLu(GroupeResume g) async {
    marquerLu(g.id);
    try {
      await supabase
          .from('groupe_membres')
          .update({'dernier_lu': DateTime.now().toUtc().toIso8601String()})
          .eq('groupe_id', g.id)
          .eq('user_id', _moi!);
    } catch (_) {}
  }

  Future<void> quitter(GroupeResume g) async {
    final ok = await Get.dialog<bool>(AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Quitter « @nom » ?'.trParams({'nom': g.nom}),
          style: TextStyle(color: AppColors.textPrimary)),
      content: Text(
          g.estEvenement
              ? 'Tu ne recevras plus les messages de cet événement. Tu restes inscrit à l\'événement.'.tr
              : 'Tu ne recevras plus les messages de ce groupe.'.tr,
          style: TextStyle(color: AppColors.textMuted)),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('Annuler'.tr)),
        TextButton(
            onPressed: () => Get.back(result: true),
            child: Text('Quitter'.tr,
                style: const TextStyle(color: Color(0xFFFF3B30)))),
      ],
    ));
    if (ok != true) return;
    try {
      await supabase
          .from('groupe_membres')
          .delete()
          .eq('groupe_id', g.id)
          .eq('user_id', _moi!);
      epingles.remove(g.id);
      archives.remove(g.id);
      await charger();
    } catch (_) {
      _snackErreur('Impossible de quitter le groupe'.tr);
    }
  }

  void _snackErreur(String texte) => Get.snackbar('Oups'.tr, texte,
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface,
      colorText: AppColors.textPrimary);

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
      Get.snackbar('Groupe non créé'.tr, 'Vérifie ta connexion et réessaie'.tr,
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
      Get.snackbar('Groupe introuvable'.tr,
          'Ce groupe n\'existe plus ou tu n\'en fais plus partie'.tr,
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
        Get.snackbar('Discussion indisponible'.tr,
            'Indique « J\'y vais » ou « Intéressé » pour rejoindre la discussion'.tr,
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
