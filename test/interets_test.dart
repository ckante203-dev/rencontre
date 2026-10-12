import 'package:flutter_test/flutter_test.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';

void main() {
  test("les intérêts de l'inscription correspondent à la liste du profil", () {
    final libelles =
        ControleurProfil.allInterests.map((e) => e['label']).toSet();
    for (final v in [
      '🎵 Musique', '🏔️ Rando', '🎨 Art', '📸 Photo', '🍕 Food', '✈️ Voyage',
      '🎮 Jeux vidéo', '🏋️ Sport', '📚 Lecture', '🎭 Théâtre', '🌿 Nature',
      '💃 Danse', '🎸 Concerts', '🏄 Surf', '🧘 Yoga', '🍷 Gastronomie',
      'Lecture',
    ]) {
      expect(libelles, contains(ControleurProfil.normaliserInteret(v)),
          reason: v);
    }
  });
}
