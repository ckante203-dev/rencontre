// Tests de la messagerie : flammes 🔥, modification, disparition après 24 h.
// Pour lancer : flutter test test/messagerie_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:rencontre/features/chat/model/message_model.dart';

DateTime _jour(int decalage) {
  final u = DateTime.now().toUtc();
  return DateTime.utc(u.year, u.month, u.day).add(Duration(days: decalage));
}

ConversationModel _conv({int compte = 0, DateTime? dernier}) =>
    ConversationModel(
      id: 'c1',
      userId: 'u2',
      userName: 'Aïcha',
      flammeCompte: compte,
      flammeDernierJour: dernier,
    );

MessageModel _msg({
  MessageType type = MessageType.text,
  String id = 'm1',
  Duration age = Duration.zero,
  DateTime? readAt,
  StoryReplyData? story,
}) =>
    MessageModel(
      id: id,
      senderId: 'u1',
      text: 'Salut',
      type: type,
      createdAt: DateTime.now().subtract(age),
      readAt: readAt,
      storyReply: story,
    );

void main() {
  group('Flammes 🔥', () {
    test('aucune série sans message', () {
      expect(_conv().flammes, 0);
      expect(_conv().flammeEnDanger, false);
    });

    test('série vivante si dernier message aujourd\'hui ou hier', () {
      expect(_conv(compte: 5, dernier: _jour(0)).flammes, 5);
      expect(_conv(compte: 5, dernier: _jour(-1)).flammes, 5);
    });

    test('série éteinte après un jour sans message', () {
      expect(_conv(compte: 5, dernier: _jour(-2)).flammes, 0);
    });

    test('⏳ en danger seulement si personne n\'a écrit aujourd\'hui', () {
      expect(_conv(compte: 5, dernier: _jour(-1)).flammeEnDanger, true);
      expect(_conv(compte: 5, dernier: _jour(0)).flammeEnDanger, false);
      // Pas de ⏳ tant que la flamme n'est pas affichée (moins de 2 jours)
      expect(_conv(compte: 1, dernier: _jour(-1)).flammeEnDanger, false);
    });

    test('un message aujourd\'hui prolonge la série d\'hier', () {
      final c = _conv(compte: 3, dernier: _jour(-1)).avecMessageAujourdhui();
      expect(c.flammeCompte, 4);
      expect(c.flammes, 4);
    });

    test('plusieurs messages le même jour comptent une seule fois', () {
      final c = _conv(compte: 3, dernier: _jour(0)).avecMessageAujourdhui();
      expect(c.flammeCompte, 3);
    });

    test('la série repart à 1 après une coupure', () {
      final c = _conv(compte: 7, dernier: _jour(-3)).avecMessageAujourdhui();
      expect(c.flammeCompte, 1);
    });

    test('date de la base lue comme un jour UTC (fuseau sans effet)', () {
      final j = ConversationModel.jourDepuisBase('2026-10-02')!;
      expect(j.isUtc, true);
      expect([j.year, j.month, j.day, j.hour], [2026, 10, 2, 0]);
      expect(ConversationModel.jourDepuisBase(null), isNull);
    });

    test('copyWith garde la série', () {
      final c = _conv(compte: 4, dernier: _jour(0)).copyWith(unreadCount: 2);
      expect(c.flammeCompte, 4);
      expect(c.unreadCount, 2);
    });
  });

  group('Modifier un message', () {
    test('texte récent modifiable', () {
      expect(_msg(age: const Duration(minutes: 5)).modifiable, true);
    });

    test('plus modifiable après 15 minutes', () {
      expect(_msg(age: const Duration(minutes: 16)).modifiable, false);
    });

    test('photo, vocal et réponse à une story non modifiables', () {
      expect(_msg(type: MessageType.image).modifiable, false);
      expect(_msg(type: MessageType.audio).modifiable, false);
      expect(
          _msg(
                  story: const StoryReplyData(
                      storyId: 's1',
                      storyPreviewUrl: '',
                      storyIsVideo: false,
                      storyOwnerName: 'Aïcha'))
              .modifiable,
          false);
    });

    test('message en cours d\'envoi non modifiable', () {
      expect(_msg(id: 'temp_123').modifiable, false);
    });
  });

  group('Disparition après lecture', () {
    test('visible tant que non lu', () {
      expect(_msg().isDisappeared, false);
    });

    test('visible pendant 24 h après lecture', () {
      final lu = DateTime.now().subtract(const Duration(hours: 23));
      expect(_msg(readAt: lu).isDisappeared, false);
    });

    test('disparu 24 h après lecture', () {
      final lu = DateTime.now().subtract(const Duration(hours: 25));
      expect(_msg(readAt: lu).isDisappeared, true);
    });
  });
}
