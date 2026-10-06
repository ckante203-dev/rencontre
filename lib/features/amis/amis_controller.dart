import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';

/// Un ami (ou une demande) avec son profil.
class Ami {
  final String id;
  final String nom;
  final String? photoUrl;
  final String? pseudo;
  final bool enLigne;
  final String statut; // amis, recue, envoyee
  const Ami({
    required this.id,
    required this.nom,
    this.photoUrl,
    this.pseudo,
    this.enLigne = false,
    this.statut = 'amis',
  });
}

/// Système d'amis façon Snap (SQL 037) : demande → acceptée.
class AmisController extends GetxController {
  static AmisController get to => Get.find<AmisController>();

  final RxList<Ami> liens = <Ami>[].obs;
  final RxBool chargement = false.obs;

  List<Ami> get amis => liens.where((a) => a.statut == 'amis').toList();
  List<Ami> get demandesRecues =>
      liens.where((a) => a.statut == 'recue').toList();
  List<Ami> get demandesEnvoyees =>
      liens.where((a) => a.statut == 'envoyee').toList();
  int get nbDemandes => liens.where((a) => a.statut == 'recue').length;

  /// Statut connu localement : aucun, envoyee, recue, amis.
  String statutDe(String userId) =>
      liens.firstWhereOrNull((a) => a.id == userId)?.statut ?? 'aucun';

  bool estAmi(String userId) => statutDe(userId) == 'amis';

  @override
  void onInit() {
    super.onInit();
    charger();
  }

  Future<void> charger() async {
    if (supabase.auth.currentUser == null) return;
    chargement.value = liens.isEmpty;
    try {
      final rows = await supabase.rpc('mes_amis') as List;
      liens.assignAll([
        for (final r in rows)
          Ami(
            id: r['id'] as String,
            nom: (r['name'] as String?) ?? 'Utilisateur',
            photoUrl: r['photo_url'] as String?,
            pseudo: r['username'] as String?,
            enLigne: r['en_ligne'] == true,
            statut: (r['statut'] as String?) ?? 'amis',
          ),
      ]);
    } catch (e) {
      debugPrint('mes_amis : $e'); // script SQL 037 absent ?
    } finally {
      chargement.value = false;
    }
  }

  void _snack(String t, String m) => Get.snackbar(t, m,
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface,
      colorText: AppColors.textPrimary);

  /// Ajouter en ami (ou accepter si l'autre m'a déjà demandé).
  Future<String> demander(String userId) async {
    try {
      final r = await supabase.rpc('demander_ami', params: {'p_user': userId})
          as String;
      await charger();
      return r;
    } catch (e) {
      _snack(
          'Demande non envoyée',
          e.toString().contains('trop_de_demandes')
              ? 'Trop de demandes en attente, attends qu\'on te réponde'
              : 'Vérifie ta connexion et réessaie');
      return statutDe(userId);
    }
  }

  Future<String> accepter(String userId) async {
    try {
      final r = await supabase.rpc('accepter_ami', params: {'p_user': userId})
          as String;
      await charger();
      return r;
    } catch (_) {
      _snack('Oups', 'Impossible d\'accepter, vérifie ta connexion');
      return statutDe(userId);
    }
  }

  /// Refuser une demande, annuler la mienne ou retirer un ami.
  Future<void> retirer(String userId) async {
    final avant = [...liens];
    liens.removeWhere((a) => a.id == userId);
    try {
      await supabase.rpc('retirer_ami', params: {'p_user': userId});
    } catch (_) {
      liens.assignAll(avant);
      _snack('Oups', 'Impossible, vérifie ta connexion');
    }
  }

  /// Statut à jour depuis la base (profil ouvert depuis un QR, une
  /// recherche… pas forcément dans ma liste locale).
  Future<String> statutServeur(String userId) async {
    try {
      return await supabase.rpc('statut_ami', params: {'p_user': userId})
          as String;
    } catch (_) {
      return statutDe(userId);
    }
  }
}
