import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/services/revenue_cat_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/core/utils/app_routes.dart';
import 'package:rencontre/shared/widgets/avatar_rayonnant.dart';
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
  Map<String, dynamic>? _bilan; // vues / likes du Boost en cours ou du dernier
  Map<String, dynamic>? _offert; // Boost offert aux Premium (1 h / mois)
  bool _activationOffert = false;

  @override
  void initState() {
    super.initState();
    if ((_rc?.boosts ?? const []).isEmpty) _rc?.fetchOfferings();
    _chargerBilan();
    _chargerOffert();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      // Bilan rafraîchi toutes les 30 s pendant le Boost
      if (_fin != null && t.tick % 30 == 0) _chargerBilan();
      setState(() {});
    });
  }

  /// Bilan du Boost (RPC bilan_boost, migration 041). Silencieux si le
  /// script n'est pas encore exécuté.
  Future<void> _chargerBilan() async {
    try {
      final res = await Supabase.instance.client.rpc('bilan_boost');
      final ligne = (res is List && res.isNotEmpty)
          ? Map<String, dynamic>.from(res.first as Map)
          : null;
      if (mounted) setState(() => _bilan = ligne);
    } catch (e) {
      debugPrint('bilan_boost: $e');
    }
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

  /// Boost offert du mois (RPC boost_offert_etat, migration 042).
  Future<void> _chargerOffert() async {
    try {
      final res = await Supabase.instance.client.rpc('boost_offert_etat');
      final ligne = (res is List && res.isNotEmpty)
          ? Map<String, dynamic>.from(res.first as Map)
          : null;
      if (mounted) setState(() => _offert = ligne);
    } catch (e) {
      debugPrint('boost_offert_etat: $e');
    }
  }

  Future<void> _utiliserOffert() async {
    if (_activationOffert) return;
    setState(() => _activationOffert = true);
    try {
      await Supabase.instance.client.rpc('utiliser_boost_offert');
      await _home.rafraichirMonProfil();
      await Future.wait([_chargerOffert(), _chargerBilan()]);
      _snack('Boost offert activé ⚡ Ton profil est en tête pendant 1 heure !');
    } on PostgrestException catch (e) {
      _snack(e.message.contains('deja_utilise')
          ? 'Ton Boost offert de ce mois est déjà utilisé.'
          : e.message.contains('premium_requis')
              ? 'Le Boost offert est réservé aux membres Premium.'
              : "Impossible d'activer le Boost. Réessaie.");
      _chargerOffert();
    } catch (_) {
      _snack("Impossible d'activer le Boost. Réessaie.");
    } finally {
      if (mounted) setState(() => _activationOffert = false);
    }
  }

  static const _mois = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
    'août', 'septembre', 'octobre', 'novembre', 'décembre'
  ];

  Widget _carteOffert() {
    final o = _offert;
    if (o == null) return const SizedBox.shrink();
    final premium = o['premium'] == true;
    final dispo = o['disponible'] == true;
    const or = Color(0xFFFFA500);

    // Compte gratuit : rappel de l'avantage Premium
    if (!premium) {
      return GestureDetector(
        onTap: () {
          Get.back();
          Get.toNamed(AppRoutes.paywall);
        },
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(text: '👑 '),
              TextSpan(
                  text: "Avec Premium : 1 Boost d'1 h offert chaque mois",
                  style: TextStyle(color: AppColors.textPrimary)),
              const TextSpan(
                  text: '  ›',
                  style: TextStyle(color: or, fontWeight: FontWeight.w900)),
            ]),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    // Premium, déjà utilisé ce mois-ci
    if (!dispo) {
      final p = DateTime.tryParse('${o['prochain']}')?.toLocal();
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          p == null
              ? '🎁 Boost offert du mois utilisé'
              : '🎁 Boost offert du mois utilisé · le prochain le '
                  '${p.day == 1 ? '1er' : p.day} ${_mois[p.month - 1]}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      );
    }

    // Premium, Boost du mois disponible
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: or.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: or, width: 1.5),
      ),
      child: Row(children: [
        const Text('🎁', style: TextStyle(fontSize: 26)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ton Boost offert du mois',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text('1 heure · inclus avec Premium',
                    style:
                        TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ]),
        ),
        GestureDetector(
          onTap: _activationOffert ? null : _utiliserOffert,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)]),
            ),
            child: _activationOffert
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Activer',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
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
    _chargerBilan();
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
        // Ta photo qui rayonne (ondes plus rapides pendant un Boost)
        AvatarRayonnant(
            photoUrl: _home.myProfile?.photoUrl, actif: fin != null),
        const SizedBox(height: 4),
        Text(fin != null ? 'Ton profil rayonne ⚡' : 'Booste ton profil',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        _MessagesDefilants(messages: _messages(fin != null)),
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

        // ─── Bilan : en direct, ou celui du dernier Boost ───
        if (!_activation) _carteBilan(fin != null),

        // ─── Boost offert aux Premium (1 h / mois) ────────
        if (!_activation) _carteOffert(),

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
          // Offre recommandée : le Boost 2 h (meilleur rapport pour une
          // soirée), sinon la première de la liste
          final a2h = pkgs.any(
              (p) => p.storeProduct.identifier.startsWith('boost_2h'));
          final meilleur = pkgs.length > 1 &&
              (a2h
                  ? pkg.storeProduct.identifier.startsWith('boost_2h')
                  : e.key == 0);
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
                            const Text('⭐ Recommandé',
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

  Widget _carteBilan(bool actif) {
    final b = _bilan;
    if (b == null) return const SizedBox.shrink();
    final vues = (b['vues'] as num?)?.toInt() ?? 0;
    final likes = (b['likes'] as num?)?.toInt() ?? 0;
    final x = (b['multiplicateur'] as num?)?.toDouble();
    final fin = DateTime.tryParse('${b['fin']}')?.toLocal();
    // Le dernier bilan n'est montré qu'une semaine après la fin
    if (!actif &&
        (fin == null ||
            DateTime.now().difference(fin) > const Duration(days: 7))) {
      return const SizedBox.shrink();
    }
    Widget chiffre(String valeur, String libelle) => Expanded(
          child: Column(children: [
            Text(valeur,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(libelle,
                style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
        );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        Text(actif ? 'Pendant ce Boost' : 'Ton dernier Boost',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted)),
        const SizedBox(height: 10),
        Row(children: [
          chiffre('$vues', vues > 1 ? 'vues du profil' : 'vue du profil'),
          chiffre('$likes', likes > 1 ? 'likes reçus' : 'like reçu'),
          if (x != null && x > 1)
            chiffre('×${x.toStringAsFixed(1).replaceAll('.0', '').replaceAll('.', ',')}',
                "que d'habitude"),
        ]),
      ]),
    );
  }

  /// Messages qui défilent sous le titre — vrais chiffres quand on en a.
  List<String> _messages(bool actif) {
    final moi = _home.myProfile?.id;
    final enLigne =
        _home.profiles.where((u) => u.isOnline && u.id != moi).length;
    final x = (_bilan?['multiplicateur'] as num?)?.toDouble();
    return [
      if (enLigne >= 2)
        '🔥 $enLigne personnes en ligne autour de toi en ce moment',
      if (actif) ...[
        '👀 Ton profil est en tête chez les personnes autour de toi',
        '⚡ Ton badge Boost attire les regards',
        '📸 Tes stories sont montrées en premier',
        "👑 Profite de tous les avantages Premium jusqu'à la fin",
        '💬 Reste dans le coin : les messages arrivent pendant le Boost',
      ] else ...[
        "🔝 Passe en tête de l'Accueil autour de toi",
        '⚡ Un badge Boost qui attire les regards',
        '📸 Tes stories passent aussi en premier',
        '👑 Tous les avantages Premium pendant ton Boost',
        '💬 Plus de vues, plus de likes, plus de discussions',
        if (x != null && x > 1)
          "📈 Ton dernier Boost : ×${x.toStringAsFixed(1).replaceAll('.0', '').replaceAll('.', ',')} de vues que d'habitude",
      ],
    ];
  }

  Widget _info(String texte) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(texte,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted)),
      );
}

// ─── Messages qui défilent (fondu toutes les 3 s) ──────────────────
class _MessagesDefilants extends StatefulWidget {
  final List<String> messages;
  const _MessagesDefilants({required this.messages});
  @override
  State<_MessagesDefilants> createState() => _MessagesDefilantsState();
}

class _MessagesDefilantsState extends State<_MessagesDefilants> {
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && widget.messages.length > 1) setState(() => _i++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.messages;
    if (m.isEmpty) return const SizedBox(height: 40);
    final texte = m[_i % m.length];
    return SizedBox(
      height: 40,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.3), end: Offset.zero)
                .animate(a),
            child: c,
          ),
        ),
        child: Text(
          texte,
          key: ValueKey(texte),
          textAlign: TextAlign.center,
          maxLines: 2,
          style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary.withValues(alpha: 0.85),
              height: 1.35),
        ),
      ),
    );
  }
}
