// SnapMeet - Tests de base
// Pour lancer : flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/shared/models/story_model.dart';
import 'package:rencontre/features/profil/vue/qr_zamu.dart';

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
}
