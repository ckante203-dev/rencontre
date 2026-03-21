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

// ─── SKELETON LOADING ────────────────────────────────────────────

class _AnnoncesSkeletonList extends StatefulWidget {
  @override
  State<_AnnoncesSkeletonList> createState() => _AnnoncesSkeletonListState();
}

class _AnnoncesSkeletonListState extends State<_AnnoncesSkeletonList>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 0.7)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 4,
        itemBuilder: (_, i) => _SkeletonCard(opacity: _anim.value),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final double opacity;
  const _SkeletonCard({required this.opacity});

  Widget _box({double w = double.infinity, double h = 14, double r = 8}) =>
      Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(opacity * 0.15),
          borderRadius: BorderRadius.circular(r),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(opacity * 0.15))),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _box(w: 100, h: 12),
            const SizedBox(height: 6),
            _box(w: 70, h: 10),
          ]),
        ]),
        const SizedBox(height: 14),
        _box(h: 12),
        const SizedBox(height: 8),
        _box(w: 200, h: 12),
        const SizedBox(height: 12),
        // Image placeholder (1 sur 2)
        if (opacity > 0.4)
          Container(
              height: 180,
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(opacity * 0.1),
                  borderRadius: BorderRadius.circular(12))),
        const SizedBox(height: 12),
        // Actions
        Row(children: [
          _box(w: 50, h: 12, r: 6),
          const SizedBox(width: 20),
          _box(w: 70, h: 12, r: 6),
        ]),
      ]),
    );
  }
}

// ─── ECRAN ANNONCES ───────────────────────────────────────────────

class AnnoncesScreen extends StatelessWidget {
  const AnnoncesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    // ✅ Permanent = données gardées en mémoire entre les navigations
    if (!Get.isRegistered<AnnoncesController>()) {
      Get.put(AnnoncesController(), permanent: true);
    } else {
      // ✅ Déjà chargé → refresh silencieux en arrière-plan sans vider la liste
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.find<AnnoncesController>().refreshSilent();
      });
    }
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
    final scrollCtrl = ScrollController();
    final searchCtrl = TextEditingController();
    scrollCtrl.addListener(() {
      if (scrollCtrl.position.pixels >=
          scrollCtrl.position.maxScrollExtent - 200) {
        controller.loadMore();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          // ── Header ──
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
              // ✅ Mes annonces
              GestureDetector(
                onTap: () => _showMesAnnonces(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.person_outline_rounded,
                      color: AppColors.textMuted, size: 18),
                ),
              ),
              // ✅ Publier
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

          // ✅ Barre de recherche
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: searchCtrl,
                style:
                    const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                onChanged: (v) => controller.searchQuery.value = v,
                decoration: InputDecoration(
                  hintText: 'Rechercher par titre, ville, auteur...',
                  hintStyle:
                      const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.textMuted, size: 20),
                  suffixIcon: Obx(() => controller.searchQuery.value.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            searchCtrl.clear();
                            controller.searchQuery.value = '';
                          },
                          child: const Icon(Icons.close_rounded,
                              color: AppColors.textMuted, size: 18))
                      : const SizedBox.shrink()),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Filtres catégories ──
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

          // ── Liste ──
          Expanded(
            child: Obx(() {
              // ✅ Skeleton — seulement au tout premier chargement (liste vide)
              if (controller.isLoading.value && controller.annonces.isEmpty) {
                return _AnnoncesSkeletonList();
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
                        Text(
                          controller.searchQuery.value.isNotEmpty
                              ? 'Aucun résultat pour "${controller.searchQuery.value}"'
                              : 'Aucune annonce',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text('Sois le premier à publier !',
                            style: TextStyle(color: AppColors.textMuted)),
                      ]),
                );
              }
              return RefreshIndicator(
                color: AppColors.accent,
                backgroundColor: AppColors.surface,
                onRefresh: controller.loadAnnonces,
                child: ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: list.length + 1,
                  itemBuilder: (_, i) {
                    if (i == list.length) {
                      return Obx(() {
                        if (!controller.hasMore.value) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                                child: Text('— Fin des annonces —',
                                    style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 12))),
                          );
                        }
                        if (controller.isLoadingMore.value) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.accent, strokeWidth: 2)),
                          );
                        }
                        return const SizedBox(height: 20);
                      });
                    }
                    return _AnnonceCard(annonce: list[i]);
                  },
                ),
              );
            }),
          ),
        ]),
      ),
    );
  }

  // ✅ Mes annonces
  void _showMesAnnonces(BuildContext context) {
    Get.find<AnnoncesController>().loadMesAnnonces();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _MesAnnoncesSheet(),
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
        'voyage': '✈️ Voyage'
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
                  )),
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
                  )),
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
                if (mediaFile != null && !isVideo) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(File(mediaFile!.path),
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover)),
                ],
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
                _ToggleRow(
                  active: anonyme,
                  icon: Icons.visibility_off_rounded,
                  activeColor: const Color(0xFF6C3FC5),
                  label: 'Publier en anonyme',
                  sub: 'Ton nom et photo seront masqués',
                  onTap: () => setS(() => anonyme = !anonyme),
                ),
                const SizedBox(height: 10),
                // Toggle commentaires
                _ToggleRow(
                  active: !commentsEnabled,
                  icon: commentsEnabled
                      ? Icons.chat_bubble_outline_rounded
                      : Icons.comments_disabled_outlined,
                  activeColor: Colors.orange,
                  label: commentsEnabled
                      ? 'Commentaires activés'
                      : 'Commentaires désactivés',
                  sub: commentsEnabled
                      ? 'Les gens peuvent répondre'
                      : 'Personne ne peut commenter',
                  onTap: () => setS(() => commentsEnabled = !commentsEnabled),
                  toggleActive: commentsEnabled,
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: loading
                      ? null
                      : () async {
                          final hasMedia = mediaFile != null;
                          if (!hasMedia &&
                              (titreCtrl.text.trim().isEmpty ||
                                  descCtrl.text.trim().isEmpty)) {
                            Get.snackbar('Champs requis',
                                'Ajoute un titre et une description, ou joins une photo/vidéo',
                                snackPosition: SnackPosition.TOP,
                                backgroundColor: Colors.red.shade900,
                                colorText: Colors.white);
                            return;
                          }
                          final titre = titreCtrl.text.trim().isEmpty
                              ? '📸'
                              : titreCtrl.text.trim();
                          setS(() => loading = true);
                          final ok = await Get.find<AnnoncesController>()
                              .publierAnnonce(
                            titre: titre,
                            description: descCtrl.text.trim(),
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
                            Get.snackbar('Annonce publiée ✅', '',
                                snackPosition: SnackPosition.TOP,
                                backgroundColor: AppColors.surface,
                                colorText: Colors.white);
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
                        ]),
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

// ─── MES ANNONCES ─────────────────────────────────────────────────

class _MesAnnoncesSheet extends GetView<AnnoncesController> {
  const _MesAnnoncesSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Text('Mes annonces',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const Spacer(),
              GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close_rounded,
                      color: AppColors.textMuted)),
            ]),
          ),
          const SizedBox(height: 12),
          Expanded(child: Obx(() {
            if (controller.isLoadingMesAnnonces.value) {
              return const Center(
                  child: CircularProgressIndicator(color: AppColors.accent));
            }
            final list = controller.mesAnnonces;
            if (list.isEmpty) {
              return const Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Icon(Icons.campaign_outlined,
                        size: 48, color: AppColors.textMuted),
                    SizedBox(height: 12),
                    Text('Aucune annonce publiée',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 15)),
                  ]));
            }
            return ListView.builder(
              controller: scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: list.length,
              itemBuilder: (_, i) => _MesAnnoncesItem(annonce: list[i]),
            );
          })),
        ]),
      ),
    );
  }
}

class _MesAnnoncesItem extends GetView<AnnoncesController> {
  final AnnonceModel annonce;
  const _MesAnnoncesItem({required this.annonce});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border)),
      child: Row(children: [
        // Media thumbnail
        if (annonce.mediaUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
                imageUrl: annonce.mediaUrl!,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                    width: 60,
                    height: 60,
                    color: AppColors.surface,
                    child: const Icon(Icons.broken_image_rounded,
                        color: AppColors.textMuted))),
          )
        else
          Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border)),
              child: const Center(
                  child: Icon(Icons.campaign_rounded,
                      color: AppColors.textMuted, size: 28))),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(annonce.titre,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.favorite_rounded, size: 12, color: Colors.red),
            const SizedBox(width: 3),
            Text('${annonce.likes}',
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            const SizedBox(width: 10),
            const Icon(Icons.chat_bubble_outline_rounded,
                size: 12, color: AppColors.textMuted),
            const SizedBox(width: 3),
            Text('${annonce.reponsesCount}',
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            const SizedBox(width: 10),
            const Icon(Icons.visibility_outlined,
                size: 12, color: AppColors.textMuted),
            const SizedBox(width: 3),
            Text('${annonce.viewsCount}',
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
        ])),
        // Actions
        Column(children: [
          GestureDetector(
            onTap: () => _modifierAnnonce(context),
            child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: AppColors.accent.withOpacity(0.3))),
                child: const Icon(Icons.edit_outlined,
                    color: AppColors.accent, size: 16)),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => controller.supprimerAnnonce(annonce.id),
            child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3))),
                child: const Icon(Icons.delete_outline_rounded,
                    color: Colors.red, size: 16)),
          ),
        ]),
      ]),
    );
  }

  void _modifierAnnonce(BuildContext context) {
    final titreCtrl =
        TextEditingController(text: annonce.titre == '📸' ? '' : annonce.titre);
    final descCtrl = TextEditingController(text: annonce.description);
    final villeCtrl = TextEditingController(text: annonce.ville ?? '');
    bool saving = false;

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
              const Text('Modifier l\'annonce',
                  style: TextStyle(
                      fontFamily: 'Syne',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 20),
              _Field(controller: titreCtrl, hint: 'Titre', maxLines: 1),
              const SizedBox(height: 12),
              _Field(controller: descCtrl, hint: 'Description', maxLines: 4),
              const SizedBox(height: 12),
              _Field(
                  controller: villeCtrl,
                  hint: 'Ville (optionnel)',
                  maxLines: 1),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: saving
                    ? null
                    : () async {
                        setS(() => saving = true);
                        final ok = await Get.find<AnnoncesController>()
                            .modifierAnnonce(
                          id: annonce.id,
                          titre: titreCtrl.text.trim().isEmpty
                              ? '📸'
                              : titreCtrl.text.trim(),
                          description: descCtrl.text.trim(),
                          ville: villeCtrl.text.trim().isEmpty
                              ? null
                              : villeCtrl.text.trim(),
                        );
                        setS(() => saving = false);
                        if (ok) {
                          Navigator.pop(ctx);
                          Get.snackbar('✅ Annonce modifiée', '',
                              snackPosition: SnackPosition.TOP,
                              backgroundColor: AppColors.surface,
                              colorText: Colors.white);
                        }
                      },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                      gradient: AppColors.gradientPink,
                      borderRadius: BorderRadius.circular(16)),
                  child: saving
                      ? const Center(
                          child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5)))
                      : const Text('Sauvegarder',
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
      'voyage': '✈️'
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
    return VisibilityDetector(
      key: Key('annonce_${annonce.id}'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.5) {
          controller.marquerVue(annonce);
        }
      },
      child: GestureDetector(
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
                        color: AppColors.accent.withOpacity(0.1),
                        blurRadius: 16)
                  ]
                : null,
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                            width: 1.5)),
                    child: ClipOval(
                      child: annonce.isAnonyme
                          ? Container(
                              decoration: const BoxDecoration(
                                  gradient: LinearGradient(colors: [
                                Color(0xFF6C3FC5),
                                Color(0xFF3B1F7A)
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
                    onTap:
                        annonce.isAnonyme ? null : () => _openProfil(annonce),
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
                                    color: const Color(0xFF6C3FC5)
                                        .withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0xFF6C3FC5)
                                            .withOpacity(0.4))),
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
                                      fontSize: 12,
                                      color: AppColors.textMuted)),
                            ],
                          ]),
                          Row(children: [
                            if (annonce.ville != null &&
                                !annonce.isAnonyme) ...[
                              const Icon(Icons.location_on_rounded,
                                  size: 11, color: AppColors.textMuted),
                              Text(annonce.ville!,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted)),
                              const SizedBox(width: 8),
                            ],
                            Text(_ago,
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.textMuted)),
                            // ✅ Compteur de vues
                            const SizedBox(width: 8),
                            const Icon(Icons.visibility_outlined,
                                size: 11, color: AppColors.textMuted),
                            const SizedBox(width: 2),
                            Text('${annonce.viewsCount}',
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
                        gradient: const LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
                        borderRadius: BorderRadius.circular(10)),
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
                      const BorderRadius.vertical(bottom: Radius.circular(20))),
              child: Row(children: [
                // ✅ Réactions
                GestureDetector(
                  onTap: () => controller.toggleReaction(annonce, '❤️'),
                  onLongPress: () => _showReactionPicker(context),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Row(key: ValueKey(annonce.myReaction), children: [
                      Text(
                          annonce.myReaction.isNotEmpty
                              ? annonce.myReaction
                              : '🤍',
                          style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 5),
                      Text('${annonce.likes}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: annonce.isLiked
                                  ? Colors.red
                                  : AppColors.textMuted)),
                    ]),
                  ),
                ),

                // ✅ Mini réactions affichées
                if (annonce.reactionCounts.length > 1) ...[
                  const SizedBox(width: 6),
                  ...annonce.reactionCounts.entries
                      .where((e) =>
                          e.key !=
                          (annonce.myReaction.isNotEmpty
                              ? annonce.myReaction
                              : '❤️'))
                      .take(2)
                      .map((e) =>
                          Text(e.key, style: const TextStyle(fontSize: 14))),
                ],

                const SizedBox(width: 16),

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

                // ✅ Partager
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () => _showPartagerSheet(context),
                  child: const Icon(Icons.send_outlined,
                      color: AppColors.textMuted, size: 18),
                ),

                const Spacer(),
                _BoostButton(annonce: annonce),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ✅ Picker réactions — appui long
  void _showReactionPicker(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
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
          const Text('Réagir à cette annonce',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: AnnoncesController.reactions.map((emoji) {
                final isSelected = annonce.myReaction == emoji;
                final count = annonce.reactionCounts[emoji] ?? 0;
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    controller.toggleReaction(annonce, emoji);
                  },
                  child: Column(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.accent.withOpacity(0.15)
                              : AppColors.surface2,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: isSelected
                                  ? AppColors.accent
                                  : Colors.transparent)),
                      child: Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                    if (count > 0) ...[
                      const SizedBox(height: 4),
                      Text('$count',
                          style: TextStyle(
                              fontSize: 11,
                              color: isSelected
                                  ? AppColors.accent
                                  : AppColors.textMuted,
                              fontWeight: FontWeight.w600)),
                    ],
                  ]),
                );
              }).toList()),
        ]),
      ),
    );
  }

  // ✅ Partager une annonce
  void _showPartagerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PartagerSheet(annonce: annonce),
    );
  }

  void _openProfil(AnnonceModel annonce) {
    Get.toNamed('/profil/detail',
        arguments: UserModel(
          id: annonce.userId,
          name: annonce.userName,
          age: annonce.userAge,
          photoUrl: annonce.userPhotoUrl,
          isOnline: false,
          interests: [],
        ));
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

  void _menu(BuildContext context) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
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
          if (myId == annonce.userId) ...[
            _MenuItem(Icons.delete_outline_rounded, 'Supprimer', Colors.red,
                () {
              Navigator.pop(context);
              controller.supprimerAnnonce(annonce.id);
            }),
            const SizedBox(height: 8),
          ],
          _MenuItem(Icons.flag_outlined, 'Signaler', Colors.orange, () {
            Navigator.pop(context);
            _showSignalementSheet(context);
          }),
          const SizedBox(height: 8),
          _MenuItem(Icons.close_rounded, 'Fermer', AppColors.textMuted,
              () => Navigator.pop(context)),
        ]),
      ),
    );
  }

  void _showSignalementSheet(BuildContext context) {
    final reasons = [
      '🔞 Contenu inapproprié',
      '🚫 Spam ou arnaque',
      '😡 Harcèlement',
      '❌ Fausses informations',
      '⚠️ Autre'
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
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
          const Text('Pourquoi signaler ?',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          ...reasons.map((r) => GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  controller.signalerAnnonce(annonce.id, r);
                },
                child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border)),
                    child: Text(r,
                        style: const TextStyle(
                            fontSize: 14, color: AppColors.textPrimary))),
              )),
        ]),
      ),
    );
  }
}

// ─── PARTAGER ANNONCE ─────────────────────────────────────────────

class _PartagerSheet extends StatefulWidget {
  final AnnonceModel annonce;
  const _PartagerSheet({required this.annonce});
  @override
  State<_PartagerSheet> createState() => _PartagerSheetState();
}

class _PartagerSheetState extends State<_PartagerSheet> {
  List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;
  final Set<String> _sending = {};

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final data = await Supabase.instance.client
          .from('conversations')
          .select('''
        id, user1_id, user2_id,
        user1_profile:profiles!conversations_user1_id_fkey(id, name, photo_url),
        user2_profile:profiles!conversations_user2_id_fkey(id, name, photo_url)
      ''')
          .or('user1_id.eq.$uid,user2_id.eq.$uid')
          .order('updated_at', ascending: false)
          .limit(20);

      setState(() {
        _conversations = (data as List).map((row) {
          final isUser1 = row['user1_id'] == uid;
          final other = isUser1 ? row['user2_profile'] : row['user1_profile'];
          return {
            'convId': row['id'],
            'userId': other?['id'] ?? '',
            'name': other?['name'] ?? 'Utilisateur',
            'photo': other?['photo_url'],
          };
        }).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Text('Partager l\'annonce',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const Spacer(),
              GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close_rounded,
                      color: AppColors.textMuted)),
            ]),
          ),
          const SizedBox(height: 12),
          // Preview annonce
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border)),
            child: Row(children: [
              if (widget.annonce.mediaUrl != null && !widget.annonce.isVideo)
                ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                        imageUrl: widget.annonce.mediaUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const SizedBox.shrink()))
              else
                Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Center(
                        child: Icon(Icons.campaign_rounded,
                            color: AppColors.accent, size: 24))),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(widget.annonce.titre,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(widget.annonce.description,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ])),
            ]),
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Envoyer à :',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600))),
          ),
          const SizedBox(height: 8),
          Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accent, strokeWidth: 2))
                  : _conversations.isEmpty
                      ? const Center(
                          child: Text('Aucune conversation',
                              style: TextStyle(color: AppColors.textMuted)))
                      : ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _conversations.length,
                          itemBuilder: (_, i) {
                            final conv = _conversations[i];
                            final isSending = _sending.contains(conv['userId']);
                            return GestureDetector(
                              onTap: isSending
                                  ? null
                                  : () async {
                                      setState(
                                          () => _sending.add(conv['userId']));
                                      await Get.find<AnnoncesController>()
                                          .partagerAnnonce(
                                              widget.annonce, conv['userId']);
                                      setState(() =>
                                          _sending.remove(conv['userId']));
                                      if (mounted) Navigator.pop(context);
                                    },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                margin: const EdgeInsets.only(bottom: 6),
                                decoration: BoxDecoration(
                                    color: AppColors.surface2,
                                    borderRadius: BorderRadius.circular(12),
                                    border:
                                        Border.all(color: AppColors.border)),
                                child: Row(children: [
                                  CircleAvatar(
                                      radius: 20,
                                      backgroundColor:
                                          AppColors.accent.withOpacity(0.1),
                                      backgroundImage: conv['photo'] != null
                                          ? CachedNetworkImageProvider(
                                              conv['photo'])
                                          : null,
                                      child: conv['photo'] == null
                                          ? Text(conv['name'][0].toUpperCase(),
                                              style: const TextStyle(
                                                  color: AppColors.accent,
                                                  fontWeight: FontWeight.w700))
                                          : null),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Text(conv['name'],
                                          style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textPrimary))),
                                  isSending
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              color: AppColors.accent,
                                              strokeWidth: 2))
                                      : const Icon(Icons.send_rounded,
                                          color: AppColors.accent, size: 20),
                                ]),
                              ),
                            );
                          })),
        ]),
      ),
    );
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
        builder: (_) => AnnonceCommentsSheet(annonce: annonce));
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
          annonce: annonce, ctrl: ctrl, tag: tag, scrollCtrl: scrollCtrl),
    );
  }
}

class _CommentsSheetContent extends StatefulWidget {
  final AnnonceModel annonce;
  final AnnonceCommentController ctrl;
  final String tag;
  final ScrollController scrollCtrl;
  const _CommentsSheetContent(
      {required this.annonce,
      required this.ctrl,
      required this.tag,
      required this.scrollCtrl});
  @override
  State<_CommentsSheetContent> createState() => _CommentsSheetContentState();
}

class _CommentsSheetContentState extends State<_CommentsSheetContent> {
  final FocusNode _focusNode = FocusNode();
  String? _myPhotoUrl;

  @override
  void initState() {
    super.initState();
    _loadMyPhoto();
  }

  Future<void> _loadMyPhoto() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('photo_url')
          .eq('id', uid)
          .maybeSingle();
      if (mounted) setState(() => _myPhotoUrl = data?['photo_url'] as String?);
    } catch (_) {}
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final annonce = widget.annonce;
    final ctrl = widget.ctrl;
    final tag = widget.tag;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D18),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        // ── Handle ──
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
              color: const Color(0xFF2E2E4A),
              borderRadius: BorderRadius.circular(2)),
        ),

        // ── Header ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
          child: Row(children: [
            Obx(() {
              final n =
                  ctrl.comments.fold(0, (s, c) => s + 1 + c.replies.length);
              return RichText(
                  text: TextSpan(
                children: [
                  const TextSpan(
                      text: 'Commentaires  ',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Syne')),
                  TextSpan(
                      text: '$n',
                      style: const TextStyle(
                          color: Color(0xFF6060A0),
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                ],
              ));
            }),
            const Spacer(),
            GestureDetector(
              onTap: () {
                Get.delete<AnnonceCommentController>(tag: tag);
                Navigator.pop(context);
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: const Color(0xFF1E1E30), shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded,
                    color: Color(0xFF8080B0), size: 16),
              ),
            ),
          ]),
        ),

        Container(height: 0.5, color: const Color(0xFF1E1E30)),

        // ── Liste ──
        Expanded(
          child: Obx(() {
            if (ctrl.loading.value) {
              return const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.accent, strokeWidth: 2));
            }
            final comments = ctrl.comments;
            final pinnedId = annonce.pinnedCommentId;
            AnnonceCommentModel? pinned;
            List<AnnonceCommentModel> others = [];
            for (final c in comments) {
              if (c.id == pinnedId)
                pinned = c;
              else
                others.add(c);
            }

            if (comments.isEmpty) {
              return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E), shape: BoxShape.circle),
                    child: const Icon(Icons.chat_bubble_outline_rounded,
                        color: Color(0xFF404070), size: 28)),
                const SizedBox(height: 14),
                const Text('Aucun commentaire',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                const Text('Sois le premier à commenter',
                    style: TextStyle(color: Color(0xFF6060A0), fontSize: 13)),
              ]));
            }

            return ListView(
              controller: widget.scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                // ✅ Épinglé
                if (pinned != null) ...[
                  _PinnedBadge(),
                  const SizedBox(height: 4),
                  _CommentTile(
                      comment: pinned,
                      ctrl: ctrl,
                      isReply: false,
                      isPinned: true),
                  Container(
                      height: 0.5,
                      color: const Color(0xFF1E1E30),
                      margin: const EdgeInsets.symmetric(vertical: 8)),
                ],
                // Autres
                ...others.map((c) => _CommentTile(
                    comment: c, ctrl: ctrl, isReply: false, isPinned: false)),
              ],
            );
          }),
        ),

        // ── Répondre à ──
        Obx(() {
          final name = ctrl.replyingToName.value;
          if (name.isEmpty) return const SizedBox.shrink();
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF111120),
            child: Row(children: [
              ShaderMask(
                shaderCallback: (b) => AppColors.gradientPink.createShader(b),
                child: const Icon(Icons.reply_rounded,
                    color: Colors.white, size: 14),
              ),
              const SizedBox(width: 8),
              Text('Répondre à ',
                  style:
                      const TextStyle(color: Color(0xFF8080B0), fontSize: 12)),
              Text(name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              GestureDetector(
                onTap: ctrl.cancelReply,
                child: const Icon(Icons.close_rounded,
                    color: Color(0xFF6060A0), size: 15),
              ),
            ]),
          );
        }),

        // ── Saisie ──
        Container(
          padding: EdgeInsets.only(
            left: 14,
            right: 14,
            top: 10,
            bottom: MediaQuery.of(context).viewInsets.bottom > 0
                ? MediaQuery.of(context).viewInsets.bottom + 8
                : MediaQuery.of(context).padding.bottom + 14,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D18),
            border: Border(top: BorderSide(color: const Color(0xFF1E1E30))),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            // ✅ Avatar de l'utilisateur — chargé une seule fois dans initState
            Container(
              width: 34,
              height: 34,
              margin: const EdgeInsets.only(right: 10, bottom: 4),
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.accent.withOpacity(0.4), width: 1.5)),
              child: ClipOval(
                  child: _myPhotoUrl != null
                      ? CachedNetworkImage(
                          imageUrl: _myPhotoUrl!, fit: BoxFit.cover)
                      : Container(
                          color: AppColors.accent.withOpacity(0.2),
                          child: const Icon(Icons.person_rounded,
                              color: AppColors.accent, size: 18))),
            ),
            // Champ texte
            Expanded(
                child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF2A2A45)),
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
                                    color: Colors.white30, fontSize: 10)))
                        : null,
                decoration: const InputDecoration(
                  hintText: 'Ajouter un commentaire...',
                  hintStyle: TextStyle(color: Color(0xFF4A4A70), fontSize: 13),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            )),
            const SizedBox(width: 8),
            // Bouton envoyer
            Obx(() => GestureDetector(
                  onTap: ctrl.sending.value ? null : ctrl.sendComment,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 38,
                    height: 38,
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                        gradient:
                            ctrl.sending.value ? null : AppColors.gradientPink,
                        color:
                            ctrl.sending.value ? const Color(0xFF1E1E30) : null,
                        shape: BoxShape.circle),
                    child: ctrl.sending.value
                        ? const Center(
                            child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2)))
                        : const Icon(Icons.send_rounded,
                            color: Colors.white, size: 17),
                  ),
                )),
          ]),
        ),
      ]),
    );
  }
}

class _PinnedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(children: const [
        Icon(Icons.push_pin_rounded, size: 11, color: Color(0xFF8080B0)),
        SizedBox(width: 4),
        Text('Commentaire épinglé',
            style: TextStyle(
                fontSize: 11,
                color: Color(0xFF8080B0),
                fontWeight: FontWeight.w500)),
      ]);
}

// ─── TUILE COMMENTAIRE ────────────────────────────────────────────

class _CommentTile extends StatelessWidget {
  final AnnonceCommentModel comment;
  final AnnonceCommentController ctrl;
  final bool isReply;
  final bool isPinned;
  const _CommentTile(
      {required this.comment,
      required this.ctrl,
      required this.isReply,
      required this.isPinned});

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
            interests: []));
  }

  void _onLongPress(BuildContext context) {
    final myUid = Supabase.instance.client.auth.currentUser?.id;
    final isOwn = comment.userId == myUid;
    final isAnnonceOwner = ctrl.annonce.userId == myUid;
    if (!isOwn && !isAnnonceOwner) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D0D18),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: const Color(0xFF2E2E4A),
                  borderRadius: BorderRadius.circular(2))),
          if (isAnnonceOwner && !isReply)
            ListTile(
              leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(
                      ctrl.annonce.pinnedCommentId == comment.id
                          ? Icons.push_pin_outlined
                          : Icons.push_pin_rounded,
                      color: AppColors.accent,
                      size: 18)),
              title: Text(
                  ctrl.annonce.pinnedCommentId == comment.id
                      ? 'Désépingler'
                      : 'Épingler',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                ctrl.epinglerOuDesepingler(comment);
              },
            ),
          ListTile(
            leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.delete_outline_rounded,
                    color: Colors.red, size: 18)),
            title: Text(
                isAnnonceOwner && !isOwn
                    ? 'Supprimer (modération)'
                    : 'Supprimer',
                style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
            onTap: () {
              Navigator.pop(context);
              ctrl.deleteComment(comment);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Commentaire "temp" en cours d'envoi — légèrement transparent
    final isSending = comment.id.startsWith('temp_');
    final double avatarR = isReply ? 14 : 18;

    return Opacity(
      opacity: isSending ? 0.6 : 1.0,
      child: GestureDetector(
        onLongPress: isSending ? null : () => _onLongPress(context),
        child: Padding(
          padding: EdgeInsets.only(
            left: isReply ? 48 : 0,
            top: isReply ? 8 : 10,
            bottom: isReply ? 0 : 4,
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Avatar ──
            GestureDetector(
              onTap: () => _openProfile(context),
              child: CircleAvatar(
                radius: avatarR,
                backgroundColor: const Color(0xFF1E1E30),
                backgroundImage: comment.userPhotoUrl != null
                    ? CachedNetworkImageProvider(comment.userPhotoUrl!)
                    : null,
                child: comment.userPhotoUrl == null
                    ? Icon(
                        comment.isAnonyme
                            ? Icons.person_outline_rounded
                            : Icons.person_rounded,
                        color: const Color(0xFF4A4A70),
                        size: avatarR)
                    : null,
              ),
            ),
            const SizedBox(width: 10),

            // ── Contenu ──
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // Pseudo + temps — inline compact
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    GestureDetector(
                      onTap: () => _openProfile(context),
                      child: Text(
                        comment.isAnonyme ? 'Anonyme' : comment.userName,
                        style: TextStyle(
                          color: comment.isAnonyme
                              ? const Color(0xFF6060A0)
                              : Colors.white,
                          fontSize: isReply ? 12 : 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(_ago(comment.createdAt),
                        style: TextStyle(
                            color: const Color(0xFF4A4A70),
                            fontSize: isReply ? 10 : 11)),
                    if (isPinned) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.push_pin_rounded,
                          size: 10, color: AppColors.accent),
                    ],
                    if (isSending) ...[
                      const SizedBox(width: 6),
                      const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                              color: AppColors.accent, strokeWidth: 1.5)),
                    ],
                  ]),

                  // Texte commentaire
                  const SizedBox(height: 3),
                  Text(comment.texte,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.88),
                        fontSize: isReply ? 13 : 14,
                        height: 1.4,
                      )),

                  // ✅ Actions sous le texte — comme Instagram
                  const SizedBox(height: 6),
                  Row(children: [
                    if (!isReply)
                      GestureDetector(
                        onTap: () =>
                            ctrl.startReply(comment.id, comment.userName),
                        child: const Text('Répondre',
                            style: TextStyle(
                                color: Color(0xFF5050A0),
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                  ]),

                  // Replies
                  if (comment.replies.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ...comment.replies.map((r) => _CommentTile(
                        comment: r,
                        ctrl: ctrl,
                        isReply: true,
                        isPinned: false)),
                  ],
                ])),

            // ── Like à droite ── style TikTok
            const SizedBox(width: 12),
            if (!isSending)
              GestureDetector(
                onTap: () => ctrl.toggleLike(comment),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      comment.isLiked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      key: ValueKey(comment.isLiked),
                      color: comment.isLiked
                          ? const Color(0xFFFF3CAC)
                          : const Color(0xFF4A4A70),
                      size: isReply ? 14 : 16,
                    ),
                  ),
                  if (comment.likes > 0) ...[
                    const SizedBox(height: 2),
                    Text('${comment.likes}',
                        style: TextStyle(
                            color: comment.isLiked
                                ? const Color(0xFFFF3CAC)
                                : const Color(0xFF4A4A70),
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                  ],
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

// ─── VIDEO PREVIEW (commentaires) ────────────────────────────────

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
    if (!_ready)
      return Container(
          height: 180,
          color: Colors.black,
          child: const Center(
              child: CircularProgressIndicator(
                  color: AppColors.accent, strokeWidth: 2)));
    return GestureDetector(
      onTap: () => setState(() {
        _vpc.value.isPlaying ? _vpc.pause() : _vpc.play();
      }),
      child: AspectRatio(
          aspectRatio: _vpc.value.aspectRatio,
          child: Stack(alignment: Alignment.center, children: [
            VideoPlayer(_vpc),
            ValueListenableBuilder(
                valueListenable: _vpc,
                builder: (_, VideoPlayerValue v, __) => AnimatedOpacity(
                    opacity: v.isPlaying ? 0.0 : 0.7,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                            color: Colors.black, shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 28)))),
          ])),
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
      'voyage': '✈️'
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
                                        Color(0xFF3B1F7A)
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
                                              gradient:
                                                  LinearGradient(colors: [AppColors.accent, AppColors.accent2])),
                                          child: Center(child: Text(annonce.userName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22))))))),
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
                              const SizedBox(width: 8),
                              const Icon(Icons.visibility_outlined,
                                  size: 12, color: AppColors.textMuted),
                              const SizedBox(width: 2),
                              Text('${annonce.viewsCount} vues',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted)),
                            ]),
                          ])),
                    ]),
                    const SizedBox(height: 20),
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
                          // ✅ Réactions dans le detail
                          GestureDetector(
                            onTap: () =>
                                controller.toggleReaction(current, '❤️'),
                            child: Row(children: [
                              Text(
                                  current.myReaction.isNotEmpty
                                      ? current.myReaction
                                      : '🤍',
                                  style: const TextStyle(fontSize: 22)),
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
                          const SizedBox(width: 20),
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
        if (isVisible)
          _ctrl.play();
        else
          _ctrl.pause();
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
          child: Stack(alignment: Alignment.bottomRight, children: [
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
                        border:
                            Border.all(color: Colors.white.withOpacity(0.2))),
                    child: Icon(
                        _muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 17))),
            if (_initialized)
              Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8)),
                      child:
                          const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 12),
                        SizedBox(width: 3),
                        Text('Vidéo',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ]))),
          ])),
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
                          gradient: const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Text('⚡ Booster !',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.white))),
                ),
              ],
            ));
  }
}

// ─── BOOST PROFIL ────────────────────────────────────────────────

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
                        gradient: const LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
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
                    if (!Get.isRegistered<AnnoncesController>())
                      Get.put(AnnoncesController());
                    await Get.find<AnnoncesController>().boosterProfil();
                  },
                  child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                                color: const Color(0xFFFFD700).withOpacity(0.4),
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
                          ])),
                ),
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

// ─── HELPERS ─────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  final bool active;
  final IconData icon;
  final Color activeColor;
  final String label;
  final String sub;
  final VoidCallback onTap;
  final bool? toggleActive;
  const _ToggleRow(
      {required this.active,
      required this.icon,
      required this.activeColor,
      required this.label,
      required this.sub,
      required this.onTap,
      this.toggleActive});

  @override
  Widget build(BuildContext context) {
    final effectiveToggle = toggleActive ?? active;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: active ? activeColor.withOpacity(0.12) : AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? activeColor : AppColors.border),
        ),
        child: Row(children: [
          Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color:
                      active ? activeColor.withOpacity(0.2) : AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: active ? activeColor : AppColors.border)),
              child: Icon(icon,
                  size: 18, color: active ? activeColor : AppColors.textMuted)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: active ? activeColor : AppColors.textPrimary)),
                Text(sub,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
              ])),
          AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 24,
              decoration: BoxDecoration(
                  color: effectiveToggle ? activeColor : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: effectiveToggle ? activeColor : AppColors.border)),
              child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  alignment: effectiveToggle
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                      margin: const EdgeInsets.all(2),
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle)))),
        ]),
      ),
    );
  }
}

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
