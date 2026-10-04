// SnapMeet - Tests de base
// Pour lancer : flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/shared/models/story_model.dart';
import 'package:rencontre/features/profil/vue/qr_zamu.dart';
import 'package:rencontre/features/home/widget/stickers_story.dart';
import 'package:rencontre/features/evenements/evenement_model.dart';

void main() {
  group('UserModel', () {
    test('distanceLabel affiche les mètres sous 1km', () {
      const user = UserModel(
        id: '1',
        name: 'Alex',
        age: 24,
        distanceMeters: 350,
      );
      expect(user.distanceLabel, '350m');
    });

    test('distanceLabel affiche les km au-dessus de 1000m', () {
      const user = UserModel(
        id: '2',
        name: 'Jordan',
        age: 27,
        distanceMeters: 2500,
      );
      expect(user.distanceLabel, '2.5km');
    });

    test('distanceLabel vide si null', () {
      const user = UserModel(id: '3', name: 'Sam', age: 22);
      expect(user.distanceLabel, '');
    });
  });

  group('StoryModel', () {
    test('isExpired retourne true si expiresAt est passé', () {
      final story = StoryModel(
        id: 's1',
        userId: 'u1',
        userName: 'Alex',
        mediaUrl: 'https://example.com/img.jpg',
        createdAt: DateTime.now().subtract(const Duration(hours: 25)),
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(story.isExpired, true);
      expect(story.isActive, false);
    });

    test('isActive retourne true si expiresAt est dans le futur', () {
      final story = StoryModel(
        id: 's2',
        userId: 'u1',
        userName: 'Alex',
        mediaUrl: 'https://example.com/img.jpg',
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        expiresAt: DateTime.now().add(const Duration(hours: 23)),
      );
      expect(story.isActive, true);
      expect(story.isExpired, false);
    });
  });

  group('QR code Zamu', () {
    const uid = '3f2b8c1e-9a4d-4e7f-8b21-0c5d6e7f8a9b';
    test("le lien du QR redonne l'id du profil", () {
      expect(idProfilDepuisQr(lienQrZamu(uid)), uid);
    });
    test('accepte le referrer décodé', () {
      expect(idProfilDepuisQr('x&referrer=zamu_u=$uid'), uid);
    });
    test("refuse un QR qui n'est pas Zamu", () {
      expect(idProfilDepuisQr('https://example.com'), isNull);
      expect(idProfilDepuisQr('zamu_u=pas-un-id'), isNull);
    });
  });

  group('Stickers de story', () {
    test("aller-retour JSON d'un emoji", () {
      const s = StickerStory(type: 'emoji', valeur: '🔥', x: 0.3, y: 0.7, echelle: 2);
      final r = StickerStory.fromJson(s.toJson())!;
      expect(r.valeur, '🔥');
      expect(r.x, 0.3);
      expect(r.echelle, 2);
    });
    test('GIF GIPHY accepté, autre image refusée', () {
      expect(StickerStory.fromJson({'t': 'giphy', 'v': 'https://media2.giphy.com/media/abc/200.gif'}), isNotNull);
      expect(StickerStory.fromJson({'t': 'giphy', 'v': 'https://exemple.com/x.gif'}), isNull);
      expect(StickerStory.fromJson({'t': 'image', 'v': 'x'}), isNull);
    });
    test('liste tolérante : 20 maximum, éléments invalides ignorés', () {
      final brut = [for (var i = 0; i < 25; i++) {'t': 'emoji', 'v': '😂'}, 'nimporte quoi'];
      expect(StickerStory.listeDepuis(brut).length, 20);
      expect(StickerStory.listeDepuis(null), isEmpty);
    });
  });

  group('Événements', () {
    Map<String, dynamic> ligne(DateTime debut, {DateTime? fin}) => {
          'id': 'e1',
          'titre': 'ASEC – Africa',
          'categorie': 'sport',
          'lieu': 'Stade FHB',
          'ville': 'Abidjan',
          'debut': debut.toUtc().toIso8601String(),
          'fin': fin?.toUtc().toIso8601String(),
          'statut': 'publie',
          'nb_participants': 87,
          'je_participe': true,
        };
    test('lecture de la base', () {
      final e = EvenementModel.fromJson(ligne(DateTime(2030, 6, 1, 20)));
      expect(e.emoji, '⚽');
      expect(e.lieuComplet, 'Stade FHB · Abidjan');
      expect(e.nbParticipants, 87);
      expect(e.jeParticipe, true);
      expect(e.debut.hour, 20); // relu en heure locale
    });
    test('sans fin : terminé 12 h après le début', () {
      final e = EvenementModel.fromJson(ligne(DateTime(2030, 6, 1, 20)));
      expect(e.finEffective, DateTime(2030, 6, 2, 8));
    });
    test('en cours / date courte', () {
      final n = DateTime.now();
      final enCours = EvenementModel.fromJson(
          ligne(n.subtract(const Duration(hours: 1))));
      expect(enCours.enCours, true);
      expect(enCours.dateCourte, 'En ce moment');
      final demain = EvenementModel.fromJson(
          ligne(DateTime(n.year, n.month, n.day + 1, 16)));
      expect(demain.dateCourte, 'Demain · 16h00');
    });
    test('participation : compteur mis à jour', () {
      final e = EvenementModel.fromJson(ligne(DateTime(2030, 6, 1, 20)));
      final sans = e.copyWith(jeParticipe: false, nbParticipants: 86);
      expect(sans.jeParticipe, false);
      expect(sans.nbParticipants, 86);
      expect(sans.titre, e.titre);
    });
  });
}
