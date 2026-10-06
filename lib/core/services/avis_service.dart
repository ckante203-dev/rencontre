import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';
import 'package:in_app_review/in_app_review.dart';

/// Demande de note sur le Play Store, seulement après un moment positif
/// (match, conversation qui prend) et jamais trop souvent :
/// • app utilisée depuis au moins 3 jours ;
/// • au plus une demande tous les 90 jours, 3 en tout.
/// Google décide ensuite d'afficher ou non la fenêtre (quota de son côté).
class AvisService {
  static final _box = GetStorage();
  static const _clePremier = 'avis_premier_lancement';
  static const _cleDerniere = 'avis_derniere_demande';
  static const _cleNombre = 'avis_nombre_demandes';
  static const _cleMessages = 'avis_messages_envoyes';

  /// À appeler au démarrage : retient la date du premier lancement.
  static void noterLancement() {
    try {
      if (_box.read<int>(_clePremier) == null) {
        _box.write(_clePremier, DateTime.now().millisecondsSinceEpoch);
      }
    } catch (_) {}
  }

  /// Un message texte envoyé : au 15e, c'est un bon moment.
  static void messageEnvoye() {
    try {
      final n = (_box.read<int>(_cleMessages) ?? 0) + 1;
      _box.write(_cleMessages, n);
      if (n == 15 || n == 60) momentPositif();
    } catch (_) {}
  }

  /// Après un match, une conversation qui marche…
  static Future<void> momentPositif() async {
    try {
      final maintenant = DateTime.now().millisecondsSinceEpoch;
      final premier = _box.read<int>(_clePremier) ?? maintenant;
      final derniere = _box.read<int>(_cleDerniere) ?? 0;
      final nombre = _box.read<int>(_cleNombre) ?? 0;
      const jour = 24 * 3600 * 1000;
      if (maintenant - premier < 3 * jour) return;
      if (maintenant - derniere < 90 * jour) return;
      if (nombre >= 3) return;

      final avis = InAppReview.instance;
      if (!await avis.isAvailable()) return;
      _box.write(_cleDerniere, maintenant);
      _box.write(_cleNombre, nombre + 1);
      await avis.requestReview();
    } catch (e) {
      debugPrint('AvisService: $e');
    }
  }
}
