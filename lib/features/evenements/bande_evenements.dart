import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/evenements/ecran_evenement.dart';
import 'package:rencontre/features/evenements/evenement_model.dart';
import 'package:rencontre/features/evenements/evenements_controller.dart';
import 'package:rencontre/features/evenements/proposer_evenement.dart';
import 'package:rencontre/features/evenements/ecran_tous_evenements.dart';

/// Accueil : bande défilante « 📅 Événements » (masquée s'il n'y en a pas).
class BandeEvenements extends StatelessWidget {
  const BandeEvenements({super.key});

  static const _maxBande = 5;

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<EvenementsController>()) {
      return const SizedBox.shrink();
    }
    final ctrl = EvenementsController.to;
    return Obx(() {
      final liste = ctrl.evenements;
      // Aucun événement : simple lien pour en proposer un
      if (liste.isEmpty) {
        return GestureDetector(
          onTap: () => Get.to(() => const ProposerEvenement()),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
            child: Row(children: [
              const Text('📅', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text('Un événement à venir ? ',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              Text('Propose-le',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent)),
            ]),
          ),
        );
      }
      // Accueil : les 5 plus pertinents (en cours, proches, bientôt)
      final bande = liste.take(_maxBande).toList();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 4, 4),
              child: Row(children: [
                Text('📅 Événements',
                    style: TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const Spacer(),
                TextButton(
                  onPressed: () => Get.to(() => const EcranTousEvenements()),
                  child: Text(
                      liste.length > _maxBande
                          ? 'Voir tout (${liste.length}) ›'
                          : 'Voir tout ›',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent)),
                ),
              ]),
            ),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: bande.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => i < bande.length
                    ? _CarteEvenement(ev: bande[i])
                    : const _CarteProposer(),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _CarteEvenement extends StatelessWidget {
  final EvenementModel ev;
  const _CarteEvenement({required this.ev});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Get.to(() => EcranEvenement(evenement: ev)),
      child: Container(
        width: 220,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: AppColors.gradientPink,
          border: ev.jeParticipe
              ? Border.all(color: AppColors.online, width: 2)
              : null,
        ),
        child: Stack(fit: StackFit.expand, children: [
          if ((ev.imageUrl ?? '').isNotEmpty)
            CachedNetworkImage(
              imageUrl: ev.imageUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox(),
            )
          else
            Center(
                child: Text(ev.emoji, style: const TextStyle(fontSize: 54))),
          // Dégradé pour lire le texte
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
                stops: [0.35, 1],
              ),
            ),
          ),
          // Date
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: ev.annule
                    ? Colors.red
                    : ev.enCours
                        ? AppColors.online
                        : Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(ev.annule ? 'Annulé' : ev.dateCourte,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
          ),
          // Titre, lieu, participants
          Positioned(
            left: 10,
            right: 10,
            bottom: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(ev.titre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.15,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Row(children: [
                  Expanded(
                    child: Text('📍 ${ev.lieuComplet}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                  ),
                  const SizedBox(width: 6),
                  Text(
                      ev.enCours && ev.nbSurPlace > 0
                          ? '📍 ${ev.nbSurPlace}'
                          : ev.jeParticipe
                              ? '✓ ${ev.nbParticipants}'
                              : '✋ ${ev.nbParticipants}',
                      style: TextStyle(
                          color: ev.jeParticipe
                              ? AppColors.online
                              : Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Dernière carte de la bande : proposer un événement à Zamu.
class _CarteProposer extends StatelessWidget {
  const _CarteProposer();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Get.to(() => const ProposerEvenement()),
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add_circle_outline_rounded,
              color: AppColors.accent, size: 34),
          const SizedBox(height: 8),
          Text('Proposer un\névénement',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
        ]),
      ),
    );
  }
}
