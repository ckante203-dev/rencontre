import 'package:flutter/material.dart';

/// Badge Premium (médaille dorée) affiché à côté du nom des abonnés.
/// Pas de coche : une coche laisserait croire à un profil vérifié.
class PremiumBadge extends StatelessWidget {
  final double size;
  const PremiumBadge({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.workspace_premium_rounded,
      size: size * 1.15,
      color: const Color(0xFFFFC233),
    );
  }
}
