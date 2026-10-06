import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:rencontre/core/services/revenue_cat_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/evenements/proposer_evenement.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/shared/widgets/avatar_rayonnant.dart';

/// Fond blanc : chaque avantage a sa couleur douce ; fond sombre : accent
Color _icone(Color clair, Color sombre) => AppColors.clair ? clair : sombre;

// Échelle de texte unique de la page (même police, mêmes graisses)
class _T {
  static TextStyle titre() => TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w800,
      color: AppColors.textPrimary,
      letterSpacing: -0.2);
  static TextStyle sousTitre() =>
      TextStyle(fontSize: 13.5, color: AppColors.textMuted, height: 1.4);
  static TextStyle section() => TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppColors.textMuted,
      letterSpacing: 0.8);
  static TextStyle ligne() => TextStyle(
      fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
  static TextStyle detail() =>
      TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.35);
  static TextStyle prix() => TextStyle(
      fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary);
}

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final rc = Get.find<RevenueCatService>();
  Package? _choisie;
  final _scroll = ScrollController();
  bool _enBas = false; // flèche « encore du contenu » masquée en bas

  void _majFleche() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final enBas = p.maxScrollExtent <= 0 || p.pixels >= p.maxScrollExtent - 40;
    if (enBas != _enBas) setState(() => _enBas = enBas);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_majFleche);
    // ✅ Si le chargement des offres avait échoué au démarrage, le paywall
    // tournait indéfiniment : on relance le chargement à l'ouverture.
    if (rc.formulesPremium.isEmpty) rc.fetchOfferings();
  }

  /// Formule mise en avant : 3 mois si elle existe, sinon la plus longue.
  Package? _populaire(List<Package> pkgs) {
    if (pkgs.length < 2) return null;
    return pkgs.firstWhereOrNull((p) =>
            RevenueCatService.joursPeriode(p.storeProduct.subscriptionPeriod) ==
            90) ??
        pkgs.last;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      body: Obx(() {
        final packages = rc.formulesPremium;
        if (packages.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final populaire = _populaire(packages);
        // Par défaut : la formule 1 semaine (la plus courte, en premier)
        final choisie =
            packages.contains(_choisie) ? _choisie! : packages.first;
        WidgetsBinding.instance.addPostFrameCallback((_) => _majFleche());
        // Référence pour calculer l'économie : la formule la plus courte.
        final reference = packages.first.storeProduct;

        return Column(
          children: [
            Expanded(
              child: Stack(children: [
                ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  children: [
                    // ─── En-tête : ta photo qui rayonne ──────────
                    Center(
                      child: AvatarRayonnant(
                        photoUrl: Get.isRegistered<HomeController>()
                            ? Get.find<HomeController>().myProfile?.photoUrl
                            : null,
                        actif: true,
                        icone: Icons.workspace_premium_rounded,
                      ),
                    ),
                    Text('Zamu Premium',
                        textAlign: TextAlign.center, style: _T.titre()),
                    const SizedBox(height: 4),
                    Text('Débloque tout le potentiel de Zamu',
                        textAlign: TextAlign.center, style: _T.sousTitre()),
                    const SizedBox(height: 24),

                    // ─── Avantages ───────────────────────────────
                    _BenefitTile(
                      icon: Icons.remove_red_eye_rounded,
                      iconColor: _icone(const Color(0xFF1D8FE1), AppColors.accent),
                      title: 'Vois qui t\'a vu',
                      subtitle:
                          'Découvre l\'identité de toutes les personnes qui ont consulté ton profil',
                    ),
                    _BenefitTile(
                      icon: Icons.favorite_rounded,
                      iconColor: _icone(const Color(0xFFE8508E), AppColors.accent),
                      title: 'Vois qui t\'a liké',
                      subtitle:
                          'Ne passe plus à côté d\'un match — vois qui s\'intéresse déjà à toi',
                    ),
                    _BenefitTile(
                      icon: Icons.people_alt_rounded,
                      iconColor: _icone(const Color(0xFF22A55B), AppColors.accent2),
                      title: 'Beaucoup plus de profils',
                      subtitle:
                          'Accède à un nombre de profils bien plus large que la version gratuite',
                    ),
                    _BenefitTile(
                      icon: Icons.location_city_rounded,
                      iconColor: _icone(const Color(0xFF8B5CF6), AppColors.accent2),
                      title: 'Explore une autre ville',
                      subtitle:
                          'Découvre les profils d\'Abidjan, Bouaké ou ailleurs avant d\'y aller',
                    ),
                    _BenefitTile(
                      icon: Icons.bolt_rounded,
                      iconColor: const Color(0xFFFFA500),
                      title: '1 Boost offert chaque mois',
                      subtitle:
                          'Ton profil passe en tête de l\'Accueil pendant 1 heure',
                    ),
                    _BenefitTile(
                      icon: Icons.visibility_off_rounded,
                      iconColor: _icone(const Color(0xFF64748B), AppColors.accent),
                      title: 'Mode fantôme sur la carte',
                      subtitle: 'Vois les autres sans apparaître toi-même',
                    ),
                    // Seulement si les propositions sont ouvertes (sinon on
                    // promettrait un avantage qui n'existe pas)
                    if (propositionsOuvertes)
                      _BenefitTile(
                        icon: Icons.event_rounded,
                        iconColor: _icone(const Color(0xFF0EA5A4), AppColors.accent2),
                        title: 'Propose tes événements',
                        subtitle:
                            'Soirées, sorties, rencontres : crée ton événement',
                      ),

                    const SizedBox(height: 20),

                    // ─── Formules ────────────────────────────────
                    Text('CHOISIS TA FORMULE', style: _T.section()),
                    const SizedBox(height: 12),
                    ...packages.map((pkg) => _FormuleTile(
                          package: pkg,
                          reference: reference,
                          choisie: identical(pkg, choisie),
                          populaire: identical(pkg, populaire),
                          onTap: () => setState(() => _choisie = pkg),
                        )),

                    const SizedBox(height: 4),
                    Center(
                      child: TextButton(
                        onPressed: rc.isProcessing.value
                            ? null
                            : () async {
                                final restored = await rc.restorePurchases();
                                if (restored && context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              },
                        child: Text(
                          'Restaurer mes achats',
                          style:
                              _T.detail().copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
                // ─── Flèche : il reste du contenu plus bas ───
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: IgnorePointer(
                    ignoring: _enBas,
                    child: AnimatedOpacity(
                      opacity: _enBas ? 0 : 1,
                      duration: const Duration(milliseconds: 250),
                      child: Center(
                        child: GestureDetector(
                          onTap: () => _scroll.animateTo(
                              _scroll.position.maxScrollExtent,
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeOutCubic),
                          child: const _FlecheRebond(),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),

            // ─── Bouton d'achat ──────────────────────────────
            Container(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
              decoration: BoxDecoration(
                color: AppColors.bg,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                GestureDetector(
                  onTap: rc.isProcessing.value
                      ? null
                      : () => _handlePurchase(context, choisie),
                  child: Container(
                    width: double.infinity,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: AppColors.gradientPink,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: rc.isProcessing.value
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: AppColors.surAccent))
                        : Text(
                            'Continuer · ${RevenueCatService.libellePrix(choisie.storeProduct)}',
                            style: _T.ligne().copyWith(color: AppColors.surAccent),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Renouvellement automatique. Résiliable à tout moment dans Google Play.',
                  textAlign: TextAlign.center,
                  style: _T.detail().copyWith(fontSize: 11),
                ),
              ]),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _handlePurchase(BuildContext context, Package package) async {
    // ✅ Évite un 2e achat lancé par un double tap pendant le 1er.
    if (rc.isProcessing.value) return;
    final success = await rc.purchasePackage(package);
    if (success && context.mounted) Navigator.of(context).pop();
  }
}

// ─── FORMULE ─────────────────────────────────────────────────────

class _FormuleTile extends StatelessWidget {
  final Package package;
  final StoreProduct reference;
  final bool choisie;
  final bool populaire;
  final VoidCallback onTap;

  const _FormuleTile({
    required this.package,
    required this.reference,
    required this.choisie,
    required this.populaire,
    required this.onTap,
  });

  static String _duree(String? iso) {
    switch (iso) {
      case 'P1W':
      case 'P7D':
        return '1 semaine';
      case 'P1M':
      case 'P4W':
        return '1 mois';
      case 'P3M':
        return '3 mois';
      case 'P6M':
        return '6 mois';
      case 'P1Y':
      case 'P12M':
        return '12 mois';
      default:
        return 'Premium';
    }
  }

  /// 1990 → « 1 990 FCFA » (XOF), sinon montant + code devise.
  static String _montant(double v, String devise) {
    final n = v
        .round()
        .toString()
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
    return devise == 'XOF' ? '$n FCFA' : '$n $devise';
  }

  @override
  Widget build(BuildContext context) {
    final p = package.storeProduct;
    final jours = RevenueCatService.joursPeriode(p.subscriptionPeriod);
    final joursRef =
        RevenueCatService.joursPeriode(reference.subscriptionPeriod);
    final parSemaine = jours > 0 ? p.price / (jours / 7) : null;
    final refParSemaine =
        joursRef > 0 ? reference.price / (joursRef / 7) : null;
    final economie = (parSemaine != null &&
            refParSemaine != null &&
            refParSemaine > 0 &&
            jours > joursRef)
        ? ((1 - parSemaine / refParSemaine) * 100).round()
        : 0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              choisie ? AppColors.accent.withOpacity(0.12) : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: choisie ? AppColors.accent : AppColors.border,
            width: choisie ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              choisie
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: choisie ? AppColors.accent : AppColors.textMuted,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(_duree(p.subscriptionPeriod), style: _T.ligne()),
                    if (populaire) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: AppColors.gradientPink,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('POPULAIRE',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: AppColors.surAccent,
                                letterSpacing: 0.5)),
                      ),
                    ],
                  ]),
                  if (parSemaine != null && jours > 7) ...[
                    const SizedBox(height: 3),
                    Text(
                      'soit ${_montant(parSemaine, p.currencyCode)} / semaine',
                      style: _T.detail(),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(p.priceString, style: _T.prix()),
                if (economie >= 5)
                  Text(
                    '−$economie %',
                    style: _T.detail().copyWith(
                        fontWeight: FontWeight.w800, color: AppColors.online),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── AVANTAGE ────────────────────────────────────────────────────

class _BenefitTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _BenefitTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _T.ligne()),
                const SizedBox(height: 2),
                Text(subtitle, style: _T.detail()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── FLÈCHE QUI REBONDIT (« encore du contenu en bas ») ─────────

class _FlecheRebond extends StatefulWidget {
  const _FlecheRebond();
  @override
  State<_FlecheRebond> createState() => _FlecheRebondState();
}

class _FlecheRebondState extends State<_FlecheRebond>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, 6 * Curves.easeInOut.transform(_anim.value)),
        child: child,
      ),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surface2,
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 10),
          ],
        ),
        child: Icon(Icons.keyboard_arrow_down_rounded,
            color: AppColors.textPrimary, size: 26),
      ),
    );
  }
}
