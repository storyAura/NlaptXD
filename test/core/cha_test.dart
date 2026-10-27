import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/core/cha.dart';

const _card =
    'Aoba from New Game! has purple hair in long twintails and purple eyes. '
    'She wears a white shirt, a lanyard and a black skirt.';

ChaCard card(String name, [String text = _card]) => ChaCard.fromText(name, 'New Game!', text);

void main() {
  group('splitCard', () {
    test('splits at the sentence that opens the outfit', () {
      final p = splitCard(_card, 'Aoba');
      expect(p.appearance, 'Aoba from New Game! has purple hair in long twintails and purple eyes.');
      expect(p.outfit, startsWith('She wears a white shirt'));
    });

    test('the name itself can open the outfit, with "is wearing"', () {
      final p = splitCard('Aoba has red eyes. Aoba is wearing a hoodie.', 'Aoba');
      expect(p.outfit, 'Aoba is wearing a hoodie.');
    });

    test('falls back to the first later sentence naming a garment', () {
      final p = splitCard('Aoba has red eyes. A black jacket covers the shoulders.', 'Aoba');
      expect(p.appearance, 'Aoba has red eyes.');
      expect(p.outfit, 'A black jacket covers the shoulders.');
    });

    test('no clothing at all keeps everything as appearance', () {
      final p = splitCard('Aoba has red eyes.', 'Aoba');
      expect(p.appearance, 'Aoba has red eyes.');
      expect(p.outfit, '');
    });
  });

  group('prompts', () {
    test('card prompt opens with "name from series" and carries the variant hint', () {
      final p = buildCardPrompt('Aoba', 'New Game!', variant: 1);
      expect(p, contains('"Aoba from New Game!"'));
      expect(p, contains('alternative 2 of 3'));
      expect(p, isNot(contains('{opening}')));
    });

    test('card prompt lists labelled extra references as images 2..n', () {
      final p = buildCardPrompt('Aoba', '', referenceLabels: ['背面', ' ']);
      expect(p, contains('- Image 2: 背面'));
      expect(p, contains('- Image 3: additional view'));
    });

    test('scene prompt lists every card with appearance and outfit', () {
      final p = buildScenePrompt([card('Aoba'), card('Yun', 'Yun has brown hair.')]);
      expect(p, contains('Card 1 — name: Aoba; appearance: "Aoba from New Game! has purple hair'));
      expect(p, contains('official outfit: "She wears a white shirt'));
      expect(p, contains('Card 2 — name: Yun'));
      expect(p, contains('no official outfit on record'));
      expect(p, isNot(contains('{ROSTER}')));
    });
  });

  group('parseReply', () {
    test('CARD numbers, SAME and rewritten outfits, then the scene', () {
      final v = parseReply('CARD: 3, 1\nOUTFIT 1: SAME.\nOUTFIT 3: She wears a red\n  swimsuit.\n\nThe scene.', 3);
      expect(v.matched, [0, 2]);
      expect(v.outfits, [null, 'She wears a red swimsuit.']);
      expect(v.scene, 'The scene.');
    });

    test('numbers outside the roster are dropped; NONE matches nothing', () {
      expect(parseReply('CARD: 1, 9\n\nscene', 2).matched, [0]);
      final none = parseReply('CARD: NONE', 2);
      expect(none.matched, isEmpty);
    });

    test('an unnumbered OUTFIT line belongs to the single match', () {
      final v = parseReply('CARD: 2\nOUTFIT: She wears pajamas.\n\nscene', 2);
      expect(v.outfits, ['She wears pajamas.']);
    });

    test('no header is accepted only for a one-card roster', () {
      expect(parseReply('Just a scene.', 1).matched, [0]);
      expect(() => parseReply('Just a scene.', 2), throwsA(isA<ChaReplyError>()));
    });
  });

  group('assembleCaption', () {
    final roster = [card('Aoba'), card('Yun', 'Yun has brown hair. She wears a coat.')];

    test('matched cards verbatim (SAME), then the scene', () {
      final out = assembleCaption(roster, parseReply('CARD: 1\nOUTFIT 1: SAME\n\nShe sits.', 2));
      expect(out, '$_card\n\nShe sits.');
    });

    test('a rewritten outfit keeps the appearance and swaps the clothing', () {
      final out = assembleCaption(roster, parseReply('CARD: 2\nOUTFIT 2: She wears pajamas.\n\nShe sleeps.', 2));
      expect(out, 'Yun has brown hair. She wears pajamas.\n\nShe sleeps.');
    });

    test('NONE writes nothing; a match without a scene is an error', () {
      expect(assembleCaption(roster, parseReply('CARD: NONE', 2)), isNull);
      expect(() => assembleCaption(roster, parseReply('CARD: 1', 2)), throwsA(isA<ChaReplyError>()));
    });

    test('VISIBLE trims the card to what this image shows; ALL keeps the full card', () {
      const trimmed = 'Aoba from New Game! has purple hair in long twintails. She wears a white shirt.';
      final v = parseReply('CARD: 1\nOUTFIT 1: SAME\nVISIBLE 1: $trimmed\n\nA close-up of her face.', 2);
      expect(v.visible, [trimmed]);
      expect(assembleCaption(roster, v), '$trimmed\n\nA close-up of her face.');
      final all = parseReply('CARD: 1\nOUTFIT 1: SAME\nVISIBLE 1: ALL\n\nShe stands.', 2);
      expect(all.visible, [null]);
      expect(assembleCaption(roster, all), '$_card\n\nShe stands.');
    });

    test('a VISIBLE line that loses the name, is a stub, or grows longer falls back to the full card', () {
      for (final bad in [
        'She has purple hair in long twintails and purple eyes, wearing a white shirt.',
        'Aoba from New Game!',
        'Aoba from New Game! has purple hair. ${'She also wears a long red cape with golden trim. ' * 4}',
      ]) {
        final out = assembleCaption(roster, parseReply('CARD: 1\nVISIBLE 1: $bad\n\nShe sits.', 2));
        expect(out, '$_card\n\nShe sits.', reason: bad);
      }
    });
  });

  test('scene prompt asks for the visibility check', () {
    expect(buildScenePrompt([card('Aoba')]), contains('VISIBLE <card number>: ALL'));
  });
}
