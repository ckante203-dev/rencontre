import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:rencontre/core/services/revenue_cat_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';

class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rc = Get.find<RevenueCatService>();
    // ✅ Si le chargement des offres avait échoué au démarrage, le paywall
    // tournait indéfiniment : on relance le chargement à l'ouverture.
    if (rc.offerings.value?.current == null) rc.fetchOfferings();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Zamu Premium'),
      ),
      body: Obx(() {
        final packages = rc.offerings.value?.current?.availablePackages ?? [];
        if (packages.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ─── En-tête ─────────────────────────────────────
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

            // ─── Avantages ───────────────────────────────────
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
            const _BenefitTile(
              icon: Icons.bolt_rounded,
              iconColor: Color(0xFFFFA500),
              title: 'Boost de profil',
              subtitle: 'Sois mis en avant auprès des autres utilisateurs',
              comingSoon: true,
            ),

            const SizedBox(height: 28),

            // ─── Formules ────────────────────────────────────
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
            ...packages.map((pkg) => _PackageTile(
                  package: pkg,
                  onTap: () => _handlePurchase(context, rc, pkg),
                )),

            const SizedBox(height: 16),
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
        );
      }),
    );
  }

  Future<void> _handlePurchase(
      BuildContext context, RevenueCatService rc, Package package) async {
    // ✅ Évite un 2e achat lancé par un double tap pendant le 1er.
    if (rc.isProcessing.value) return;
    final success = await rc.purchasePackage(package);
    if (success && context.mounted) Navigator.of(context).pop();
  }
}

// ─── AVANTAGE ────────────────────────────────────────────────────

class _BenefitTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool comingSoon;

  const _BenefitTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: comingSoon ? 0.55 : 1.0,
      child: Padding(
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
                      if (comingSoon) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Bientôt',
                            style: TextStyle(
                                fontSize: 9,
                                color: Colors.white70,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
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
      ),
    );
  }
}

// ─── FORMULE ─────────────────────────────────────────────────────

class _PackageTile extends StatelessWidget {
  final Package package;
  final VoidCallback onTap;
  const _PackageTile({required this.package, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final product = package.storeProduct;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.accent, AppColors.accent2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.description,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Text(
              product.priceString,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
