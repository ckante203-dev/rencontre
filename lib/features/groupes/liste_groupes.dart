import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/features/groupes/communautes.dart';
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
      final liste =
          ctrl.groupes.where((g) => !ctrl.archives.contains(g.id)).toList();
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
              title: Text('Nouveau groupe'.tr,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.lien)),
              subtitle: Text('Discute avec plusieurs amis à la fois'.tr,
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
            // 🌍 Communautés publiques (créées par l'équipe Zamu)
            ListTile(
              onTap: () => Get.to(() => const EcranCommunautes()),
              leading: CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.surface2,
                child: const Text('🌍', style: TextStyle(fontSize: 22)),
              ),
              title: Text('Communautés'.tr,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.lien)),
              subtitle: Text('Rejoins des groupes autour de tes passions'.tr,
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
            if (liste.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                    'Aucun groupe pour l\'instant.\nCrée-en un, ou dis « J\'y vais » à un événement pour rejoindre sa discussion.'.tr,
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
              TuileGroupe(groupe: g),
            ],
          ],
        ),
      );
    });
  }
}

class TuileGroupe extends StatelessWidget {
  final GroupeResume groupe;
  const TuileGroupe({super.key, required this.groupe});

  static String _heure(DateTime d) {
    final n = DateTime.now();
    final jour = DateTime(d.year, d.month, d.day);
    final ecart = DateTime(n.year, n.month, n.day).difference(jour).inDays;
    if (ecart == 0) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    if (ecart == 1) return 'Hier'.tr;
    if (ecart < 7) return const ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'][d.weekday - 1].tr;
    return '${d.day}/${d.month}';
  }

  @override
  Widget build(BuildContext context) {
    final g = groupe;
    final nonLu = g.nonLus > 0;
    return ListTile(
      onTap: () => Get.to(() => EcranGroupe(groupe: g)),
      // Maintien : mêmes actions que pour une conversation
      onLongPress: () => _actionsGroupe(g),
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
        if (GroupesController.to.epingles.contains(g.id))
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(Icons.push_pin_rounded,
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
              gradient: g.sourdine ? null : AppColors.pastille,
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


/// Feuille d'actions au maintien d'un groupe (comme les conversations)
void _actionsGroupe(GroupeResume g) {
  final ctrl = GroupesController.to;
  final epingle = ctrl.epingles.contains(g.id);
  final archive = ctrl.archives.contains(g.id);
  Widget action(IconData icone, String texte, VoidCallback faire,
          {bool danger = false}) =>
      ListTile(
        leading: Icon(icone,
            color: danger ? const Color(0xFFFF3B30) : AppColors.textPrimary),
        title: Text(texte,
            style: TextStyle(
                color: danger ? const Color(0xFFFF3B30) : AppColors.textPrimary,
                fontWeight: FontWeight.w600)),
        onTap: () {
          Get.back();
          faire();
        },
      );
  Get.bottomSheet(
    SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(g.nom,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
          ),
          if (g.nonLus > 0)
            action(Icons.mark_chat_read_rounded, 'Marquer comme lu'.tr,
                () => ctrl.marquerCommeLu(g)),
          if (!archive)
            action(
                epingle ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                epingle ? 'Désépingler'.tr : 'Épingler en haut'.tr,
                () => ctrl.basculerEpingle(g.id)),
          action(
              g.sourdine
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_rounded,
              g.sourdine ? 'Réactiver les notifications'.tr : 'Mettre en sourdine'.tr,
              () => ctrl.basculerSourdine(g)),
          action(archive ? Icons.unarchive_rounded : Icons.archive_rounded,
              archive ? 'Désarchiver'.tr : 'Archiver'.tr,
              () => ctrl.basculerArchive(g.id)),
          action(Icons.logout_rounded, 'Quitter le groupe'.tr,
              () => ctrl.quitter(g),
              danger: true),
        ]),
      ),
    ),
    backgroundColor: Colors.transparent,
  );
}
