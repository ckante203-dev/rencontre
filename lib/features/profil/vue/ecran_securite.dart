import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/profil/vue/urgence.dart';

/// Guide de sécurité : conseils pour rencontrer en confiance.
class EcranSecurite extends StatelessWidget {
  const EcranSecurite({super.key});

  static const _conseils = [
    ('🛡️', 'Protège tes infos',
        "Ne donne pas ton adresse, ton lieu de travail ni tes infos bancaires à quelqu'un que tu viens de connaître."),
    ('💸', "Jamais d'argent",
        "Une personne qui te demande de l'argent, du crédit, un transfert Mobile Money ou un code reçu par SMS est presque toujours un arnaqueur. Signale-la."),
    ('✅', 'Préfère les profils vérifiés',
        'Le badge bleu montre que la personne ressemble bien à ses photos.'),
    ('☕', 'Premier rendez-vous dans un lieu public',
        'Choisis un endroit fréquenté (café, restaurant, maquis animé) et rentre par tes propres moyens.'),
    ('📍', 'Préviens un proche',
        "Dis à un ami où tu vas, avec qui, et à quelle heure tu penses rentrer."),
    ('🍹', 'Garde ton verre à l’œil',
        'Ne laisse jamais ta boisson sans surveillance et reste lucide.'),
    ('🚩', 'Écoute ton instinct',
        "Si quelque chose te met mal à l'aise, pars. Tu ne dois rien à personne."),
    ('🔞', 'Contenus intimes',
        "N'envoie pas de photos intimes : une fois partagées, tu n'en as plus le contrôle. Le chantage est un délit."),
    ('🚨', 'Signale et bloque',
        "Depuis un profil ou une conversation (menu ⋮) : signale tout comportement suspect. L'équipe Zamu examine chaque signalement."),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        title: Text('Conseils de sécurité'.tr,
            style: TextStyle(
                fontFamily: 'Syne',
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
              "Zamu, c'est fait pour de belles rencontres. Quelques réflexes pour qu'elles se passent bien :".tr,
              style: TextStyle(
                  fontSize: 14, color: AppColors.textMuted, height: 1.5)),
          const SizedBox(height: 16),
          // 🚨 Alerte à un proche, avec la position
          GestureDetector(
            onTap: () => Urgence.alerter(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.sos_rounded, color: AppColors.surAccent),
                const SizedBox(width: 8),
                Text('Je suis en danger'.tr,
                    style: const TextStyle(
                        color: AppColors.surAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          StatefulBuilder(
            builder: (context, setState) {
              final c = Urgence.contact;
              return GestureDetector(
                onTap: () async {
                  await Urgence.definir(context);
                  setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(children: [
                    const Text('📞', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Contact d'urgence".tr,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary)),
                            Text(
                                c == null
                                    ? 'Ajoute une personne de confiance'.tr
                                    : '${c['nom']} · ${c['numero']}',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.textMuted)),
                          ]),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: AppColors.textMuted),
                  ]),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          for (final (emoji, titre, texte) in _conseils) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(titre.tr,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary)),
                            const SizedBox(height: 4),
                            Text(texte.tr,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textMuted,
                                    height: 1.45)),
                          ]),
                    ),
                  ]),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
