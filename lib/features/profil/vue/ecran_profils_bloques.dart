import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';

class EcranProfilsBloques extends StatelessWidget {
  const EcranProfilsBloques({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = ControleurProfil.to;

    WidgetsBinding.instance
        .addPostFrameCallback((_) => ctrl.chargerProfilsBloques());

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        centerTitle: true,
        leading: GestureDetector(
          onTap: () => Get.back(),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppColors.surface2,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border)),
            child:  Icon(Icons.arrow_back_ios_rounded,
                size: 16, color: AppColors.textPrimary),
          ),
        ),
        title:  Text('Profils bloqués',
            style: TextStyle(
                fontFamily: 'Syne',
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        actions: [
          Obx(() => ctrl.blockedProfiles.isNotEmpty
              ? GestureDetector(
                  onTap: ctrl.toutDebloquer,
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: AppColors.error.withOpacity(0.3)),
                    ),
                    child:  Text('Tout débloquer',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.error)),
                  ),
                )
              : const SizedBox()),
        ],
      ),
      body: Obx(() {
        if (ctrl.isLoadingBlocked.value) {
          return  Center(
            child: CircularProgressIndicator(
                color: AppColors.accent, strokeWidth: 2),
          );
        }

        if (ctrl.blockedProfiles.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child:  Icon(Icons.block_rounded,
                      size: 36, color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                 Text('Aucun profil bloqué',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                 Text('Les profils que tu bloques\napparaîtront ici',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          itemCount: ctrl.blockedProfiles.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final p = ctrl.blockedProfiles[i];
            final name = p['name'] ?? 'Utilisateur';
            final photo = p['photo_url'] as String?;
            final id = p['id'] as String;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border)),
              child: Row(children: [
                // Avatar
                ClipOval(
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: photo != null && photo.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: photo,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                _InitialAvatar(name: name))
                        : _InitialAvatar(name: name),
                  ),
                ),
                const SizedBox(width: 12),
                // Nom + info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style:  TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                       Text('Bloqué',
                          style:
                              TextStyle(fontSize: 11, color: AppColors.error)),
                    ],
                  ),
                ),
                // Bouton débloquer
                GestureDetector(
                  onTap: () => _confirmerDeblocage(ctrl, id, name),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.online.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: AppColors.online.withOpacity(0.3)),
                    ),
                    child:  Text('Débloquer',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.online)),
                  ),
                ),
              ]),
            );
          },
        );
      }),
    );
  }

  void _confirmerDeblocage(ControleurProfil ctrl, String id, String name) {
    Get.dialog(AlertDialog(
      backgroundColor: const Color(0xFF11111C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Débloquer $name ?',
          style: const TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontSize: 17)),
      content: Text(
          '$name pourra à nouveau voir ton profil et t\'envoyer des messages.',
          style: const TextStyle(color: Color(0xFF5A5A78), fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Get.back(),
            child: const Text('Annuler',
                style: TextStyle(color: Color(0xFF5A5A78)))),
        GestureDetector(
          onTap: () {
            Get.back();
            ctrl.debloquerProfil(id);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
                color: AppColors.online,
                borderRadius: BorderRadius.circular(12)),
            child: const Text('Débloquer',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    ));
  }
}

class _InitialAvatar extends StatelessWidget {
  final String name;
  const _InitialAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface2,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(fontSize: 20, color: Colors.white38),
        ),
      ),
    );
  }
}
