import 'package:flutter_test/flutter_test.dart';
import 'package:rencontre/shared/models/user_model.dart';

void main() {
  String? signe(int mois, int jour, {bool visible = true}) => UserModel(
        id: 'x',
        name: 'x',
        age: 25,
        naissance: DateTime(1999, mois, jour),
        showBirthdate: visible,
      ).signeAstro;

  test('signe astrologique aux limites des signes', () {
    expect(signe(1, 19), '♑ Capricorne');
    expect(signe(1, 20), '♒ Verseau');
    expect(signe(3, 21), '♈ Bélier');
    expect(signe(7, 23), '♌ Lion');
    expect(signe(11, 22), '♐ Sagittaire');
    expect(signe(12, 21), '♐ Sagittaire');
    expect(signe(12, 22), '♑ Capricorne');
  });

  test('pas de signe si la date de naissance est masquée ou inconnue', () {
    expect(signe(5, 10, visible: false), isNull);
    expect(const UserModel(id: 'x', name: 'x', age: 0).signeAstro, isNull);
  });
}
