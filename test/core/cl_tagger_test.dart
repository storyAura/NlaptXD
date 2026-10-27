import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/core/local/character_index.dart';
import 'package:nlaptxd/core/local/cl_tagger.dart';

// 和真表一样:开头有 BOM,CRLF,字段里有引号和逗号。
const _csv = '﻿character_tag,other_names,copyright,parent_tag,post_count\r\n'
    '"""a-z""",,,,2\r\n'
    'hatsune_miku,"ミク,初音",vocaloid,,90000\r\n'
    'hatsune_miku_(append),,vocaloid,hatsune_miku,800\r\n'
    'sakura_miku,,vocaloid,hatsune_miku,3000\r\n'
    'loop_a,,x,loop_b,1\r\n'
    'loop_b,,x,loop_a,1\r\n';

double _logit(double p) => math.log(p / (1 - p));

void main() {
  test('reads the BOM-prefixed csv with quoted fields', () {
    final index = CharacterIndex.parse(_csv);
    expect(index.length, 6);
    expect(index.lookup('"a-z"')?.posts, 2);
    expect(index.lookup('Hatsune Miku')?.copyright, 'vocaloid');
    expect(parseCsv('a,"b ""c"", d"\n')[0], ['a', 'b "c", d']);
  });

  test('family is root + descendants + self by post count, relations relative to the detected tag', () {
    final index = CharacterIndex.parse(_csv);
    expect([for (final e in index.family('sakura_miku')) e.tag], ['hatsune_miku', 'sakura_miku', 'hatsune_miku_(append)']);
    final miku = index.lookup('hatsune_miku')!, append = index.lookup('hatsune_miku_(append)')!;
    expect(index.relationOf(miku, 'sakura_miku'), CharacterRelation.parent);
    expect(index.relationOf(append, 'sakura_miku'), CharacterRelation.sibling);
    expect(index.relationOf(append, 'hatsune_miku'), CharacterRelation.child);
    expect(index.family('loop_a').length, 2, reason: '父子成环不会死循环');
    expect(index.family('nobody'), isEmpty);
  });

  test('candidates expand the family, fall back to the top copyright and skip duplicates', () {
    final index = CharacterIndex.parse(_csv);
    final c = expandCandidates((
      characters: [(tag: 'sakura miku', prob: .9), (tag: 'hatsune miku', prob: .5), (tag: "someone o'neill (game)", prob: .4)],
      copyrights: [(tag: 'my_game_(series)', prob: .8)],
    ), index);
    expect([for (final x in c) (x.name, x.series, x.relation)], [
      ('Hatsune Miku', 'Vocaloid', CharacterRelation.parent),
      ('Sakura Miku', 'Vocaloid', CharacterRelation.detected),
      ('Hatsune Miku', 'Vocaloid', CharacterRelation.sibling),
      ("Someone O'Neill", 'My Game', CharacterRelation.detected),
    ]);
    expect(c[1].prob, .9);
    expect(c[0].prob, 0);
  });

  test('python-style title case', () {
    expect(pyTitle("o'neill 2b-chan"), "O'Neill 2B-Chan");
    expect(displayName('hatsune_miku_(append)'), 'Hatsune Miku');
  });

  test('vocabulary with category names or indexes, logits decoded through sigmoid', () {
    final vocab = parseClVocabulary(jsonEncode({
      'idx_to_tag': {'0': '1girl', '1': 'hatsune miku', '2': 'vocaloid', '3': 'kagamine rin'},
      'tag_to_category': {'1girl': 'General', 'hatsune miku': 'Character', 'vocaloid': 2, 'kagamine rin': 'Character'},
    }));
    expect([for (final v in vocab) v.category], ['general', 'character', 'copyright', 'character']);
    final tags = decodeClTags([_logit(.99), _logit(.6), _logit(.7), _logit(.2)], vocab);
    expect([for (final t in tags.characters) t.tag], ['hatsune miku']);
    expect(tags.characters.single.prob, closeTo(.6, 1e-9));
    expect([for (final t in tags.copyrights) t.tag], ['vocaloid']);
  });

  test('pixels: transparent becomes white, channels first, scaled to -1..1', () {
    final rgba = Uint8List(clImageSize * clImageSize * 4);
    rgba.setAll(0, [255, 0, 0, 255]); // 第一个点红色不透明,其余全透明
    final px = clPixels(rgba);
    const plane = clImageSize * clImageSize;
    expect([px[0], px[plane], px[2 * plane]], [1, -1, -1]);
    expect([px[1], px[plane + 1], px[2 * plane + 1]], [1, 1, 1]);
  });
}
