import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';

/// Photos en plein écran : glisser ou toucher gauche / droite pour changer,
/// compteur en haut, glisser vers le bas pour fermer.
void ouvrirGaleriePhotos(List<String> urls, {int depart = 0}) {
  if (urls.isEmpty) return;
  Get.to(() => _GaleriePhotos(urls: urls, depart: depart.clamp(0, urls.length - 1)),
      fullscreenDialog: true, transition: Transition.fadeIn);
}

class _GaleriePhotos extends StatefulWidget {
  final List<String> urls;
  final int depart;
  const _GaleriePhotos({required this.urls, required this.depart});
  @override
  State<_GaleriePhotos> createState() => _GaleriePhotosState();
}

class _GaleriePhotosState extends State<_GaleriePhotos> {
  late final PageController _pages = PageController(initialPage: widget.depart);
  late int _index = widget.depart;
  double _dy = 0;

  void _aller(int i) {
    if (i < 0 || i >= widget.urls.length) return;
    _pages.animateToPage(i,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.urls.length;
    final fond = (1 - _dy.abs() / 500).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: fond),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.surMedia,
        title: n > 1
            ? Text('${_index + 1} / $n',
                style: const TextStyle(
                    color: AppColors.surMedia, fontWeight: FontWeight.w700))
            : null,
      ),
      body: GestureDetector(
        onVerticalDragUpdate: (d) => setState(() => _dy += d.delta.dy),
        onVerticalDragEnd: (d) {
          if (_dy.abs() > 120 || (d.primaryVelocity ?? 0).abs() > 900) {
            Get.back();
          } else {
            setState(() => _dy = 0);
          }
        },
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          if (d.localPosition.dx < w * 0.3) _aller(_index - 1);
          if (d.localPosition.dx > w * 0.7) _aller(_index + 1);
        },
        child: Transform.translate(
          offset: Offset(0, _dy),
          child: PageView.builder(
            controller: _pages,
            itemCount: n,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => Center(
              child: CachedNetworkImage(
                imageUrl: widget.urls[i],
                fit: BoxFit.contain,
                memCacheWidth: 1440,
                placeholder: (_, __) =>
                    const CircularProgressIndicator(color: AppColors.surMedia),
                errorWidget: (_, __, ___) => const Icon(
                    Icons.broken_image_rounded,
                    color: Color(0x61FFFFFF),
                    size: 48),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
