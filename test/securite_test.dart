import 'package:flutter_test/flutter_test.dart';
import 'package:rencontre/features/chat/model/detection_arnaque.dart';
import 'package:rencontre/features/profil/vue/urgence.dart';

void main() {
  group('détection des messages suspects', () {
    test('argent, Mobile Money, codes et liens sont signalés', () {
      for (final m in [
        'Envoie-moi 5000 fcfa stp',
        'fais moi un dépôt orange money',
        'tu as un compte Wave ?',
        'Donne moi le code de vérification que tu as reçu',
        'clique ici https://exemple.com',
        'Prête-moi un peu d\'argent',
        'Western Union marche aussi',
      ]) {
        expect(messageSuspect(m), isTrue, reason: m);
      }
    });

    test('les messages ordinaires ne sont pas signalés', () {
      for (final m in [
        'Salut, comment tu vas ?',
        'On se voit au maquis ce soir ?',
        'J\'adore ta photo 🔥',
        'Tu fais quoi ce week-end',
        null,
        'ok',
      ]) {
        expect(messageSuspect(m), isFalse, reason: '$m');
      }
    });
  });

  test('numéro d\'urgence au format international', () {
    expect(Urgence.international('07 01 02 03 04'), '2250701020304');
    expect(Urgence.international('+225 07 01 02 03 04'), '2250701020304');
    expect(Urgence.international('0033 6 12 34 56 78'), '33612345678');
  });
}
