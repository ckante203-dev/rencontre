// lib/features/annonces/view/annonces_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/annonces/controller/annonces_controller.dart';
import 'package:rencontre/features/annonces/controller/annonce_comment_controller.dart';
import 'package:rencontre/features/annonces/model/annonce_model.dart';
import 'package:rencontre/features/annonces/model/annonce_comment_model.dart';
import 'package:rencontre/shared/models/user_model.dart';

// ─── ECRAN ANNONCES ───────────────────────────────────────────────

class AnnoncesScreen extends StatelessWidget {
  const AnnoncesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<AnnoncesController>()) Get.put(AnnoncesController());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.find<AnnoncesController>().markAnnoncesAsSeen();
    });
    return const _AnnoncesView();
  }
}

class _AnnoncesView extends GetView<AnnoncesController> {
  const _AnnoncesView();

  String _catLabel(String cat) {
    const m = {
      'toutes': '🔥 Toutes',
      'rencontre': '💕 Rencontre',
      'amitie': '🤝 Amitié',
      'sortie': '🎉 Sortie',
      'voyage': '✈️ Voyage',
    };
    return m[cat] ?? cat;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              ShaderMask(
                shaderCallback: (b) => AppColors.gradientPink.createShader(b),
                child: const Text('Annonces',
                    style: TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showPublierSheet(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientPink,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.accent.withOpacity(0.3),
                          blurRadius: 12)
                    ],
                  ),
                  child: const Row(children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text('Publier',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ]),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 36,
            child: Obx(() {
              final currentCat = controller.filterCategorie.value;
              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: controller.categories.length,
                itemBuilder: (_, i) {
                  final cat = controller.categories[i];
                  final sel = currentCat == cat;
                  return GestureDetector(
                    onTap: () => controller.filterCategorie.value = cat,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: sel ? AppColors.gradientPink : null,
                        color: sel ? null : AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: sel ? Colors.transparent : AppColors.border),
                      ),
                      child: Text(_catLabel(cat),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: sel ? Colors.white : AppColors.textMuted)),
                    ),
                  );
                },
              );
            }),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value) {
                return const Center(
                    child: CircularProgressIndicator(color: AppColors.accent));
              }
              final list = controller.filtered;
              if (list.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ShaderMask(
                        shaderCallback: (b) =>
                            AppColors.gradientPink.createShader(b),
                        child: const Icon(Icons.campaign_rounded,
                            size: 64, color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      const Text('Aucune annonce',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 8),
                      const Text('Sois le premier à publier !',
                          style: TextStyle(color: AppColors.textMuted)),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                color: AppColors.accent,
                backgroundColor: AppColors.surface,
                onRefresh: controller.loadAnnonces,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _AnnonceCard(annonce: list[i]),
                ),
              );
            }),
          ),
        ]),
      ),
    );
  }

  void _showPublierSheet(BuildContext context) {
    final titreCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final villeCtrl = TextEditingController();
    String cat = 'rencontre';
    bool loading = false;
    bool anonyme = false;
    bool commentsEnabled = true;
    XFile? mediaFile;
    bool isVideo = false;

    String cl(String c) {
      const m = {
        'rencontre': '💕 Rencontre',
        'amitie': '🤝 Amitié',
        'sortie': '🎉 Sortie',
        'voyage': '✈️ Voyage',
      };
      return m[c] ?? c;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: AppColors.border),
            ),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2))),
                ShaderMask(
                  shaderCallback: (b) => AppColors.gradientPink.createShader(b),
                  child: const Text('Nouvelle annonce',
                      style: TextStyle(
                          fontFamily: 'Syne',
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white)),
                ),
                const SizedBox(height: 20),
                // Catégories
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['rencontre', 'amitie', 'sortie', 'voyage']
                        .map<Widget>((c) => GestureDetector(
                              onTap: () => setS(() => cat = c),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  gradient:
                                      cat == c ? AppColors.gradientPink : null,
                                  color: cat == c ? null : AppColors.surface2,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: cat == c
                                          ? Colors.transparent
                                          : AppColors.border),
                                ),
                                child: Text(cl(c),
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: cat == c
                                            ? Colors.white
                                            : AppColors.textMuted)),
                              ),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 16),
                _Field(
                    controller: titreCtrl,
                    hint: 'Titre (optionnel si photo/vidéo)',
                    maxLines: 1),
                const SizedBox(height: 12),
                _Field(
                    controller: descCtrl,
                    hint: 'Description (optionnelle si photo/vidéo)',
                    maxLines: 4),
                const SizedBox(height: 12),
                _Field(
                    controller: villeCtrl,
                    hint: 'Ville (optionnel)',
                    maxLines: 1),
                const SizedBox(height: 16),
                // Boutons photo / vidéo
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final f = await ImagePicker().pickImage(
                            source: ImageSource.gallery, imageQuality: 80);
                        if (f != null)
                          setS(() {
                            mediaFile = f;
                            isVideo = false;
                          });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: mediaFile != null && !isVideo
                              ? AppColors.accent.withOpacity(0.15)
                              : AppColors.surface2,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: mediaFile != null && !isVideo
                                  ? AppColors.accent
                                  : AppColors.border),
                        ),
                        child: Column(children: [
                          Icon(Icons.photo_outlined,
                              color: mediaFile != null && !isVideo
                                  ? AppColors.accent
                                  : AppColors.textMuted,
                              size: 22),
                          const SizedBox(height: 4),
                          Text('Photo',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: mediaFile != null && !isVideo
                                      ? AppColors.accent
                                      : AppColors.textMuted)),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final f = await ImagePicker()
                            .pickVideo(source: ImageSource.gallery);
                        if (f != null)
                          setS(() {
                            mediaFile = f;
                            isVideo = true;
                          });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: mediaFile != null && isVideo
                              ? AppColors.accent.withOpacity(0.15)
                              : AppColors.surface2,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: mediaFile != null && isVideo
                                  ? AppColors.accent
                                  : AppColors.border),
                        ),
                        child: Column(children: [
                          Icon(Icons.videocam_outlined,
                              color: mediaFile != null && isVideo
                                  ? AppColors.accent
                                  : AppColors.textMuted,
                              size: 22),
                          const SizedBox(height: 4),
                          Text('Vidéo',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: mediaFile != null && isVideo
                                      ? AppColors.accent
                                      : AppColors.textMuted)),
                        ]),
                      ),
                    ),
                  ),
                  if (mediaFile != null) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => setS(() => mediaFile = null),
                      child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: Colors.red.withOpacity(0.3))),
                          child: const Icon(Icons.close_rounded,
                              color: Colors.red, size: 20)),
                    ),
                  ],
                ]),
                // Preview photo
                if (mediaFile != null && !isVideo) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(File(mediaFile!.path),
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover)),
                ],
                // Preview vidéo
                if (mediaFile != null && isVideo) ...[
                  const SizedBox(height: 12),
                  Container(
                    height: 72,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.accent.withOpacity(0.4))),
                    child: Row(children: [
                      const Icon(Icons.videocam_rounded,
                          color: AppColors.accent, size: 26),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(mediaFile!.name,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
                ],
                const SizedBox(height: 16),
                // Toggle anonyme
                GestureDetector(
                  onTap: () => setS(() => anonyme = !anonyme),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: anonyme
                          ? const Color(0xFF6C3FC5).withOpacity(0.12)
                          : AppColors.surface2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: anonyme
                              ? const Color(0xFF6C3FC5)
                              : AppColors.border),
                    ),
                    child: Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: anonyme
                              ? const Color(0xFF6C3FC5).withOpacity(0.2)
                              : AppColors.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: anonyme
                                  ? const Color(0xFF6C3FC5)
                                  : AppColors.border),
                        ),
                        child: Icon(Icons.visibility_off_rounded,
                            size: 18,
                            color: anonyme
                                ? const Color(0xFF6C3FC5)
                                : AppColors.textMuted),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Publier en anonyme',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: anonyme
                                          ? const Color(0xFF6C3FC5)
                                          : AppColors.textPrimary)),
                              const Text('Ton nom et photo seront masqués',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted)),
                            ]),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44,
                        height: 24,
                        decoration: BoxDecoration(
                          color: anonyme
                              ? const Color(0xFF6C3FC5)
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: anonyme
                                  ? const Color(0xFF6C3FC5)
                                  : AppColors.border),
                        ),
                        child: AnimatedAlign(
                          duration: const Duration(milliseconds: 200),
                          alignment: anonyme
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                              margin: const EdgeInsets.all(2),
                              width: 20,
                              height: 20,
                              decoration: const BoxDecoration(
                                  color: Colors.white, shape: BoxShape.circle)),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
                // Toggle commentaires
                GestureDetector(
                  onTap: () => setS(() => commentsEnabled = !commentsEnabled),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: !commentsEnabled
                          ? Colors.orange.withOpacity(0.08)
                          : AppColors.surface2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: !commentsEnabled
                              ? Colors.orange
                              : AppColors.border),
                    ),
                    child: Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: !commentsEnabled
                              ? Colors.orange.withOpacity(0.15)
                              : AppColors.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: !commentsEnabled
                                  ? Colors.orange
                                  : AppColors.border),
                        ),
                        child: Icon(
                            commentsEnabled
                                ? Icons.chat_bubble_outline_rounded
                                : Icons.comments_disabled_outlined,
                            size: 18,
                            color: !commentsEnabled
                                ? Colors.orange
                                : AppColors.textMuted),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                commentsEnabled
                                    ? 'Commentaires activés'
                                    : 'Commentaires désactivés',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: !commentsEnabled
                                        ? Colors.orange
                                        : AppColors.textPrimary),
                              ),
                              Text(
                                commentsEnabled
                                    ? 'Les gens peuvent répondre'
                                    : 'Personne ne peut commenter',
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.textMuted),
                              ),
                            ]),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44,
                        height: 24,
                        decoration: BoxDecoration(
                          color: commentsEnabled
                              ? AppColors.accent
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: commentsEnabled
                                  ? AppColors.accent
                                  : AppColors.border),
                        ),
                        child: AnimatedAlign(
                          duration: const Duration(milliseconds: 200),
                          alignment: commentsEnabled
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                              margin: const EdgeInsets.all(2),
                              width: 20,
                              height: 20,
                              decoration: const BoxDecoration(
                                  color: Colors.white, shape: BoxShape.circle)),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                // Bouton publier
                GestureDetector(
                  onTap: loading
                      ? null
                      : () async {
                          final hasMedia = mediaFile != null;
                          if (!hasMedia &&
                              (titreCtrl.text.trim().isEmpty ||
                                  descCtrl.text.trim().isEmpty)) {
                            Get.snackbar(
                              'Champs requis',
                              'Ajoute un titre et une description, ou joins une photo/vidéo',
                              snackPosition: SnackPosition.TOP,
                              backgroundColor: Colors.red.shade900,
                              colorText: Colors.white,
                            );
                            return;
                          }
                          final titre = titreCtrl.text.trim().isEmpty
                              ? '📸'
                              : titreCtrl.text.trim();
                          final desc = descCtrl.text.trim();
                          setS(() => loading = true);
                          final ok = await Get.find<AnnoncesController>()
                              .publierAnnonce(
                            titre: titre,
                            description: desc,
                            categorie: cat,
                            ville: villeCtrl.text.trim().isEmpty
                                ? null
                                : villeCtrl.text.trim(),
                            anonyme: anonyme,
                            mediaFile: mediaFile,
                            isVideo: isVideo,
                            commentsEnabled: commentsEnabled,
                          );
                          setS(() => loading = false);
                          if (ok) {
                            Navigator.pop(ctx);
                            Get.snackbar(
                              'Annonce publiée ✅',
                              '',
                              snackPosition: SnackPosition.TOP,
                              backgroundColor: AppColors.surface,
                              colorText: Colors.white,
                            );
                          }
                        },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: AppColors.gradientPink,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.accent.withOpacity(0.3),
                            blurRadius: 16)
                      ],
                    ),
                    child: loading
                        ? const Center(
                            child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5)))
                        : const Text('Publier mon annonce',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── CARTE ANNONCE ────────────────────────────────────────────────

class _AnnonceCard extends GetView<AnnoncesController> {
  final AnnonceModel annonce;
  const _AnnonceCard({required this.annonce});

  String get _emoji {
    const m = {
      'rencontre': '💕',
      'amitie': '🤝',
      'sortie': '🎉',
      'voyage': '✈️',
    };
    return m[annonce.categorie] ?? '📢';
  }

  String get _ago {
    final d = DateTime.now().difference(annonce.createdAt);
    if (d.inDays > 0) return 'il y a ${d.inDays}j';
    if (d.inHours > 0) return 'il y a ${d.inHours}h';
    if (d.inMinutes > 0) return 'il y a ${d.inMinutes}min';
    return "à l'instant";
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: annonce.isBoosted
                  ? AppColors.accent.withOpacity(0.5)
                  : AppColors.border,
              width: annonce.isBoosted ? 1.5 : 1),
          boxShadow: annonce.isBoosted
              ? [
                  BoxShadow(
                      color: AppColors.accent.withOpacity(0.1), blurRadius: 16)
                ]
              : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(children: [
              GestureDetector(
                onTap: annonce.isAnonyme ? null : () => _openProfil(annonce),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: annonce.isAnonyme
                            ? const Color(0xFF6C3FC5).withOpacity(0.5)
                            : AppColors.accent.withOpacity(0.4),
                        width: 1.5),
                  ),
                  child: ClipOval(
                    child: annonce.isAnonyme
                        ? Container(
                            decoration: const BoxDecoration(
                                gradient: LinearGradient(colors: [
                              Color(0xFF6C3FC5),
                              Color(0xFF3B1F7A),
                            ])),
                            child: const Center(
                                child: Icon(Icons.person_outline_rounded,
                                    color: Colors.white, size: 24)))
                        : (annonce.userPhotoUrl != null
                            ? CachedNetworkImage(
                                imageUrl: annonce.userPhotoUrl!,
                                fit: BoxFit.cover)
                            : Container(
                                decoration: const BoxDecoration(
                                    gradient: LinearGradient(colors: [
                                  AppColors.accent,
                                  AppColors.accent2
                                ])),
                                child: Center(
                                    child: Text(
                                        annonce.userName[0].toUpperCase(),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800))))),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: annonce.isAnonyme ? null : () => _openProfil(annonce),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          if (annonce.isAnonyme)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFF6C3FC5).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: const Color(0xFF6C3FC5)
                                        .withOpacity(0.4)),
                              ),
                              child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.visibility_off_rounded,
                                        size: 10, color: Color(0xFF6C3FC5)),
                                    SizedBox(width: 3),
                                    Text('Anonyme',
                                        style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF6C3FC5))),
                                  ]),
                            ),
                          Flexible(
                              child: Text(
                                  annonce.isAnonyme
                                      ? 'Utilisateur anonyme'
                                      : annonce.userName,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary),
                                  overflow: TextOverflow.ellipsis)),
                          if (!annonce.isAnonyme) ...[
                            const SizedBox(width: 6),
                            Text('${annonce.userAge} ans',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.textMuted)),
                          ],
                        ]),
                        Row(children: [
                          if (annonce.ville != null && !annonce.isAnonyme) ...[
                            const Icon(Icons.location_on_rounded,
                                size: 11, color: AppColors.textMuted),
                            Text(annonce.ville!,
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.textMuted)),
                            const SizedBox(width: 8),
                          ],
                          Text(_ago,
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textMuted)),
                        ]),
                      ]),
                ),
              ),
              if (annonce.isBoosted)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      Color(0xFFFFD700),
                      Color(0xFFFF8C00),
                    ]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.bolt_rounded, size: 11, color: Colors.white),
                    SizedBox(width: 2),
                    Text('BOOST',
                        style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                  ]),
                ),
              GestureDetector(
                  onTap: () => _menu(context),
                  child: const Icon(Icons.more_vert_rounded,
                      color: AppColors.textMuted, size: 20)),
            ]),
          ),

          // ── Titre + catégorie ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border)),
                child: Text('$_emoji ${annonce.categorie}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted)),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(annonce.titre,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
            ]),
          ),
          const SizedBox(height: 8),

          // ── Description ──
          if (annonce.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(annonce.description,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textMuted, height: 1.5),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ),
          const SizedBox(height: 10),

          // ── Media ──
          if (annonce.mediaUrl != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: annonce.isVideo
                  ? _AutoplayVideoPlayer(
                      url: annonce.mediaUrl!, annonceId: annonce.id)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                          imageUrl: annonce.mediaUrl!,
                          height: 320,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                              height: 320,
                              color: AppColors.surface2,
                              child: const Center(
                                  child: CircularProgressIndicator(
                                      color: AppColors.accent))),
                          errorWidget: (_, __, ___) =>
                              const SizedBox.shrink())),
            ),
            const SizedBox(height: 10),
          ],

          // ── Actions ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Row(children: [
              // ❤️ Like
              GestureDetector(
                onTap: () {
                  controller.toggleLike(annonce);
                  // Notifier si c'est un nouveau like (pas un unlike)
                  if (!annonce.isLiked) {
                    _notifyLike(context);
                  }
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Row(
                    key: ValueKey(annonce.isLiked),
                    children: [
                      Icon(
                          annonce.isLiked
                              ? Icons.favorite_rounded
                              : Icons.favorite_outline_rounded,
                          color: annonce.isLiked
                              ? Colors.red
                              : AppColors.textMuted,
                          size: 22),
                      const SizedBox(width: 5),
                      Text('${annonce.likes}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: annonce.isLiked
                                  ? Colors.red
                                  : AppColors.textMuted)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // 💬 Commentaires
              GestureDetector(
                onTap: annonce.commentsEnabled
                    ? () {
                        HapticFeedback.lightImpact();
                        _openComments(context);
                      }
                    : null,
                child: Row(children: [
                  Icon(
                      annonce.commentsEnabled
                          ? Icons.chat_bubble_outline_rounded
                          : Icons.comments_disabled_outlined,
                      color: annonce.commentsEnabled
                          ? AppColors.textMuted
                          : AppColors.textMuted.withOpacity(0.4),
                      size: 18),
                  const SizedBox(width: 5),
                  Text(
                      !annonce.commentsEnabled
                          ? '—'
                          : annonce.reponsesCount > 0
                              ? '${annonce.reponsesCount}'
                              : 'Commenter',
                      style: TextStyle(
                          fontSize: 13,
                          color: annonce.commentsEnabled
                              ? AppColors.textMuted
                              : AppColors.textMuted.withOpacity(0.4),
                          fontWeight: FontWeight.w600)),
                ]),
              ),
              const Spacer(),
              _BoostButton(annonce: annonce),
            ]),
          ),
        ]),
      ),
    );
  }

  void _openProfil(AnnonceModel annonce) {
    final user = UserModel(
      id: annonce.userId,
      name: annonce.userName,
      age: annonce.userAge,
      photoUrl: annonce.userPhotoUrl,
      isOnline: false,
      interests: [],
    );
    Get.toNamed('/profil/detail', arguments: user);
  }

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnnonceDetailSheet(annonce: annonce),
    );
  }

  void _openComments(BuildContext context) {
    AnnonceCommentsSheet.show(context, annonce: annonce);
  }

  void _notifyLike(BuildContext context) {
    // Ouvre un controller temporaire juste pour envoyer la notif
    final tag = 'comments_${annonce.id}';
    AnnonceCommentController ctrl;
    if (Get.isRegistered<AnnonceCommentController>(tag: tag)) {
      ctrl = Get.find<AnnonceCommentController>(tag: tag);
    } else {
      ctrl = Get.put(AnnonceCommentController(annonce: annonce), tag: tag);
    }
    // Récupérer le nom du liker depuis Supabase
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    Supabase.instance.client
        .from('profiles')
        .select('name')
        .eq('id', uid)
        .maybeSingle()
        .then((p) =>
            ctrl.notifyAnnonceLike(likerName: p?['name'] ?? 'Quelqu\'un'));
  }

  void _repondreAnonyme(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppColors.border)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          const Icon(Icons.visibility_off_rounded,
              color: Color(0xFF6C3FC5), size: 44),
          const SizedBox(height: 12),
          const Text('Annonce anonyme',
              style: TextStyle(
                  fontFamily: 'Syne',
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          const Text(
              'Cette annonce a été publiée de façon anonyme.\nTu ne peux pas contacter directement cet utilisateur.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textMuted, fontSize: 13, height: 1.5)),
          const SizedBox(height: 20),
          GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border)),
                  child: const Text('Fermer',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)))),
        ]),
      ),
    );
  }

  void _menu(BuildContext context) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border.all(color: AppColors.border)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2))),
                if (myId == annonce.userId) ...[
                  _MenuItem(
                      Icons.delete_outline_rounded, 'Supprimer', Colors.red,
                      () {
                    Navigator.pop(context);
                    controller.supprimerAnnonce(annonce.id);
                  }),
                  const SizedBox(height: 8),
                ],
                _MenuItem(Icons.flag_outlined, 'Signaler', Colors.orange,
                    () => Navigator.pop(context)),
                const SizedBox(height: 8),
                _MenuItem(Icons.close_rounded, 'Fermer', AppColors.textMuted,
                    () => Navigator.pop(context)),
              ]),
            ));
  }
}

// ─── SHEET COMMENTAIRES ───────────────────────────────────────────

class AnnonceCommentsSheet extends StatelessWidget {
  final AnnonceModel annonce;
  const AnnonceCommentsSheet({super.key, required this.annonce});

  static void show(BuildContext context, {required AnnonceModel annonce}) {
    if (!annonce.commentsEnabled) {
      Get.snackbar(
          'Commentaires désactivés', 'L\'auteur a désactivé les commentaires',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF13131A),
          colorText: Colors.white);
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => AnnonceCommentsSheet(annonce: annonce),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tag = 'comments_${annonce.id}';
    final ctrl = Get.put(AnnonceCommentController(annonce: annonce), tag: tag);
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollCtrl) => _CommentsSheetContent(
        annonce: annonce,
        ctrl: ctrl,
        tag: tag,
        scrollCtrl: scrollCtrl,
      ),
    );
  }
}

// ── Sheet content ────────────────────────────────────────────────
class _CommentsSheetContent extends StatefulWidget {
  final AnnonceModel annonce;
  final AnnonceCommentController ctrl;
  final String tag;
  final ScrollController scrollCtrl;
  const _CommentsSheetContent({
    required this.annonce,
    required this.ctrl,
    required this.tag,
    required this.scrollCtrl,
  });
  @override
  State<_CommentsSheetContent> createState() => _CommentsSheetContentState();
}

class _CommentsSheetContentState extends State<_CommentsSheetContent> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  static String _postAgo(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays >= 365) return '${(diff.inDays / 365).floor()}a';
    if (diff.inDays >= 30) return '${(diff.inDays / 30).floor()}mo';
    if (diff.inDays >= 7) return '${(diff.inDays / 7).floor()}sem';
    if (diff.inDays >= 1) return '${diff.inDays}j';
    if (diff.inHours >= 1) return '${diff.inHours}h';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}min';
    return 'maintenant';
  }

  @override
  Widget build(BuildContext context) {
    final annonce = widget.annonce;
    final ctrl = widget.ctrl;
    final tag = widget.tag;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0E0E1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        // ── Poignée + titre ──────────────────────────────────────
        const SizedBox(height: 8),
        Center(
            child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
              color: const Color(0xFF353550),
              borderRadius: BorderRadius.circular(2)),
        )),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            const Text('Commentaires',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Obx(() {
              final n =
                  ctrl.comments.fold(0, (s, c) => s + 1 + c.replies.length);
              return Text('$n',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 13));
            }),
            const Spacer(),
            GestureDetector(
              onTap: () {
                Get.delete<AnnonceCommentController>(tag: tag);
                Navigator.pop(context);
              },
              child: const Icon(Icons.close_rounded,
                  color: AppColors.textMuted, size: 20),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        const Divider(height: 1, color: Color(0xFF1A1A2E)),

        // ── Scroll unique : pub + commentaires ───────────────────
        Expanded(
          child: Obx(() {
            if (ctrl.loading.value) {
              return const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.accent, strokeWidth: 2));
            }
            final comments = ctrl.comments;
            // Nombre total de sliver items = 1 (pub) + N commentaires + 1 (padding bas)
            return CustomScrollView(
              controller: widget.scrollCtrl,
              slivers: [
                // ── Publication style TikTok ──
                // ── Publication originale style TikTok ──────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar
                        GestureDetector(
                          onTap: () {
                            if (annonce.isAnonyme) return;
                            Get.toNamed('/profil/detail',
                                arguments: UserModel(
                                  id: annonce.userId,
                                  name: annonce.userName,
                                  age: annonce.userAge,
                                  photoUrl: annonce.userPhotoUrl,
                                  isOnline: false,
                                  interests: [],
                                ));
                          },
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.surface2,
                            backgroundImage: annonce.userPhotoUrl != null &&
                                    !annonce.isAnonyme
                                ? CachedNetworkImageProvider(
                                    annonce.userPhotoUrl!)
                                : null,
                            child: annonce.userPhotoUrl == null ||
                                    annonce.isAnonyme
                                ? Icon(
                                    annonce.isAnonyme
                                        ? Icons.person_outline_rounded
                                        : Icons.person_rounded,
                                    color: Colors.white54,
                                    size: 18)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Texte + média
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Pseudo + heure de la pub
                              Row(children: [
                                Text(
                                  annonce.isAnonyme
                                      ? 'Anonyme'
                                      : annonce.userName,
                                  style: TextStyle(
                                    color: annonce.isAnonyme
                                        ? Colors.white54
                                        : Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _postAgo(annonce.createdAt),
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 11),
                                ),
                              ]),
                              const SizedBox(height: 5),

                              // Texte (titre + description)
                              if (annonce.titre.isNotEmpty) ...[
                                Text(annonce.titre,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        height: 1.4)),
                                const SizedBox(height: 2),
                              ],
                              if (annonce.description.isNotEmpty)
                                Text(
                                  annonce.description,
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      height: 1.45),
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),

                              // Média compact (image ou vidéo) — style TikTok
                              if (annonce.mediaUrl != null) ...[
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: annonce.isVideo
                                      ? SizedBox(
                                          height: 160,
                                          width: double.infinity,
                                          child: _AnnonceVideoPreview(
                                              url: annonce.mediaUrl!),
                                        )
                                      : CachedNetworkImage(
                                          imageUrl: annonce.mediaUrl!,
                                          width: double.infinity,
                                          height: 160,
                                          fit: BoxFit.cover,
                                        ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SliverToBoxAdapter(
                  child: Divider(height: 1, color: Color(0xFF1A1A2E)),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),

                // ── Commentaires vides ──
                if (comments.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.chat_bubble_outline_rounded,
                            color: AppColors.textMuted, size: 42),
                        const SizedBox(height: 10),
                        const Text('Aucun commentaire',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 14)),
                        const SizedBox(height: 4),
                        const Text('Sois le premier !',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 12)),
                      ]),
                    ),
                  ),

                // ── Liste commentaires ──
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _CommentTile(
                          comment: comments[i], ctrl: ctrl, isReply: false),
                    ),
                    childCount: comments.length,
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 90)),
              ],
            );
          }),
        ),

        // ── Barre "répondre à" ────────────────────────────────────
        Obx(() {
          final name = ctrl.replyingToName.value;
          if (name.isEmpty) return const SizedBox.shrink();
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: const Color(0xFF13131F),
            child: Row(children: [
              Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Text('Répondre à $name',
                  style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              GestureDetector(
                  onTap: ctrl.cancelReply,
                  child: const Icon(Icons.close_rounded,
                      color: AppColors.textMuted, size: 16)),
            ]),
          );
        }),

        // ── Champ saisie collé en bas ─────────────────────────────
        Container(
          padding: EdgeInsets.only(
              left: 12,
              right: 12,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 12),
          decoration: const BoxDecoration(
            color: Color(0xFF0E0E1A),
            border: Border(top: BorderSide(color: Color(0xFF1A1A2E))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFF252540)),
                  ),
                  child: TextField(
                    controller: ctrl.textCtrl,
                    focusNode: _focusNode,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    maxLines: 4,
                    minLines: 1,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    buildCounter: (_,
                            {required currentLength,
                            required isFocused,
                            maxLength}) =>
                        isFocused && currentLength > 400
                            ? Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text('$currentLength/500',
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 10)))
                            : null,
                    decoration: const InputDecoration(
                      hintText: 'Écrire un commentaire...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Obx(() => GestureDetector(
                    onTap: ctrl.sending.value ? null : ctrl.sendComment,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient:
                            ctrl.sending.value ? null : AppColors.gradientPink,
                        color:
                            ctrl.sending.value ? const Color(0xFF252538) : null,
                        shape: BoxShape.circle,
                      ),
                      child: ctrl.sending.value
                          ? const Center(
                              child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2)))
                          : const Icon(Icons.send_rounded,
                              color: Colors.white, size: 19),
                    ),
                  )),
            ],
          ),
        ),
      ]),
    );
  }
}
// ─── TUILE COMMENTAIRE — style TikTok / X ────────────────────────
//
//  [avatar]  @pseudo · 2h                          [♥ 4]
//            Texte du commentaire sur
//            plusieurs lignes si besoin
//            Répondre
//            ↳ [replies indentés]

class _CommentTile extends StatelessWidget {
  final AnnonceCommentModel comment;
  final AnnonceCommentController ctrl;
  final bool isReply;
  const _CommentTile({
    required this.comment,
    required this.ctrl,
    required this.isReply,
  });

  static String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays >= 365) return '${(diff.inDays / 365).floor()}a';
    if (diff.inDays >= 30) return '${(diff.inDays / 30).floor()}mo';
    if (diff.inDays >= 7) return '${(diff.inDays / 7).floor()}sem';
    if (diff.inDays >= 1) return '${diff.inDays}j';
    if (diff.inHours >= 1) return '${diff.inHours}h';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}min';
    return 'maintenant';
  }

  void _openProfile(BuildContext context) {
    if (comment.isAnonyme) return;
    Get.toNamed('/profil/detail',
        arguments: UserModel(
          id: comment.userId,
          name: comment.userName,
          age: 18,
          photoUrl: comment.userPhotoUrl,
          isOnline: false,
          interests: [],
        ));
  }

  void _onLongPress(BuildContext context) {
    final myUid = Supabase.instance.client.auth.currentUser?.id;
    final isOwn = comment.userId == myUid;
    final isAnnonceOwner = ctrl.annonce.userId == myUid;
    if (!isOwn && !isAnnonceOwner) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF13131F),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 6),
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFF353550),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
            leading:
                const Icon(Icons.delete_outline_rounded, color: Colors.red),
            title: Text(
              isAnnonceOwner && !isOwn
                  ? 'Supprimer (modération)'
                  : 'Supprimer mon commentaire',
              style: const TextStyle(
                  color: Colors.red, fontWeight: FontWeight.w600),
            ),
            onTap: () {
              Navigator.pop(context);
              ctrl.deleteComment(comment);
            },
          ),
          ListTile(
            leading:
                const Icon(Icons.close_rounded, color: AppColors.textMuted),
            title: const Text('Annuler',
                style: TextStyle(color: AppColors.textMuted)),
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double avatarR = isReply ? 14 : 18;

    return GestureDetector(
      onLongPress: () => _onLongPress(context),
      child: Padding(
        padding: EdgeInsets.only(
          left: isReply ? 44 : 0,
          bottom: isReply ? 10 : 14,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Avatar ──────────────────────────────────────────
            GestureDetector(
              onTap: () => _openProfile(context),
              child: CircleAvatar(
                radius: avatarR,
                backgroundColor: AppColors.surface2,
                backgroundImage: comment.userPhotoUrl != null
                    ? CachedNetworkImageProvider(comment.userPhotoUrl!)
                    : null,
                child: comment.userPhotoUrl == null
                    ? Icon(
                        comment.isAnonyme
                            ? Icons.person_outline_rounded
                            : Icons.person_rounded,
                        color: Colors.white54,
                        size: avatarR,
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 10),

            // ── Corps ────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ligne pseudo + heure
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () => _openProfile(context),
                        child: Text(
                          comment.isAnonyme ? 'Anonyme' : comment.userName,
                          style: TextStyle(
                            color: comment.isAnonyme
                                ? AppColors.textMuted
                                : Colors.white,
                            fontSize: isReply ? 12 : 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _ago(comment.createdAt),
                        style: TextStyle(
                            color: Colors.white38, fontSize: isReply ? 10 : 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),

                  // Texte du commentaire — pas de bulle
                  Text(
                    comment.texte,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: isReply ? 13 : 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Actions : Répondre
                  if (!isReply)
                    GestureDetector(
                      onTap: () =>
                          ctrl.startReply(comment.id, comment.userName),
                      child: const Text(
                        'Répondre',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                  // Replies imbriqués
                  if (comment.replies.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...comment.replies.map((r) =>
                        _CommentTile(comment: r, ctrl: ctrl, isReply: true)),
                  ],
                ],
              ),
            ),

            // ── Like (à droite comme TikTok) ─────────────────────
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => ctrl.toggleLike(comment),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      comment.isLiked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      key: ValueKey(comment.isLiked),
                      color:
                          comment.isLiked ? Colors.pinkAccent : Colors.white38,
                      size: isReply ? 14 : 16,
                    ),
                  ),
                  if (comment.likes > 0)
                    Text(
                      '${comment.likes}',
                      style: TextStyle(
                        color: comment.isLiked
                            ? Colors.pinkAccent
                            : Colors.white38,
                        fontSize: 10,
                      ),
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

// ─── VIDEO PREVIEW (header commentaires) ──────────────────────────

class _AnnonceVideoPreview extends StatefulWidget {
  final String url;
  const _AnnonceVideoPreview({required this.url});
  @override
  State<_AnnonceVideoPreview> createState() => _AnnonceVideoPreviewState();
}

class _AnnonceVideoPreviewState extends State<_AnnonceVideoPreview> {
  late VideoPlayerController _vpc;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _vpc = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) setState(() => _ready = true);
        _vpc.setLooping(true);
        _vpc.play();
      });
  }

  @override
  void dispose() {
    _vpc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Container(
        height: 180,
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(
              color: AppColors.accent, strokeWidth: 2),
        ),
      );
    }
    return GestureDetector(
      onTap: () {
        setState(() {
          _vpc.value.isPlaying ? _vpc.pause() : _vpc.play();
        });
      },
      child: AspectRatio(
        aspectRatio: _vpc.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_vpc),
            ValueListenableBuilder(
              valueListenable: _vpc,
              builder: (_, VideoPlayerValue v, __) => AnimatedOpacity(
                opacity: v.isPlaying ? 0.0 : 0.7,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 28),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── DETAIL ANNONCE ───────────────────────────────────────────────

class _AnnonceDetailSheet extends GetView<AnnoncesController> {
  final AnnonceModel annonce;
  const _AnnonceDetailSheet({required this.annonce});

  String get _emoji {
    const m = {
      'rencontre': '💕',
      'amitie': '🤝',
      'sortie': '🎉',
      'voyage': '✈️',
    };
    return m[annonce.categorie] ?? '📢';
  }

  String get _ago {
    final d = DateTime.now().difference(annonce.createdAt);
    if (d.inDays > 0) return 'il y a ${d.inDays}j';
    if (d.inHours > 0) return 'il y a ${d.inHours}h';
    if (d.inMinutes > 0) return 'il y a ${d.inMinutes}min';
    return "à l'instant";
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header profil
                    Row(children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: annonce.isAnonyme
                                    ? const Color(0xFF6C3FC5)
                                    : AppColors.accent,
                                width: 2)),
                        child: ClipOval(
                            child: annonce.isAnonyme
                                ? Container(
                                    decoration: const BoxDecoration(
                                        gradient: LinearGradient(colors: [
                                      Color(0xFF6C3FC5),
                                      Color(0xFF3B1F7A),
                                    ])),
                                    child: const Center(
                                        child: Icon(
                                            Icons.person_outline_rounded,
                                            color: Colors.white,
                                            size: 28)))
                                : (annonce.userPhotoUrl != null
                                    ? CachedNetworkImage(
                                        imageUrl: annonce.userPhotoUrl!,
                                        fit: BoxFit.cover)
                                    : Container(
                                        decoration: const BoxDecoration(
                                            gradient: LinearGradient(colors: [
                                          AppColors.accent,
                                          AppColors.accent2,
                                        ])),
                                        child: Center(
                                            child: Text(
                                                annonce.userName[0]
                                                    .toUpperCase(),
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 22)))))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(
                                annonce.isAnonyme
                                    ? 'Utilisateur anonyme'
                                    : annonce.userName,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.textPrimary)),
                            Row(children: [
                              if (annonce.ville != null &&
                                  !annonce.isAnonyme) ...[
                                const Icon(Icons.location_on_rounded,
                                    size: 12, color: AppColors.textMuted),
                                Text(annonce.ville!,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textMuted)),
                                const SizedBox(width: 8),
                              ],
                              Text(_ago,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted)),
                            ]),
                          ])),
                    ]),
                    const SizedBox(height: 20),

                    // Catégorie
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                            color: AppColors.accent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.accent.withOpacity(0.3))),
                        child: Text('$_emoji ${annonce.categorie}',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accent))),
                    const SizedBox(height: 12),
                    Text(annonce.titre,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                            height: 1.2)),
                    if (annonce.description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(annonce.description,
                          style: const TextStyle(
                              fontSize: 15,
                              color: AppColors.textMuted,
                              height: 1.6)),
                    ],
                    const SizedBox(height: 20),

                    // Media
                    if (annonce.mediaUrl != null) ...[
                      annonce.isVideo
                          ? _AutoplayVideoPlayer(
                              url: annonce.mediaUrl!,
                              annonceId: '${annonce.id}_detail')
                          : GestureDetector(
                              onTap: () => _openImage(context),
                              child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: CachedNetworkImage(
                                      imageUrl: annonce.mediaUrl!,
                                      width: double.infinity,
                                      fit: BoxFit.cover))),
                      const SizedBox(height: 20),
                    ],

                    // Actions like + commenter
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                          border: Border(
                              top: BorderSide(color: AppColors.border),
                              bottom: BorderSide(color: AppColors.border))),
                      child: Obx(() {
                        final current = controller.annonces
                                .firstWhereOrNull((a) => a.id == annonce.id) ??
                            annonce;
                        return Row(children: [
                          GestureDetector(
                            onTap: () => controller.toggleLike(current),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: Row(
                                  key: ValueKey(current.isLiked),
                                  children: [
                                    Icon(
                                        current.isLiked
                                            ? Icons.favorite_rounded
                                            : Icons.favorite_outline_rounded,
                                        color: current.isLiked
                                            ? Colors.red
                                            : AppColors.textMuted,
                                        size: 26),
                                    const SizedBox(width: 6),
                                    Text('${current.likes}',
                                        style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: current.isLiked
                                                ? Colors.red
                                                : AppColors.textMuted)),
                                  ]),
                            ),
                          ),
                          const SizedBox(width: 24),
                          GestureDetector(
                            onTap: annonce.commentsEnabled
                                ? () => AnnonceCommentsSheet.show(context,
                                    annonce: annonce)
                                : null,
                            child: Row(children: [
                              const Icon(Icons.chat_bubble_outline_rounded,
                                  color: AppColors.textMuted, size: 22),
                              const SizedBox(width: 6),
                              Text(
                                  '${current.reponsesCount} commentaire${current.reponsesCount > 1 ? 's' : ''}',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textMuted,
                                      fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ]);
                      }),
                    ),
                    const SizedBox(height: 8),
                    // commentaires → ouverts directement via le bouton commentaire
                  ]),
            ),
          ),
        ]),
      ),
    );
  }

  void _openImage(BuildContext context) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => Scaffold(
                  backgroundColor: Colors.black,
                  appBar: AppBar(
                      backgroundColor: Colors.black,
                      leading: IconButton(
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white),
                          onPressed: () => Navigator.pop(context))),
                  body: Center(
                      child: InteractiveViewer(
                          child:
                              CachedNetworkImage(imageUrl: annonce.mediaUrl!))),
                )));
  }
}

// ─── AUTOPLAY VIDEO PLAYER ────────────────────────────────────────

class _AutoplayVideoPlayer extends StatefulWidget {
  final String url;
  final String annonceId;
  const _AutoplayVideoPlayer({required this.url, required this.annonceId});

  @override
  State<_AutoplayVideoPlayer> createState() => _AutoplayVideoPlayerState();
}

class _AutoplayVideoPlayerState extends State<_AutoplayVideoPlayer> {
  late VideoPlayerController _ctrl;
  bool _initialized = false;
  bool _muted = true;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    await _ctrl.initialize();
    _ctrl.setLooping(true);
    _ctrl.setVolume(0);
    if (mounted) setState(() => _initialized = true);
    if (_visible) _ctrl.play();
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    final isVisible = info.visibleFraction > 0.5;
    if (isVisible != _visible) {
      _visible = isVisible;
      if (_initialized) {
        if (isVisible) {
          _ctrl.play();
        } else {
          _ctrl.pause();
        }
      }
    }
  }

  void _toggleSound() {
    setState(() => _muted = !_muted);
    _ctrl.setVolume(_muted ? 0 : 1);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('video_${widget.annonceId}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            _initialized
                ? AspectRatio(
                    aspectRatio: _ctrl.value.aspectRatio,
                    child: VideoPlayer(_ctrl))
                : Container(
                    height: 220,
                    color: AppColors.surface2,
                    child: const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.accent))),
            GestureDetector(
              onTap: _toggleSound,
              child: Container(
                  margin: const EdgeInsets.all(10),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.2))),
                  child: Icon(
                      _muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      color: Colors.white,
                      size: 17)),
            ),
            if (_initialized)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 12),
                      SizedBox(width: 3),
                      Text('Vidéo',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ])),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── BOOST BUTTON ─────────────────────────────────────────────────

class _BoostButton extends GetView<AnnoncesController> {
  final AnnonceModel annonce;
  const _BoostButton({required this.annonce});

  @override
  Widget build(BuildContext context) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId != annonce.userId) return const SizedBox.shrink();
    if (annonce.isBoosted) {
      return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: const Color(0xFFFFD700).withOpacity(0.4))),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.bolt_rounded, size: 13, color: Color(0xFFFFD700)),
            SizedBox(width: 3),
            Text('Boostée',
                style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFFFFD700),
                    fontWeight: FontWeight.w700)),
          ]));
    }
    return Obx(() => GestureDetector(
        onTap: controller.isBoosting.value ? null : () => _confirm(context),
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFFFFD700).withOpacity(0.3),
                      blurRadius: 8)
                ]),
            child: controller.isBoosting.value
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.bolt_rounded, size: 13, color: Colors.white),
                    SizedBox(width: 3),
                    Text('Booster',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ]))));
  }

  void _confirm(BuildContext context) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
                backgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: const Row(children: [
                  Icon(Icons.bolt_rounded, color: Color(0xFFFFD700), size: 22),
                  SizedBox(width: 8),
                  Text('Booster l\'annonce',
                      style: TextStyle(
                          fontFamily: 'Syne',
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary)),
                ]),
                content: const Text(
                    'Ton annonce apparaîtra en tête de liste pendant 24h.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Annuler',
                          style: TextStyle(color: AppColors.textMuted))),
                  GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        controller.boosterAnnonce(annonce);
                      },
                      child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                Color(0xFFFFD700),
                                Color(0xFFFF8C00),
                              ]),
                              borderRadius: BorderRadius.circular(10)),
                          child: const Text('⚡ Booster !',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)))),
                ]));
  }
}

// ─── BOOST PROFIL WIDGET ──────────────────────────────────────────

class BoostProfilWidget extends StatelessWidget {
  const BoostProfilWidget({super.key});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: () => _sheet(context),
      child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.4),
                    blurRadius: 12)
              ]),
          child:
              const Icon(Icons.bolt_rounded, color: Colors.white, size: 22)));

  void _sheet(BuildContext context) {
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border.all(color: AppColors.border)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2))),
                Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [
                          Color(0xFFFFD700),
                          Color(0xFFFF8C00),
                        ]),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: const Color(0xFFFFD700).withOpacity(0.4),
                              blurRadius: 20)
                        ]),
                    child: const Icon(Icons.bolt_rounded,
                        color: Colors.white, size: 42)),
                const SizedBox(height: 20),
                const Text('Booster ton profil',
                    style: TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                const Text(
                    'Apparais en premier dans la liste\npendant 30 minutes',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                const SizedBox(height: 24),
                _Feat('🔝', 'Premier dans les résultats'),
                const SizedBox(height: 8),
                _Feat('👁️', 'Plus de vues sur ton profil'),
                const SizedBox(height: 8),
                _Feat('💬', 'Plus de messages reçus'),
                const SizedBox(height: 28),
                GestureDetector(
                    onTap: () async {
                      Navigator.pop(context);
                      if (!Get.isRegistered<AnnoncesController>()) {
                        Get.put(AnnoncesController());
                      }
                      await Get.find<AnnoncesController>().boosterProfil();
                    },
                    child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [
                              Color(0xFFFFD700),
                              Color(0xFFFF8C00),
                            ]),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                  color:
                                      const Color(0xFFFFD700).withOpacity(0.4),
                                  blurRadius: 16)
                            ]),
                        child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.bolt_rounded,
                                  color: Colors.white, size: 22),
                              SizedBox(width: 8),
                              Text('⚡ Activer le Boost — Gratuit',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white)),
                            ]))),
                const SizedBox(height: 10),
                const Text('Bientôt : Boost Premium 30min / 24h / 7j',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ]),
            ));
  }
}

class _Feat extends StatelessWidget {
  final String emoji, text;
  const _Feat(this.emoji, this.text);
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 18)))),
        const SizedBox(width: 12),
        Text(text,
            style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600)),
      ]);
}

// ─── HELPERS ──────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  const _Field(
      {required this.controller, required this.hint, required this.maxLines});
  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      child: TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppColors.textMuted),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12))));
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MenuItem(this.icon, this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.2))),
          child: Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 15, fontWeight: FontWeight.w600)),
          ])));
}
