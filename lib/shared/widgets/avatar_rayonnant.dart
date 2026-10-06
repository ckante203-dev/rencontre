import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:rencontre/core/theme/app_theme.dart';

// Ta photo de profil qui « rayonne » : ondes or / orange qui partent de
// l'avatar. Utilisée par la fenêtre Boost et la page Premium.

// ─── Ta photo qui rayonne : ondes orange qui partent de l'avatar ──
class AvatarRayonnant extends StatefulWidget {
  final String? photoUrl;
  final bool actif; // ondes plus nombreuses et plus rapides
  final IconData icone; // ⚡ Boost, 👑 Premium
  const AvatarRayonnant(
      {super.key,
      required this.photoUrl,
      this.actif = false,
      this.icone = Icons.bolt_rounded});
  @override
  State<AvatarRayonnant> createState() => AvatarRayonnantState();
}

class AvatarRayonnantState extends State<AvatarRayonnant>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: _duree)..repeat();

  Duration get _duree => Duration(milliseconds: widget.actif ? 1600 : 2600);

  @override
  void didUpdateWidget(covariant AvatarRayonnant old) {
    super.didUpdateWidget(old);
    if (old.actif != widget.actif) {
      _anim
        ..duration = _duree
        ..repeat();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const taille = 140.0;
    const photo = 76.0;
    final url = widget.photoUrl;
    return SizedBox(
      width: taille,
      height: taille,
      child: Stack(alignment: Alignment.center, children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: _Ondes(_anim, intense: widget.actif)),
          ),
        ),
        // Photo avec contour dégradé or → orange
        Container(
          width: photo + 6,
          height: photo + 6,
          padding: const EdgeInsets.all(3),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [BoxShadow(color: Color(0x66FFA500), blurRadius: 18)],
          ),
          child: ClipOval(
            child: url != null && url.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _vide(),
                  )
                : _vide(),
          ),
        ),
        // Petit éclair sur la photo
        Positioned(
          right: (taille - photo) / 2 - 4,
          bottom: (taille - photo) / 2 - 2,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFA500),
              border: Border.all(color: AppColors.bg, width: 2),
            ),
            child: Icon(widget.icone, color: AppColors.surAccent, size: 16),
          ),
        ),
      ]),
    );
  }

  Widget _vide() => Container(
        color: AppColors.surface2,
        child: Icon(Icons.person, color: AppColors.textMuted.withValues(alpha: 0.54), size: 36),
      );
}

class _Ondes extends CustomPainter {
  final Animation<double> anim;
  final bool intense;
  _Ondes(this.anim, {required this.intense}) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    const rMin = 40.0;
    final rMax = size.width / 2;
    final nb = intense ? 3 : 2;
    for (var i = 0; i < nb; i++) {
      final v = (anim.value + i / nb) % 1.0;
      final r = rMin + (rMax - rMin) * Curves.easeOut.transform(v);
      final opacite = (1 - v) * (intense ? 0.55 : 0.4);
      canvas.drawCircle(
          centre,
          r,
          Paint()
            ..color = const Color(0xFFFFA500).withValues(alpha: opacite * 0.35)
            ..style = PaintingStyle.fill);
      canvas.drawCircle(
          centre,
          r,
          Paint()
            ..color = const Color(0xFFFFC233).withValues(alpha: opacite)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant _Ondes old) => old.intense != intense;
}
