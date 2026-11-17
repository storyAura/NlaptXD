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
        bind: (folder: 'a', solo: false, refs: false, text: true),
      ),
    ]);
    final raw = File('${data.path}${sep}cha_cards.json').readAsStringSync();
    expect(raw, isNot(contains(abs.replaceAll(r'\', r'\\'))), reason: '存相对路径');
    final back = await loadChaCards(data, root);
    final c = back!.cards.single;
    expect((c.name, c.series, c.ref), ('Si', 'Arknights', '$abs${sep}a${sep}1.png'));
    expect([for (final r in c.references) r.label], ['back']);
    expect(c.bind, (folder: 'a', solo: false, refs: false, text: true));
  });

  test('drafts: same id replaces, all three candidates and the binding survive, only the newest chaDraftsKeep kept', () async {
    final sep = Platform.pathSeparator;
    ChaDraft draft(int i, {String? id}) => (
      id: id ?? 'd$i',
      time: DateTime(2026, 11, 18, 10, i),
      done: false,
      step: 2,
      cards: [
        (
          name: 'Si',
          series: '',
          ref: '${root.absolute.path}${sep}a${sep}1.png',
          references: const [],
          cands: ['one $i', '', 'three'],
          pick: 0,
          bind: (folder: 'a', solo: true, refs: true, text: false),
        ),
      ],
    );
    var all = const <ChaDraft>[];
    for (var i = 0; i < chaDraftsKeep + 3; i++) {
      all = withDraft(all, draft(i));
    }
    all = withDraft(all, draft(99, id: 'd5'));
    expect(all.length, chaDraftsKeep);
    expect(all.where((d) => d.id == 'd5').single.cards.single.cands.first, 'one 99');
    await saveChaDrafts(data, root, all);
    final back = await loadChaDrafts(data, root);
    expect(back.length, chaDraftsKeep);
    final c = back.last.cards.single;
    expect(c.cands, ['one 99', '', 'three']);
    expect((c.pick, c.ref, c.bind), (0, '${root.absolute.path}${sep}a${sep}1.png', (folder: 'a', solo: true, refs: true, text: false)));
    File('${data.path}/cha_drafts.json').writeAsStringSync('[oops');
    expect(await loadChaDrafts(data, root), isEmpty);
  });

  test('no file or a broken file means nothing to reuse', () async {
    expect(await loadChaCards(data, root), isNull);
    File('${data.path}/cha_cards.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{oops');
    expect(await loadChaCards(data, root), isNull);
  });

  test('CHA runs: appended in order, only the newest chaRunsKeep kept, broken file reads as empty', () async {
    ChaRun run(int i) => (
      time: DateTime(2026, 11, 16, 10, i),
      model: 'm$i',
      cards: [(name: 'Si', series: 'Arknights', text: 'card $i', images: ['a/1.png'])],
      written: i,
      skipped: 1,
      failed: 0,
      cancelled: i.isOdd,
      missed: ['b/$i.png'],
    );
    for (var i = 0; i < chaRunsKeep + 2; i++) {
      await appendChaRun(data, run(i));
    }
    final back = await loadChaRuns(data);
    expect(back.length, chaRunsKeep);
    expect(back.first.model, 'm2');
    expect(back.last.cards.single.text, 'card ${chaRunsKeep + 1}');
    expect(back.last.cards.single.images, ['a/1.png']);
    expect(back.last.cancelled, isTrue);
    expect(back.last.missed, ['b/${chaRunsKeep + 1}.png']);
    File('${data.path}/cha_runs.json').writeAsStringSync('{bad');
    expect(await loadChaRuns(data), isEmpty);
  });
}
