// lib/features/auth/view/cgu_screen.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rencontre/core/theme/app_theme.dart';

class CguScreen extends StatefulWidget {
  /// showAcceptButton = true  → depuis l'inscription (case à cocher)
  /// showAcceptButton = false → consultation simple depuis les paramètres
  final bool showAcceptButton;
  const CguScreen({super.key, this.showAcceptButton = false});

  @override
  State<CguScreen> createState() => _CguScreenState();
}

class _CguScreenState extends State<CguScreen> {
  bool _accepted = false;

  // Version en ligne : legal/conditions-utilisation.html, hébergée sur GitHub Pages (dépôt zamu-legal)
  static const String _cguUrl =
      'https://supportsnapmeet-jpg.github.io/zamu-legal/conditions-utilisation.html';

  Future<void> _openOnline() async {
    try {
      final uri = Uri.parse(_cguUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      Get.snackbar('Erreur', 'Impossible d\'ouvrir le lien',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.textPrimary, size: 20),
          onPressed: () => Get.back(result: false),
        ),
        title: Text("Conditions d'utilisation",
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFamily: 'Syne')),
        centerTitle: true,
        actions: [
          // Bouton ouvrir dans le navigateur
          IconButton(
            icon: Icon(Icons.open_in_new_rounded,
                color: AppColors.accent, size: 20),
            onPressed: _openOnline,
            tooltip: 'Voir en ligne',
          ),
        ],
      ),
      body: Column(children: [
        // ── Contenu scrollable ──
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // En-tête
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientPink,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(children: [
                    const Text('Zamu',
                        style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Syne',
                            fontSize: 22,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    const Text("Conditions Générales d'Utilisation",
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Text('Dernière mise à jour : Mars 2026',
                          style: TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ]),
                ),

                _buildSection('1. Présentation',
                    'Zamu est une application mobile de rencontre et de réseau social permettant aux utilisateurs de se découvrir, d\'échanger et de créer des liens.\n\nContact : support.snapmeet@gmail.com\n\nEn utilisant Zamu, vous acceptez sans réserve les présentes conditions. Si vous n\'acceptez pas, cessez d\'utiliser l\'application.'),

                _buildSection('2. Conditions d\'accès',
                    '• Âge minimum : 18 ans requis. Tout compte mineur sera supprimé immédiatement.\n\n• Compte unique : un seul compte par personne. Les faux profils entraînent une suppression immédiate.\n\n• Informations exactes : vous vous engagez à fournir de vraies informations. L\'usurpation d\'identité est interdite.'),

                _buildSection('3. Règles de comportement',
                    'Il est strictement interdit de :\n\n• Publier des contenus pornographiques ou impliquant des mineurs\n• Harceler, menacer ou insulter d\'autres utilisateurs\n• Publier des contenus haineux ou discriminatoires\n• Usurper l\'identité d\'une autre personne\n• Diffuser de fausses informations ou des escroqueries\n• Partager des informations personnelles sans consentement\n\nTout contenu inapproprié sera supprimé sans préavis.'),

                _buildSection('4. Protection des données personnelles',
                    'Données collectées : profil (nom, âge, photo), localisation (avec autorisation), messages, données techniques.\n\nUtilisation : uniquement pour faire fonctionner l\'application, envoyer des notifications et assurer la sécurité.\n\nPartage : vos données ne sont jamais vendues à des tiers.\n\nVos droits : accès, rectification, suppression, opposition.\n→ Exercez-les à : support.snapmeet@gmail.com\n\nSuppression du compte : vos données sont effacées dans les 30 jours.'),

                _buildSection('5. Responsabilités',
                    'Zamu est une plateforme de mise en relation. Nous ne sommes pas responsables des comportements entre utilisateurs, des rencontres physiques, ni des informations inexactes communiquées.\n\n⚠️ Recommandations de sécurité :\n• Informez un proche avant un rendez-vous\n• Choisissez un lieu public pour la première rencontre\n• Ne partagez jamais vos informations bancaires\n\nNotre responsabilité est limitée au montant payé lors des 3 derniers mois.'),

                _buildSection('6. Abonnement Premium',
                    'L\'application de base est entièrement gratuite.\n\nL\'abonnement Premium donne accès à des fonctionnalités avancées décrites dans l\'application.\n\nTarification : affichée avant toute souscription. Toute modification sera annoncée 30 jours à l\'avance.\n\nRenouvellement automatique sauf résiliation depuis l\'application. La résiliation prend effet à la fin de la période payée.\n\nRemboursement : non effectué sauf défaut technique imputable à Zamu.'),

                _buildSection('7. Modération et sanctions',
                    'En cas de violation des CGU :\n• Avertissement\n• Suspension temporaire\n• Suppression définitive du compte\n• Signalement aux autorités pour actes illégaux\n\nSignalez tout comportement inapproprié directement depuis l\'application.'),

                _buildSection('8. Propriété intellectuelle',
                    'Le nom Zamu, son logo et son code sont protégés. Toute reproduction sans autorisation est interdite.\n\nVotre contenu vous appartient. En le publiant, vous accordez à Zamu une licence limitée au fonctionnement de l\'application.'),

                _buildSection('9. Modifications',
                    'Ces CGU peuvent être modifiées à tout moment. Vous serez notifié via l\'application. Continuer à utiliser Zamu après notification vaut acceptation.'),

                _buildSection('10. Contact',
                    'Pour toute question ou réclamation :\n📧 support.snapmeet@gmail.com\n\nRéponse garantie sous 7 jours ouvrables.'),

                // Footer
                Container(
                  margin: const EdgeInsets.only(top: 20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border)),
                  child: Text(
                    'En utilisant Zamu, vous confirmez avoir lu, compris et accepté l\'intégralité des présentes Conditions Générales d\'Utilisation.\n\n© 2026 Zamu — Tous droits réservés',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 12, height: 1.6),
                    textAlign: TextAlign.center,
                  ),
                ),

                // Bouton voir en ligne
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _openOnline,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.accent.withOpacity(0.4))),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.open_in_new_rounded,
                              color: AppColors.accent, size: 16),
                          SizedBox(width: 8),
                          Text('Voir la version en ligne',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ]),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        // ── Bouton accepter (inscription seulement) ──
        if (widget.showAcceptButton)
          Container(
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, MediaQuery.of(context).padding.bottom + 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Case à cocher
              GestureDetector(
                onTap: () => setState(() => _accepted = !_accepted),
                child: Row(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      gradient: _accepted ? AppColors.gradientPink : null,
                      color: _accepted ? null : AppColors.surface2,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color:
                              _accepted ? Colors.transparent : AppColors.border,
                          width: 1.5),
                    ),
                    child: _accepted
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 14)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "J'ai lu et j'accepte les Conditions Générales d'Utilisation",
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          height: 1.4),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 14),

              // Bouton continuer
              GestureDetector(
                onTap: _accepted ? () => Get.back(result: true) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: _accepted ? AppColors.gradientPink : null,
                    color: _accepted ? null : AppColors.surface2,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: _accepted
                        ? [
                            BoxShadow(
                                color: AppColors.accent.withOpacity(0.3),
                                blurRadius: 16)
                          ]
                        : null,
                  ),
                  child: Text('Continuer',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color:
                              _accepted ? Colors.white : AppColors.textMuted)),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _buildSection(String title, String content) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Text(title,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Syne')),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(content,
              style: TextStyle(
                  color: AppColors.textMuted, fontSize: 13, height: 1.7)),
        ),
      ]),
    );
  }
}
