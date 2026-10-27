import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/core/cha_store.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('nlx_cha');
    File('${root.path}/a/1.png').createSync(recursive: true);
    File('${root.path}/a/back.png').createSync(recursive: true);
  });
  tearDown(() => root.delete(recursive: true));

  test('saves relative paths under .nlapt and loads them back; missing images are dropped', () async {
    final sep = Platform.pathSeparator;
    final abs = root.absolute.path;
    await saveChaCards(root, [
      (
        name: 'Si',
        series: 'Arknights',
        text: 'Si from Arknights has green hair.',
        ref: '$abs${sep}a${sep}1.png',
        references: [(path: '$abs${sep}a${sep}back.png', label: 'back'), (path: '$abs${sep}gone.png', label: 'x')],
      ),
    ]);
    final raw = File('$abs$sep.nlapt${sep}cha_cards.json').readAsStringSync();
    expect(raw, isNot(contains(abs.replaceAll(r'\', r'\\'))), reason: '存相对路径');
    final back = await loadChaCards(root);
    final c = back!.cards.single;
    expect((c.name, c.series, c.ref), ('Si', 'Arknights', '$abs${sep}a${sep}1.png'));
    expect([for (final r in c.references) r.label], ['back']);
  });

  test('no file or a broken file means nothing to reuse', () async {
    expect(await loadChaCards(root), isNull);
    File('${root.path}/.nlapt/cha_cards.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{oops');
    expect(await loadChaCards(root), isNull);
  });
}
