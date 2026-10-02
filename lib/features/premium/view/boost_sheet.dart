import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:rencontre/core/services/revenue_cat_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';

// ═══════════════════════════════════════════════════════════════
// Boost de profil (1h / 2h / 24h) : achat unique via RevenueCat
// (offre « boosts »). Le Boost est accordé par le serveur (webhook) :
// après le paiement, on attend que boost_jusqua soit mis à jour.
// ═══════════════════════════════════════════════════════════════

void showBoostSheet() {
  Get.bottomSheet(const _BoostSheet(), isScrollControlled: true);
}

class _BoostSheet extends StatefulWidget {
  const _BoostSheet();
  @override
  State<_BoostSheet> createState() => _BoostSheetState();
}

class _BoostSheetState extends State<_BoostSheet> {
  RevenueCatService? get _rc => Get.isRegistered<RevenueCatService>()
      ? Get.find<RevenueCatService>()
      : null;
  HomeController get _home => Get.find<HomeController>();

  Timer? _ticker;
  bool _activation = false; // paiement fait, en attente du serveur

  @override
  void initState() {
    super.initState();
    if ((_rc?.boosts ?? const []).isEmpty) _rc?.fetchOfferings();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  DateTime? get _fin {
    final f = _home.myProfile?.boostJusqua;
    return (f != null && f.isAfter(DateTime.now())) ? f : null;
  }

  static String _duree(String productId) {
    switch (productId.split(':').first) {
      case 'boost_1h':
        return '1 heure';
      case 'boost_2h':
        return '2 heures';
      case 'boost_24h':
        return '24 heures';
      default:
        return 'Boost';
    }
  }

  static String _restant(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '${h}h $m min' : '$m:$s';
  }

  Future<void> _acheter(Package pkg) async {
    final rc = _rc;
    if (rc == null) return;
    final avant = _home.myProfile?.boostJusqua;
    final ok = await rc.acheterBoost(pkg);
    if (!ok || !mounted) return;

    setState(() => _activation = true);
    // Le webhook RevenueCat → Supabase prend en général quelques secondes.
    for (var i = 0; i < 15 && mounted; i++) {
      await Future.delayed(const Duration(seconds: 2));
      await _home.rafraichirMonProfil();
      final apres = _home.myProfile?.boostJusqua;
      if (apres != null && apres != avant && apres.isAfter(DateTime.now())) {
        break;
      }
    }
    if (!mounted) return;
    setState(() => _activation = false);
    _snack(_fin != null
        ? 'Boost activé ⚡ Ton profil est en tête !'
        : 'Paiement reçu. Ton Boost s\'activera dans un instant.');
  }

  void _snack(String texte) => Get.snackbar(texte, '',
      titleText: Text(texte,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary)),
      messageText: const SizedBox.shrink(),
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface2,
      margin: const EdgeInsets.all(12),
      borderRadius: 14,
      duration: const Duration(seconds: 3));

  @override
  Widget build(BuildContext context) {
    final fin = _fin;
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).padding.bottom + 20),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2))),
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 36),
        ),
        const SizedBox(height: 12),
        Text('Booste ton profil',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(
          'Ton profil apparaît en tête de l\'accueil chez les personnes '
          'autour de toi, avec un badge ⚡.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: AppColors.textMuted, height: 1.4),
        ),
        const SizedBox(height: 18),

        // ─── Boost en cours ───────────────────────────────
        if (fin != null || _activation)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFA500).withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFFFFA500).withOpacity(0.5)),
            ),
            child: Row(children: [
              const Icon(Icons.bolt_rounded,
                  color: Color(0xFFFFA500), size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _activation && fin == null
                      ? 'Activation de ton Boost…'
                      : 'Boost actif · encore ${_restant(fin!.difference(DateTime.now()))}',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
              ),
              if (_activation)
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFFFFA500))),
            ]),
          ),

        // ─── Choix du Boost ───────────────────────────────
        _choix(fin != null),
      ]),
    );
  }

  Widget _choix(bool actif) {
    final rc = _rc;
    if (rc == null) {
      return _info('Les Boosts ne sont pas encore disponibles ici.');
    }
    return Obx(() {
      final pkgs = rc.boosts;
      if (pkgs.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        );
      }
      final enCours = rc.isProcessing.value || _activation;
      return Column(children: [
        if (actif)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('Un nouvel achat prolonge ton Boost en cours.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
        ...pkgs.asMap().entries.map((e) {
          final pkg = e.value;
          final meilleur = e.key == 0 && pkgs.length > 1;
          return GestureDetector(
            onTap: enCours ? null : () => _acheter(pkg),
            child: Opacity(
              opacity: enCours ? 0.5 : 1,
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: meilleur
                          ? const Color(0xFFFFA500)
                          : AppColors.border,
                      width: meilleur ? 1.5 : 1),
                ),
                child: Row(children: [
                  const Icon(Icons.bolt_rounded,
                      color: Color(0xFFFFA500), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Boost ${_duree(pkg.storeProduct.identifier)}',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary)),
                          if (meilleur)
                            const Text('Le plus efficace',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFFFA500))),
                        ]),
                  ),
                  Text(pkg.storeProduct.priceString,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary)),
                ]),
              ),
            ),
          );
        }),
        const SizedBox(height: 4),
        Text('Paiement unique, sans abonnement.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ]);
    });
  }

  Widget _info(String texte) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(texte,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted)),
      );
}
