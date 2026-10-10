import 'package:flutter_test/flutter_test.dart';
import 'package:rencontre/core/i18n/en_auto.dart';

void main() {
  test('chaque traduction anglaise garde les paramètres @… du texte français', () {
    // « @pseudo » / « @username » est du texte affiché, pas un paramètre.
    final motAffiche = RegExp(r'(?<!@)@(pseudo|username)');
    int nbParams(String s) => '@'.allMatches(s.replaceAll(motAffiche, '')).length;
    for (final e in enAuto.entries) {
      // ≤ : l'anglais peut omettre un accord (« bloqué@p2 » → « blocked »).
      expect(nbParams(e.value) <= nbParams(e.key), isTrue,
          reason: '${e.key} → ${e.value}');
    }
  });
}
