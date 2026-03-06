import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/annonces/controller/annonces_controller.dart';
import 'package:rencontre/features/annonces/model/annonce_model.dart';

// ─── ECRAN ANNONCES ───────────────────────────────────────────────

class AnnoncesScreen extends StatelessWidget {
  const AnnoncesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<AnnoncesController>()) Get.put(AnnoncesController());
    return const _AnnoncesView();
  }
}

class _AnnoncesView extends GetView<AnnoncesController> {
  const _AnnoncesView();

  String _catLabel(String cat) {
    const m = {
      'toutes': '🔥 Toutes', 'rencontre': '💕 Rencontre',
      'amitie': '🤝 Amitié', 'sortie': '🎉 Sortie', 'voyage': '✈️ Voyage'
    };
    return m[cat] ?? cat;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(child: Column(children: [
        // ── Header ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(children: [
            ShaderMask(
              shaderCallback: (b) => AppColors.gradientPink.createShader(b),
              child: const Text('Annonces', style: TextStyle(
                fontFamily: 'Syne', fontSize: 26,
                fontWeight: FontWeight.w900, color: Colors.white))),
            const Spacer(),
            GestureDetector(
              onTap: () => _showPublierSheet(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: AppColors.gradientPink,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.3), blurRadius: 12)]),
                child: const Row(children: [
                  Icon(Icons.add_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text('Publier', style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w800, color: Colors.white)),
                ]))),
          ])),
        const SizedBox(height: 16),

        // ── Filtres ──
        SizedBox(height: 36,
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: sel ? AppColors.gradientPink : null,
                      color: sel ? null : AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel ? Colors.transparent : AppColors.border)),
                    child: Text(_catLabel(cat), style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: sel ? Colors.white : AppColors.textMuted))));
              });
          })),
        const SizedBox(height: 12),

        // ── Liste ──
        Expanded(child: Obx(() {
          if (controller.isLoading.value) return const Center(
            child: CircularProgressIndicator(color: AppColors.accent));
          final list = controller.filtered;
          if (list.isEmpty) return Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center, children: [
              ShaderMask(
                shaderCallback: (b) => AppColors.gradientPink.createShader(b),
                child: const Icon(Icons.campaign_rounded,
                  size: 64, color: Colors.white)),
              const SizedBox(height: 16),
              const Text('Aucune annonce', style: TextStyle(fontSize: 18,
                fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              const Text('Sois le premier à publier !',
                style: TextStyle(color: AppColors.textMuted)),
            ]));
          return RefreshIndicator(
            color: AppColors.accent, backgroundColor: AppColors.surface,
            onRefresh: controller.loadAnnonces,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: list.length,
              itemBuilder: (_, i) => _AnnonceCard(annonce: list[i])));
        })),
      ])),
    );
  }

  // ── Sheet Publication ──────────────────────────────────────────
  void _showPublierSheet(BuildContext context) {
    final titreCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final villeCtrl = TextEditingController();
    String cat = 'rencontre';
    bool loading = false;
    bool anonyme = false;
    XFile? mediaFile;
    bool isVideo = false;

    String cl(String c) {
      const m = {'rencontre': '💕 Rencontre', 'amitie': '🤝 Amitié',
        'sortie': '🎉 Sortie', 'voyage': '✈️ Voyage'};
      return m[c] ?? c;
    }

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: AppColors.border)),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Poignée
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),

              ShaderMask(
                shaderCallback: (b) => AppColors.gradientPink.createShader(b),
                child: const Text('Nouvelle annonce', style: TextStyle(
                  fontFamily: 'Syne', fontSize: 20,
                  fontWeight: FontWeight.w900, color: Colors.white))),
              const SizedBox(height: 20),

              // ── Catégories ──
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['rencontre', 'amitie', 'sortie', 'voyage'].map<Widget>((c) =>
                    GestureDetector(
                      onTap: () => setS(() => cat = c),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          gradient: cat == c ? AppColors.gradientPink : null,
                          color: cat == c ? null : AppColors.surface2,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: cat == c
                            ? Colors.transparent : AppColors.border)),
                        child: Text(cl(c), style: TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cat == c ? Colors.white : AppColors.textMuted)),
                      ),
                    ),
                  ).toList(),
                ),
              ),
              const SizedBox(height: 16),

              // ── Champs texte ──
              _Field(controller: titreCtrl, hint: 'Titre de ton annonce', maxLines: 1),
              const SizedBox(height: 12),
              _Field(controller: descCtrl, hint: 'Décris ce que tu recherches...', maxLines: 4),
              const SizedBox(height: 12),
              _Field(controller: villeCtrl, hint: 'Ville (optionnel)', maxLines: 1),
              const SizedBox(height: 16),

              // ── Media (Photo / Vidéo) ──
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final picker = ImagePicker();
                      final f = await picker.pickImage(
                        source: ImageSource.gallery, imageQuality: 80);
                      if (f != null) setS(() { mediaFile = f; isVideo = false; });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: mediaFile != null && !isVideo
                          ? AppColors.accent.withValues(alpha: 0.15) : AppColors.surface2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: mediaFile != null && !isVideo
                            ? AppColors.accent : AppColors.border)),
                      child: Column(children: [
                        Icon(Icons.photo_outlined,
                          color: mediaFile != null && !isVideo
                            ? AppColors.accent : AppColors.textMuted, size: 22),
                        const SizedBox(height: 4),
                        Text('Photo', style: TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: mediaFile != null && !isVideo
                            ? AppColors.accent : AppColors.textMuted)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final picker = ImagePicker();
                      final f = await picker.pickVideo(source: ImageSource.gallery);
                      if (f != null) setS(() { mediaFile = f; isVideo = true; });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: mediaFile != null && isVideo
                          ? AppColors.accent.withValues(alpha: 0.15) : AppColors.surface2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: mediaFile != null && isVideo
                            ? AppColors.accent : AppColors.border)),
                      child: Column(children: [
                        Icon(Icons.videocam_outlined,
                          color: mediaFile != null && isVideo
                            ? AppColors.accent : AppColors.textMuted, size: 22),
                        const SizedBox(height: 4),
                        Text('Vidéo', style: TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: mediaFile != null && isVideo
                            ? AppColors.accent : AppColors.textMuted)),
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
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.3))),
                      child: const Icon(Icons.close_rounded, color: Colors.red, size: 20)),
                  ),
                ],
              ]),

              // Aperçu photo
              if (mediaFile != null && !isVideo) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(File(mediaFile!.path),
                    height: 160, width: double.infinity, fit: BoxFit.cover)),
              ],
              // Aperçu vidéo
              if (mediaFile != null && isVideo) ...[
                const SizedBox(height: 12),
                Container(
                  height: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.4))),
                  child: Row(children: [
                    const Icon(Icons.videocam_rounded, color: AppColors.accent, size: 26),
                    const SizedBox(width: 12),
                    Expanded(child: Text(mediaFile!.name,
                      style: const TextStyle(color: AppColors.textPrimary,
                        fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis)),
                  ])),
              ],
              const SizedBox(height: 16),

              // ── Mode Anonyme ──
              GestureDetector(
                onTap: () => setS(() => anonyme = !anonyme),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: anonyme
                      ? const Color(0xFF6C3FC5).withValues(alpha: 0.12) : AppColors.surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: anonyme ? const Color(0xFF6C3FC5) : AppColors.border)),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: anonyme
                          ? const Color(0xFF6C3FC5).withValues(alpha: 0.2) : AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: anonyme ? const Color(0xFF6C3FC5) : AppColors.border)),
                      child: Icon(Icons.visibility_off_rounded, size: 18,
                        color: anonyme ? const Color(0xFF6C3FC5) : AppColors.textMuted)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Publier en anonyme', style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: anonyme ? const Color(0xFF6C3FC5) : AppColors.textPrimary)),
                      const Text('Ton nom et photo seront masqués',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ])),
                    // Toggle switch
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 44, height: 24,
                      decoration: BoxDecoration(
                        color: anonyme ? const Color(0xFF6C3FC5) : AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: anonyme ? const Color(0xFF6C3FC5) : AppColors.border)),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 200),
                        alignment: anonyme ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          width: 20, height: 20,
                          decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle)))),
                  ])),
              ),
              const SizedBox(height: 20),

              // ── Bouton Publier ──
              GestureDetector(
                onTap: loading ? null : () async {
                  if (titreCtrl.text.trim().isEmpty || descCtrl.text.trim().isEmpty) {
                    Get.snackbar('Champs requis', 'Remplis le titre et la description',
                      snackPosition: SnackPosition.TOP,
                      backgroundColor: Colors.red.shade900, colorText: Colors.white);
                    return;
                  }
                  setS(() => loading = true);
                  final ok = await controller.publierAnnonce(
                    titre: titreCtrl.text.trim(),
                    description: descCtrl.text.trim(),
                    categorie: cat,
                    ville: villeCtrl.text.trim().isEmpty ? null : villeCtrl.text.trim(),
                    anonyme: anonyme,
                    mediaFile: mediaFile,
                    isVideo: isVideo,
                  );
                  setS(() => loading = false);
                  if (ok) {
                    Navigator.pop(ctx);
                    Get.snackbar('Annonce publiée ✅', '',
                      snackPosition: SnackPosition.TOP,
                      backgroundColor: AppColors.surface, colorText: Colors.white);
                  }
                },
                child: Container(width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientPink,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.3), blurRadius: 16)]),
                  child: loading
                    ? const Center(child: SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5)))
                    : const Text('Publier mon annonce', textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16,
                          fontWeight: FontWeight.w800, color: Colors.white)))),
            ]),
          ),
        ),
      )),
    );
  }
}

// ─── CARTE ANNONCE ────────────────────────────────────────────────

class _AnnonceCard extends GetView<AnnoncesController> {
  final AnnonceModel annonce;
  const _AnnonceCard({required this.annonce});

  String get _emoji {
    const m = {'rencontre': '💕', 'amitie': '🤝', 'sortie': '🎉', 'voyage': '✈️'};
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
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: annonce.isBoosted
            ? AppColors.accent.withValues(alpha: 0.5) : AppColors.border,
          width: annonce.isBoosted ? 1.5 : 1),
        boxShadow: annonce.isBoosted ? [BoxShadow(
          color: AppColors.accent.withValues(alpha: 0.1), blurRadius: 16)] : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header ──
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(children: [
            // Avatar anonyme ou réel
            Container(width: 44, height: 44,
              decoration: BoxDecoration(shape: BoxShape.circle,
                border: Border.all(
                  color: annonce.isAnonyme
                    ? const Color(0xFF6C3FC5).withValues(alpha: 0.5)
                    : AppColors.accent.withValues(alpha: 0.4), width: 1.5)),
              child: ClipOval(
                child: annonce.isAnonyme
                  ? Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF6C3FC5), Color(0xFF3B1F7A)])),
                      child: const Center(child: Icon(Icons.person_outline_rounded,
                        color: Colors.white, size: 24)))
                  : (annonce.userPhotoUrl != null
                    ? CachedNetworkImage(imageUrl: annonce.userPhotoUrl!, fit: BoxFit.cover)
                    : Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.accent, AppColors.accent2])),
                        child: Center(child: Text(annonce.userName[0].toUpperCase(),
                          style: const TextStyle(color: Colors.white,
                            fontWeight: FontWeight.w800))))))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (annonce.isAnonyme)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C3FC5).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF6C3FC5).withValues(alpha: 0.4))),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.visibility_off_rounded,
                        size: 10, color: Color(0xFF6C3FC5)),
                      SizedBox(width: 3),
                      Text('Anonyme', style: TextStyle(fontSize: 9,
                        fontWeight: FontWeight.w700, color: Color(0xFF6C3FC5))),
                    ])),
                Flexible(child: Text(
                  annonce.isAnonyme ? 'Utilisateur anonyme' : annonce.userName,
                  style: const TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis)),
                if (!annonce.isAnonyme) ...[
                  const SizedBox(width: 6),
                  Text('${annonce.userAge} ans',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              ]),
              Row(children: [
                if (annonce.ville != null && !annonce.isAnonyme) ...[
                  const Icon(Icons.location_on_rounded, size: 11, color: AppColors.textMuted),
                  Text(annonce.ville!, style: const TextStyle(
                    fontSize: 11, color: AppColors.textMuted)),
                  const SizedBox(width: 8),
                ],
                Text(_ago, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ]),
            ])),
            if (annonce.isBoosted)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
                  borderRadius: BorderRadius.circular(10)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.bolt_rounded, size: 11, color: Colors.white),
                  SizedBox(width: 2),
                  Text('BOOST', style: TextStyle(fontSize: 8,
                    fontWeight: FontWeight.w900, color: Colors.white)),
                ])),
            GestureDetector(
              onTap: () => _menu(context),
              child: const Icon(Icons.more_vert_rounded,
                color: AppColors.textMuted, size: 20)),
          ])),

        // ── Titre + catégorie ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.surface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border)),
              child: Text('$_emoji ${annonce.categorie}', style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted))),
            const SizedBox(width: 10),
            Expanded(child: Text(annonce.titre, style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
          ])),
        const SizedBox(height: 8),

        // ── Description ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(annonce.description, style: const TextStyle(
            fontSize: 13, color: AppColors.textMuted, height: 1.5),
            maxLines: 3, overflow: TextOverflow.ellipsis)),
        const SizedBox(height: 10),

        // ── Media ──
        if (annonce.mediaUrl != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: annonce.isVideo
              ? Container(
                  height: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.3))),
                  child: const Row(children: [
                    Icon(Icons.play_circle_outline_rounded,
                      color: AppColors.accent, size: 30),
                    SizedBox(width: 10),
                    Text('Voir la vidéo', style: TextStyle(
                      color: AppColors.accent, fontWeight: FontWeight.w600)),
                  ]))
              : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: annonce.mediaUrl!,
                    height: 200, width: double.infinity, fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      height: 200, color: AppColors.surface2,
                      child: const Center(
                        child: CircularProgressIndicator(color: AppColors.accent))),
                    errorWidget: (_, __, ___) => const SizedBox.shrink()))),
          const SizedBox(height: 10),
        ],

        // ── Actions ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: AppColors.surface2,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20))),
          child: Row(children: [
            // ❤️ Like
            GestureDetector(
              onTap: () => controller.toggleLike(annonce),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Row(
                  key: ValueKey(annonce.isLiked),
                  children: [
                    Icon(
                      annonce.isLiked
                        ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                      color: annonce.isLiked ? Colors.red : AppColors.textMuted,
                      size: 22),
                    const SizedBox(width: 5),
                    Text('${annonce.likes}', style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: annonce.isLiked ? Colors.red : AppColors.textMuted)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
            // 💬 Répondre
            GestureDetector(
              onTap: () => annonce.isAnonyme
                ? _repondreAnonyme(context) : _repondre(context),
              child: const Row(children: [
                Icon(Icons.chat_bubble_outline_rounded,
                  color: AppColors.textMuted, size: 18),
                SizedBox(width: 5),
                Text('Répondre', style: TextStyle(fontSize: 13,
                  color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              ])),
            const Spacer(),
            _BoostButton(annonce: annonce),
          ])),
      ]));
  }

  void _repondre(BuildContext context) {
    final msgCtrl = TextEditingController();
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppColors.border)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.border,
                borderRadius: BorderRadius.circular(2))),
            Text('Répondre à ${annonce.userName}',
              style: const TextStyle(fontFamily: 'Syne', fontSize: 17,
                fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            _Field(controller: msgCtrl, hint: 'Ton message...', maxLines: 3),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () async {
                final msg = msgCtrl.text.trim();
                if (msg.isEmpty) return;
                Navigator.pop(ctx);
                try {
                  final sb = Supabase.instance.client;
                  final myId = sb.auth.currentUser!.id;
                  final existing = await sb.from('conversations').select('id')
                    .or('and(user1_id.eq.$myId,user2_id.eq.${annonce.userId}),'
                        'and(user1_id.eq.${annonce.userId},user2_id.eq.$myId)')
                    .maybeSingle();
                  String convId;
                  if (existing != null) {
                    convId = existing['id'];
                  } else {
                    final c = await sb.from('conversations')
                      .insert({'user1_id': myId, 'user2_id': annonce.userId})
                      .select('id').single();
                    convId = c['id'];
                  }
                  await sb.from('messages').insert({
                    'conversation_id': convId,
                    'sender_id': myId,
                    'text': '📢 "${annonce.titre}" : $msg',
                  });
                  Get.snackbar('Message envoyé ✅', '',
                    snackPosition: SnackPosition.TOP,
                    backgroundColor: AppColors.surface, colorText: Colors.white);
                } catch (e) { debugPrint('reply error: $e'); }
              },
              child: Container(width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  gradient: AppColors.gradientPink,
                  borderRadius: BorderRadius.circular(16)),
                child: const Text('Envoyer', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w800, color: Colors.white)))),
          ]))));
  }

  void _repondreAnonyme(BuildContext context) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.border)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppColors.border,
              borderRadius: BorderRadius.circular(2))),
          const Icon(Icons.visibility_off_rounded,
            color: Color(0xFF6C3FC5), size: 44),
          const SizedBox(height: 12),
          const Text('Annonce anonyme', style: TextStyle(fontFamily: 'Syne',
            fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          const Text(
            'Cette annonce a été publiée de façon anonyme.\nTu ne peux pas contacter directement cet utilisateur.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5)),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border)),
              child: const Text('Fermer', textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted,
                  fontSize: 14, fontWeight: FontWeight.w600)))),
        ])));
  }

  void _menu(BuildContext context) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.border)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppColors.border,
              borderRadius: BorderRadius.circular(2))),
          if (myId == annonce.userId) ...[
            _MenuItem(Icons.delete_outline_rounded, 'Supprimer', Colors.red, () {
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
        ])));
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
          border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.4))),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bolt_rounded, size: 13, color: Color(0xFFFFD700)),
          SizedBox(width: 3),
          Text('Boostée', style: TextStyle(fontSize: 11,
            color: Color(0xFFFFD700), fontWeight: FontWeight.w700)),
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
          boxShadow: [BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.3), blurRadius: 8)]),
        child: controller.isBoosting.value
          ? const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bolt_rounded, size: 13, color: Colors.white),
              SizedBox(width: 3),
              Text('Booster', style: TextStyle(fontSize: 11,
                fontWeight: FontWeight.w800, color: Colors.white)),
            ]))));
  }

  void _confirm(BuildContext context) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.bolt_rounded, color: Color(0xFFFFD700), size: 22),
        SizedBox(width: 8),
        Text('Booster l\u2019annonce', style: TextStyle(fontFamily: 'Syne',
          fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
      ]),
      content: const Text(
        'Ton annonce apparaîtra en tête de liste pendant 24h.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('Annuler',
            style: TextStyle(color: AppColors.textMuted))),
        GestureDetector(
          onTap: () { Navigator.pop(context); controller.boosterAnnonce(annonce); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
              borderRadius: BorderRadius.circular(10)),
            child: const Text('⚡ Booster !',
              style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)))),
      ]));
  }
}

// ─── BOOST PROFIL ─────────────────────────────────────────────────

class BoostProfilWidget extends StatelessWidget {
  const BoostProfilWidget({super.key});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => _sheet(context),
    child: Container(
      width: 46, height: 46,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(
          color: const Color(0xFFFFD700).withValues(alpha: 0.4),
          blurRadius: 12)]),
      child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 22)));

  void _sheet(BuildContext context) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: AppColors.border)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: AppColors.border,
              borderRadius: BorderRadius.circular(2))),
          Container(width: 80, height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                blurRadius: 20)]),
            child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 42)),
          const SizedBox(height: 20),
          const Text('Booster ton profil', style: TextStyle(fontFamily: 'Syne',
            fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          const Text('Apparais en premier dans la liste\npendant 30 minutes',
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
              if (!Get.isRegistered<AnnoncesController>()) Get.put(AnnoncesController());
              await Get.find<AnnoncesController>().boosterProfil();
            },
            child: Container(width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                  blurRadius: 16)]),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
                SizedBox(width: 8),
                Text('⚡ Activer le Boost — Gratuit', style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
              ]))),
          const SizedBox(height: 10),
          const Text('Bientôt : Boost Premium 30min / 24h / 7j',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ])));
  }
}

class _Feat extends StatelessWidget {
  final String emoji, text;
  const _Feat(this.emoji, this.text);
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 36, height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10)),
      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 18)))),
    const SizedBox(width: 12),
    Text(text, style: const TextStyle(fontSize: 14,
      color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
  ]);
}

// ─── HELPERS ──────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  const _Field({required this.controller, required this.hint, required this.maxLines});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: AppColors.surface2,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border)),
    child: TextField(controller: controller, maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12))));
}

class _MenuItem extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _MenuItem(this.icon, this.label, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(children: [
        Icon(icon, color: color, size: 20), const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color,
          fontSize: 15, fontWeight: FontWeight.w600)),
      ])));
}