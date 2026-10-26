import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/core/text_ops.dart';

void main() {
  group('FindSpec', () {
    test('counts case-insensitively by default', () {
      expect(const FindSpec('Hair').count('long hair, short HAIR'), 2);
    });

    test('case-sensitive and whole-word narrow the match', () {
      expect(const FindSpec('hair', caseSensitive: true).count('Hair, hair'), 1);
      expect(const FindSpec('hair', wholeWord: true).count('hairband, hair'), 1);
    });

    test('regex characters in the query are literal', () {
      expect(const FindSpec('a+b').count('a+b, aab'), 1);
    });

    test('an empty query matches nothing', () {
      expect(const FindSpec('').count('abc'), 0);
    });
  });

  group('replaceIn', () {
    test('replaces every match', () {
      expect(
        replaceIn('violet hair, violet eyes', const FindSpec('violet'), 'purple'),
        'purple hair, purple eyes',
      );
    });

    test('deleting a whole tag also removes its comma', () {
      expect(replaceIn('a, solo, b', const FindSpec('solo'), ''), 'a, b');
    });
  });

  group('addAffix', () {
    test('as a tag it joins with a comma at the start or end', () {
      expect(addAffix('1girl, solo', 'aoba', atStart: true, asTag: true),
          'aoba, 1girl, solo');
      expect(addAffix('1girl', 'masterpiece', atStart: false, asTag: true),
          '1girl, masterpiece');
    });

    test('as a tag it skips a trigger that is already there', () {
      expect(addAffix('aoba, 1girl', 'aoba', atStart: true, asTag: true),
          'aoba, 1girl');
    });

    test('a longer word starting with the trigger does not count as present', () {
      expect(addAffix('caterpillar', 'cat', atStart: true, asTag: true),
          'cat, caterpillar');
    });

    test('on an empty caption it is just the affix', () {
      expect(addAffix('', 'aoba', atStart: true, asTag: true), 'aoba');
    });

    test('raw mode concatenates as typed', () {
      expect(addAffix('girl', 'a ', atStart: true, asTag: false), 'a girl');
    });
  });
}
