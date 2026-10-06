import 'package:flutter/material.dart';

/// Badge « Profil vérifié » (selfie validé par l'équipe Zamu).
/// Bleu fixe : lisible sur les photos comme sur tous les thèmes.
class BadgeVerifie extends StatelessWidget {
  final double size;
  const BadgeVerifie({super.key, this.size = 16});

  static const bleu = Color(0xFF1D9BF0);

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.verified_rounded, size: size, color: bleu);
  }
}
