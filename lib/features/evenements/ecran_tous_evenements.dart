import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/evenements/ecran_evenement.dart';
import 'package:rencontre/features/evenements/evenement_model.dart';
import 'package:rencontre/features/evenements/evenements_controller.dart';
import 'package:rencontre/features/evenements/proposer_evenement.dart';

/// Tous les événements : 🔴 En ce moment, Aujourd'hui, Cette semaine,
/// Plus tard ; filtre par catégorie ; « Mes événements ».
class EcranTousEvenements extends StatefulWidget {
  const EcranTousEvenements({super.key});

  @override
  State<EcranTousEvenements> createState() => _EcranTousEvenementsState();
}

class _EcranTousEvenementsState extends State<EcranTousEvenements> {
  String? _categorie; // null = toutes
  bool _mesEvenements = false;

  static const _categories = {
    'sport': '⚽ Sport',
    'concert': '🎤 Concert',
    'soiree': '🎉 Soirée',
    'festival': '🎪 Festival',
    'autre': '📅 Autre',
  };

  @override
  Widget build(BuildContext context) {
    final ctrl = EvenementsController.to;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text('📅 Événements',
            style: TextStyle(fontFamily: 'Syne', fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Proposer un événement',
            onPressed: () => Get.to(() => const ProposerEvenement()),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      body: Column(children: [
        // ── Filtres ──
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              _puce('✓ Mes événements', _mesEvenements,
                  () => setState(() => _mesEvenements = !_mesEvenements)),
              _puce('Toutes', _categorie == null,
                  () => setState(() => _categorie = null)),
              for (final c in _categories.entries)
                _puce(c.value, _categorie == c.key,
                    () => setState(() => _categorie = c.key)),
            ],
          ),
        ),
        Expanded(
          child: Obx(() {
            final liste = ctrl.evenements
                .where((e) =>
                    (_categorie == null || e.categorie == _categorie) &&
                    (!_mesEvenements || e.jeParticipe))
                .toList();
            if (liste.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                      _mesEvenements
                          ? 'Tu ne participes à aucun événement pour l\'instant'
                          : 'Aucun événement à venir dans cette catégorie',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted)),
                ),
              );
            }
            final sections = _sections(liste);
            return RefreshIndicator(
              onRefresh: ctrl.charger,
              color: AppColors.accent,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
                children: [
                  for (final s in sections.entries)
                    if (s.value.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                        child: Text(s.key,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                      ),
                      for (final e in s.value) _LigneEvenement(ev: e),
                    ],
                ],
              ),
            );
          }),
        ),
      ]),
    );
  }

  /// Regroupe par moment (l'ordre de la liste est conservé dans chaque
  /// section : par distance puis par date).
  Map<String, List<EvenementModel>> _sections(List<EvenementModel> liste) {
    final n = DateTime.now();
    final finAujourdhui = DateTime(n.year, n.month, n.day + 1);
    final finSemaine = DateTime(n.year, n.month, n.day + 7);
    final s = <String, List<EvenementModel>>{
      '🔴 En ce moment': [],
      'Aujourd\'hui': [],
      'Cette semaine': [],
      'Plus tard': [],
    };
    for (final e in liste) {
      if (e.enCours) {
        s['🔴 En ce moment']!.add(e);
      } else if (e.debut.isBefore(finAujourdhui)) {
        s['Aujourd\'hui']!.add(e);
      } else if (e.debut.isBefore(finSemaine)) {
        s['Cette semaine']!.add(e);
      } else {
        s['Plus tard']!.add(e);
      }
    }
    return s;
  }

  Widget _puce(String label, bool actif, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: actif ? AppColors.gradientPink : null,
              color: actif ? null : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: actif ? Colors.transparent : AppColors.border),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: actif ? Colors.white : AppColors.textPrimary)),
          ),
        ),
      );
}

class _LigneEvenement extends StatelessWidget {
  final EvenementModel ev;
  const _LigneEvenement({required this.ev});

  @override
  Widget build(BuildContext context) {
    final distance = ev.distanceKm == null
        ? ''
        : ' · ${ev.distanceKm! < 1 ? '${(ev.distanceKm! * 1000).round()} m' : '${ev.distanceKm!.round()} km'}';
    return GestureDetector(
      onTap: () => Get.to(() => EcranEvenement(evenement: ev)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: ev.jeParticipe ? AppColors.online : AppColors.border,
              width: ev.jeParticipe ? 1.5 : 1),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 74,
              height: 74,
              child: (ev.imageUrl ?? '').isNotEmpty
                  ? CachedNetworkImage(imageUrl: ev.imageUrl!, fit: BoxFit.cover)
                  : Container(
                      decoration:
                          BoxDecoration(gradient: AppColors.gradientPink),
                      child: Center(
                          child: Text(ev.emoji,
                              style: const TextStyle(fontSize: 32))),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ev.annule ? 'Annulé' : ev.dateCourte,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ev.annule
                              ? Colors.red
                              : ev.enCours
                                  ? AppColors.online
                                  : AppColors.accent)),
                  const SizedBox(height: 3),
                  Text(ev.titre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 3),
                  Text('📍 ${ev.lieuComplet}$distance',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 3),
                  Text(
                      [
                        if (ev.nbParticipants > 0) '✋ ${ev.nbParticipants}',
                        if (ev.nbInteresses > 0) '⭐ ${ev.nbInteresses}',
                        if (ev.enCours && ev.nbSurPlace > 0)
                          '📍 ${ev.nbSurPlace} sur place',
                        if (ev.jeParticipe)
                          ev.jYVais ? '✓ J\'y vais' : '✓ Intéressé',
                      ].join('  ·  '),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ]),
          ),
        ]),
      ),
    );
  }
}
