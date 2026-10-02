import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:rencontre/core/services/revenue_cat_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final rc = Get.find<RevenueCatService>();
  Package? _choisie;

  @override
  void initState() {
    super.initState();
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
        title: const Text('Zamu Premium'),
      ),
      body: Obx(() {
        final packages = rc.formulesPremium;
        if (packages.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final populaire = _populaire(packages);
        final choisie = packages.contains(_choisie)
            ? _choisie!
            : (populaire ?? packages.first);
        // Référence pour calculer l'économie : la formule la plus courte.
        final reference = packages.first.storeProduct;

        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                children: [
                  // ─── En-tête ─────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.workspace_premium_rounded,
                            color: Colors.white, size: 40),
                        SizedBox(height: 8),
                        Text(
                          'Zamu Premium',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Débloque tout le potentiel de Zamu',
                          style: TextStyle(fontSize: 13, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ─── Avantages ───────────────────────────────
                  _BenefitTile(
                    icon: Icons.remove_red_eye_rounded,
                    iconColor: AppColors.accent,
                    title: 'Vois qui t\'a vu',
                    subtitle:
                        'Découvre l\'identité de toutes les personnes qui ont consulté ton profil',
                  ),
                  _BenefitTile(
                    icon: Icons.favorite_rounded,
                    iconColor: AppColors.accent,
                    title: 'Vois qui t\'a liké',
                    subtitle:
                        'Ne passe plus à côté d\'un match — vois qui s\'intéresse déjà à toi',
                  ),
                  _BenefitTile(
                    icon: Icons.people_alt_rounded,
                    iconColor: AppColors.accent2,
                    title: 'Beaucoup plus de profils',
                    subtitle:
                        'Accède à un nombre de profils bien plus large que la version gratuite',
                  ),

                  const SizedBox(height: 20),

                  // ─── Formules ────────────────────────────────
                  const Text(
                    'CHOISIS TA FORMULE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white54,
                      letterSpacing: 0.8,
                    ),
                  ),
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
                      child: const Text(
                        'Restaurer mes achats',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  ),
                ],
              ),
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
                                strokeWidth: 2.5, color: Colors.white))
                        : Text(
                            'Continuer · ${RevenueCatService.libellePrix(choisie.storeProduct)}',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.white),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Renouvellement automatique. Résiliable à tout moment dans Google Play.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.white38),
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
                    Text(
                      _duree(p.subscriptionPeriod),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary),
                    ),
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
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.5)),
                      ),
                    ],
                  ]),
                  if (parSemaine != null && jours > 7) ...[
                    const SizedBox(height: 3),
                    Text(
                      'soit ${_montant(parSemaine, p.currencyCode)} / semaine',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  p.priceString,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary),
                ),
                if (economie >= 5)
                  Text(
                    '−$economie %',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.online),
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
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
