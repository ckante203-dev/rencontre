import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/profil/vue/qr_zamu.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Partage de mon profil en image (statut WhatsApp, story Instagram…) :
/// photo, prénom, @pseudo et QR code vers Zamu.
Future<void> partagerCarteProfil({
  required String nom,
  required String pseudo,
  String? photoUrl,
}) async {
  final cle = GlobalKey();
  final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
  await Get.dialog(
    Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        RepaintBoundary(
          key: cle,
          child: _Carte(nom: nom, pseudo: pseudo, photoUrl: photoUrl, uid: uid),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.share_rounded, color: AppColors.surAccent),
            label: Text('Partager l\'image'.tr,
                style: const TextStyle(
                    color: AppColors.surAccent, fontWeight: FontWeight.w700)),
            onPressed: () => _capturerEtPartager(cle, pseudo),
          ),
        ),
      ]),
    ),
  );
}

Future<void> _capturerEtPartager(GlobalKey cle, String pseudo) async {
  try {
    final boundary =
        cle.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final octets = await image.toByteData(format: ui.ImageByteFormat.png);
    final dossier = await getTemporaryDirectory();
    final fichier = File('${dossier.path}/zamu_profil.png');
    await fichier.writeAsBytes(octets!.buffer.asUint8List());
    await SharePlus.instance.share(ShareParams(
      files: [XFile(fichier.path)],
      text: 'Retrouve-moi sur Zamu 💬 : @@pseudo\nCherche mon pseudo dans Messages 🔍\nhttps://play.google.com/store/apps/details?id=com.vybestyle.zamu'
          .trParams({'pseudo': pseudo}),
    ));
  } catch (e) {
    debugPrint('Partage de la carte impossible : $e');
  }
}

class _Carte extends StatelessWidget {
  final String nom;
  final String pseudo;
  final String? photoUrl;
  final String uid;
  const _Carte(
      {required this.nom,
      required this.pseudo,
      required this.photoUrl,
      required this.uid});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1450), Color(0xFF8C46F0), Color(0xFFD94BC8)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(
          radius: 52,
          backgroundColor: Colors.white24,
          backgroundImage: (photoUrl ?? '').isNotEmpty
              ? CachedNetworkImageProvider(photoUrl!)
              : null,
          child: (photoUrl ?? '').isEmpty
              ? Text(nom.isNotEmpty ? nom[0].toUpperCase() : '?',
                  style: const TextStyle(
                      fontSize: 40,
                      color: Colors.white,
                      fontWeight: FontWeight.w800))
              : null,
        ),
        const SizedBox(height: 12),
        Text(nom,
            style: const TextStyle(
                fontFamily: 'Syne',
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.white)),
        if (pseudo.isNotEmpty)
          Text('@$pseudo',
              style: const TextStyle(fontSize: 15, color: Colors.white70)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: QrImageView(data: lienQrZamu(uid), size: 130),
        ),
        const SizedBox(height: 14),
        Text('Retrouve-moi sur Zamu'.tr,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
        const SizedBox(height: 2),
        Text('Gratuit sur Google Play'.tr,
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ]),
    );
  }
}
