import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/core/captions.dart';

void main() {
  group('splitSegments', () {
    test('splits on half- and full-width commas and trims', () {
      expect(splitSegments(' 1girl ,solo，long hair,, '), [
        '1girl',
        'solo',
        'long hair',
      ]);
    });

    test('empty text has no segments', () {
      expect(splitSegments('  '), isEmpty);
    });
  });

  test('joinSegments drops blanks and joins with ", "', () {
    expect(joinSegments(['a', ' ', ' b ']), 'a, b');
  });

  test('hasCjk detects Chinese', () {
    expect(hasCjk('aoba, 毛衣'), isTrue);
    expect(hasCjk('aoba, sweater'), isFalse);
  });

  test('isSentence: more than four words reads as natural language', () {
    expect(isSentence('looking at viewer'), isFalse);
    expect(isSentence('A girl stands under falling blossoms'), isTrue);
  });
}
