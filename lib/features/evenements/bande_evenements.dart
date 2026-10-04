import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/evenements/ecran_evenement.dart';
import 'package:rencontre/features/evenements/evenement_model.dart';
import 'package:rencontre/features/evenements/evenements_controller.dart';

/// Accueil : bande défilante « 📅 Événements » (masquée s'il n'y en a pas).
class BandeEvenements extends StatelessWidget {
  const BandeEvenements({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<EvenementsController>()) {
      return const SizedBox.shrink();
    }
    final ctrl = EvenementsController.to;
    return Obx(() {
      final liste = ctrl.evenements;
      if (liste.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
              child: Text('📅 Événements',
                  style: TextStyle(
                      fontFamily: 'Syne',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: liste.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _CarteEvenement(ev: liste[i]),
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
                      ev.jeParticipe
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
