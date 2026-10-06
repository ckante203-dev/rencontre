import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:rencontre/core/services/ouvrir_profil.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';

// ─── QR CODE ZAMU (façon Snapcode) ────────────────────────────────
// Le QR contient un lien Play Store avec l'id du profil en « referrer » :
// • scanné dans Zamu → ouvre directement le profil ;
// • scanné avec l'appareil photo du téléphone → ouvre Zamu sur le
//   Play Store (la personne qui ne l'a pas encore peut l'installer).

String lienQrZamu(String uid) =>
    'https://play.google.com/store/apps/details?id=com.vybestyle.zamu'
    '&referrer=zamu_u%3D$uid';

final _idDansQr = RegExp(
    r'zamu_u(?:=|%3D)([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})');

/// Id du profil contenu dans un QR Zamu, ou null.
String? idProfilDepuisQr(String contenu) =>
    _idDansQr.firstMatch(contenu)?.group(1)?.toLowerCase();

/// Mon QR code + bouton pour scanner celui d'un ami.
class FeuilleQrZamu extends StatelessWidget {
  final ControleurProfil ctrl;
  const FeuilleQrZamu({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final uid = ctrl.monProfil.value?.id ?? '';
    final pseudo = ctrl.monUsername.value;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: uid.isEmpty
                  ? const SizedBox(
                      width: 200,
                      height: 200,
                      child: Center(child: CircularProgressIndicator()))
                  : QrImageView(
                      data: lienQrZamu(uid),
                      size: 200,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.circle, color: Colors.black),
                      dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.circle,
                          color: Colors.black),
                    ),
            ),
            const SizedBox(height: 14),
            Text(
                pseudo.isEmpty
                    ? (ctrl.monProfil.value?.name ?? '')
                    : '@$pseudo',
                style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text('Fais scanner ce code à tes amis pour qu\'ils te trouvent',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                Get.back();
                Get.to(() => const EcranScanQr());
              },
              child: Container(
                width: double.infinity,
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppColors.gradientPink,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_scanner_rounded,
                        color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('Scanner le code d\'un ami',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Scanner : lit un QR Zamu et ouvre le profil.
class EcranScanQr extends StatefulWidget {
  const EcranScanQr({super.key});

  @override
  State<EcranScanQr> createState() => _EcranScanQrState();
}

class _EcranScanQrState extends State<EcranScanQr> {
  final MobileScannerController _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _traite = false;
  String? _dernierRefus;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_traite) return;
    for (final b in capture.barcodes) {
      final brut = b.rawValue;
      if (brut == null) continue;
      final id = idProfilDepuisQr(brut);
      if (id == null) {
        if (_dernierRefus != brut) {
          _dernierRefus = brut;
          Get.snackbar('Pas un code Zamu', 'Scanne le QR code Zamu d\'un ami',
              snackPosition: SnackPosition.TOP,
              backgroundColor: AppColors.surface,
              colorText: AppColors.textPrimary);
        }
        continue;
      }
      _traite = true;
      await _scanner.stop();
      Get.back();
      await ouvrirProfilParId(id);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        MobileScanner(
          controller: _scanner,
          onDetect: _onDetect,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? 'Autorise l\'appareil photo pour scanner un code'
                    : 'Appareil photo indisponible',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ),
          ),
        ),
        // Cadre de visée
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              IconButton(
                onPressed: Get.back,
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 28),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => _scanner.toggleTorch(),
                icon: const Icon(Icons.flash_on_rounded,
                    color: Colors.white, size: 26),
              ),
            ]),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 80,
          child: Text('Vise le QR code Zamu de ton ami',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}
