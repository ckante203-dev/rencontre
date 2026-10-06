import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/groupes/choix_membres.dart';
import 'package:rencontre/features/groupes/ecran_groupe.dart';
import 'package:rencontre/features/groupes/groupe_model.dart';
import 'package:rencontre/features/groupes/groupes_controller.dart';

void ouvrirNouveauGroupe() => Get.to(() => const ChoixMembres());

/// Onglet « Groupes » de Messages.
class ListeGroupes extends StatelessWidget {
  const ListeGroupes({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<GroupesController>()) return const SizedBox();
    final ctrl = GroupesController.to;
    return Obx(() {
      if (ctrl.chargement.value) {
        return Center(
            child: CircularProgressIndicator(color: AppColors.accent));
      }
      final liste = ctrl.groupes;
      return RefreshIndicator(
        onRefresh: ctrl.charger,
        color: AppColors.accent,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            ListTile(
              onTap: ouvrirNouveauGroupe,
              leading: CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.accent,
                child:
                    const Icon(Icons.group_add_rounded, color: AppColors.surAccent),
              ),
              title: Text('Nouveau groupe',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.accent)),
              subtitle: Text('Discute avec plusieurs amis à la fois',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
            if (liste.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                    'Aucun groupe pour l\'instant.\nCrée-en un, ou dis « J\'y vais » '
                    'à un événement pour rejoindre sa discussion.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, height: 1.5)),
              ),
            for (final g in liste) ...[
              Divider(
                height: 1,
                thickness: 1,
                indent: 80,
                endIndent: 16,
                color: Color.lerp(AppColors.border, AppColors.textMuted, 0.3),
              ),
              _TuileGroupe(groupe: g),
            ],
          ],
        ),
      );
    });
  }
}

class _TuileGroupe extends StatelessWidget {
  final GroupeResume groupe;
  const _TuileGroupe({required this.groupe});

  static String _heure(DateTime d) {
    final n = DateTime.now();
    final jour = DateTime(d.year, d.month, d.day);
    final ecart = DateTime(n.year, n.month, n.day).difference(jour).inDays;
    if (ecart == 0) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    if (ecart == 1) return 'Hier';
    if (ecart < 7) return const ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'][d.weekday - 1];
    return '${d.day}/${d.month}';
  }

  @override
  Widget build(BuildContext context) {
    final g = groupe;
    final nonLu = g.nonLus > 0;
    return ListTile(
      onTap: () => Get.to(() => EcranGroupe(groupe: g)),
      leading: AvatarGroupe(groupe: g),
      title: Row(children: [
        if (g.estEvenement)
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Text('📅', style: TextStyle(fontSize: 13)),
          ),
        Expanded(
          child: Text(g.nom,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: nonLu ? FontWeight.w800 : FontWeight.w600,
                  color: AppColors.textPrimary)),
        ),
        if (g.sourdine)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(Icons.notifications_off_rounded,
                size: 13, color: AppColors.textMuted),
          ),
        const SizedBox(width: 6),
        Text(_heure(g.derniereActivite),
            style: TextStyle(
                fontSize: 11,
                color: nonLu ? AppColors.accent : AppColors.textMuted)),
      ]),
      subtitle: Row(children: [
        Expanded(
          child: Text(g.apercu,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  color: nonLu ? AppColors.textPrimary : AppColors.textMuted)),
        ),
        if (nonLu)
          Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              gradient: g.sourdine ? null : AppColors.gradientPink,
              color: g.sourdine ? AppColors.border : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('${g.nonLus}',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    // groupe en sourdine : pastille grise → texte du thème
                    color: g.sourdine
                        ? AppColors.textPrimary
                        : AppColors.surAccent)),
          ),
      ]),
    );
  }
}
