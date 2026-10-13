import 'package:flutter/services.dart';
import 'package:rencontre/core/services/ouvrir_profil.dart';

/// Liens de profil partageables :
/// https://supportsnapmeet-jpg.github.io/zamu-legal/p.html?u=<id>
/// La page ouvre zamu://profil/<id> (ou le Play Store si Zamu n'est pas
/// installée) ; l'app reçoit ce lien ici et ouvre le profil.
class LiensProfil {
  LiensProfil._();
  static const _canal = MethodChannel('zamu/liens');
  static const pageWeb =
      'https://supportsnapmeet-jpg.github.io/zamu-legal/p.html';
  static bool _ecoute = false;

  static String lien(String uid) => '$pageWeb?u=$uid';

  static final _id = RegExp(
      r'^zamu://profil/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})');

  static void _ouvrir(String? url) {
    final id = _id.firstMatch(url ?? '')?.group(1)?.toLowerCase();
    if (id != null) ouvrirProfilParId(id);
  }

  /// À appeler une fois l'écran principal affiché.
  static Future<void> demarrer() async {
    if (!_ecoute) {
      _ecoute = true;
      _canal.setMethodCallHandler((appel) async {
        if (appel.method == 'lien') _ouvrir(appel.arguments as String?);
      });
    }
    try {
      _ouvrir(await _canal.invokeMethod<String>('initial'));
    } catch (_) {}
  }
}
