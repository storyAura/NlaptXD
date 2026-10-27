import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/core/cha_store.dart';

void main() {
  late Directory root;
  late Directory data;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('nlx_cha');
    data = await Directory.systemTemp.createTemp('nlx_cha_data');
    File('${root.path}/a/1.png').createSync(recursive: true);
    File('${root.path}/a/back.png').createSync(recursive: true);
  });
  tearDown(() async {
    await root.delete(recursive: true);
    await data.delete(recursive: true);
  });

  test('saves into the data dir with paths relative to the dataset, loads them back; missing images are dropped', () async {
    final sep = Platform.pathSeparator;
    final abs = root.absolute.path;
    await saveChaCards(data, root, [
      (
        name: 'Si',
        series: 'Arknights',
        text: 'Si from Arknights has green hair.',
        ref: '$abs${sep}a${sep}1.png',
        references: [(path: '$abs${sep}a${sep}back.png', label: 'back'), (path: '$abs${sep}gone.png', label: 'x')],
      ),
    ]);
    final raw = File('${data.path}${sep}cha_cards.json').readAsStringSync();
    expect(raw, isNot(contains(abs.replaceAll(r'\', r'\\'))), reason: '存相对路径');
    final back = await loadChaCards(data, root);
    final c = back!.cards.single;
    expect((c.name, c.series, c.ref), ('Si', 'Arknights', '$abs${sep}a${sep}1.png'));
    expect([for (final r in c.references) r.label], ['back']);
  });

  test('no file or a broken file means nothing to reuse', () async {
    expect(await loadChaCards(data, root), isNull);
    File('${data.path}/cha_cards.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{oops');
    expect(await loadChaCards(data, root), isNull);
  });
}
