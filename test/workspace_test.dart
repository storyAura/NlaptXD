import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/core/dataset.dart';
import 'package:nlaptxd/core/text_ops.dart';
import 'package:nlaptxd/ui/features/workspace/workspace.dart';

void main() {
  late Directory root;
  late Workspace ws;
  CaptionFn? fake;

  String txt(String rel) => File('${root.path}/$rel').readAsStringSync();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nlx_ws');
    for (final (rel, cap) in [('a/1.png', 'violet hair, solo'), ('a/2.png', 'violet hair'), ('b/3.png', '')]) {
      File('${root.path}/$rel').createSync(recursive: true);
      if (cap.isNotEmpty) File('${root.path}/${rel.replaceAll('.png', '.txt')}').writeAsStringSync(cap);
    }
    fake = (ImageEntry e) async => e.name == '2.png' ? throw Exception('refused') : 'new ${e.name}';
    ws = Workspace();
    await ws.open(root);
  });
  tearDown(() => root.delete(recursive: true));

  test('edits stay in memory until saved, and undo walks back', () async {
    ws.setText('violet hair, solo, smile', label: '编辑');
    expect(ws.dirtyCount, 1);
    expect(txt('a/1.txt'), 'violet hair, solo');
    await ws.save();
    expect(txt('a/1.txt'), 'violet hair, solo, smile');
    expect(ws.dirtyCount, 0);
    expect(ws.undo(), isTrue);
    expect(ws.textOf(ws.entry!), 'violet hair, solo');
  });

  test('first save of an unlabeled image creates its txt', () async {
    ws.select(2);
    ws.setText('1girl', label: '编辑');
    await ws.save();
    expect(txt('b/3.txt'), '1girl');
  });

  test('find/replace snapshots, writes, logs, and rolls back as one batch', () async {
    final n = await ws.findReplace(Scope.all, const FindSpec('violet'), 'purple');
    expect(n, 2);
    expect(txt('a/2.txt'), 'purple hair');
    expect(Directory('${root.path}/.backups').listSync(), hasLength(1));
    final op = ws.oplog!.records.single;
    expect(op.changes, hasLength(2));
    ws.select(1);
    expect(ws.history!.entries.first.text, 'violet hair', reason: 'history starts from the pre-batch text');
    await ws.rollback(op.id);
    expect(txt('a/1.txt'), 'violet hair, solo');
    expect(ws.textOf(ws.entries[1]), 'violet hair');
  });

  test('folder scope only touches the current folder', () async {
    ws.select(2);
    final n = await ws.addAffixTo(Scope.folder, 'aoba', atStart: true, asTag: true);
    expect(n, 1);
    expect(txt('b/3.txt'), 'aoba');
    expect(txt('a/1.txt'), 'violet hair, solo');
  });

  test('batch inference keeps the original when a model call fails', () async {
    await ws.startBatch(Scope.all, fake);
    expect(txt('a/1.txt'), 'new 1.png');
    expect(txt('a/2.txt'), 'violet hair');
    expect(ws.lastJob!.failed, 1);
    expect(ws.oplog!.records.single.changes, hasLength(2));
  });

  test('single inference waits for accept before changing the caption', () async {
    expect(await ws.inferCurrent(fake, 'fake'), isNull);
    expect(ws.textOf(ws.entry!), 'violet hair, solo');
    ws.acceptPending();
    expect(ws.textOf(ws.entry!), 'new 1.png');
    expect(ws.isDirty(ws.entry!), isTrue);
  });

  test('a captioner returning null skips the image: nothing written, counted as skipped', () async {
    await ws.startBatch(Scope.all, (e) async => e.name == '1.png' ? null : 'x');
    expect(txt('a/1.txt'), 'violet hair, solo');
    expect(ws.lastJob!.skipped.map((e) => e.name), ['1.png']);
    expect(ws.oplog!.records.single.detail, contains('跳过 1'));
  });

  test('without a vision model inference explains what to do', () async {
    expect(await ws.inferCurrent(null, 'x'), contains('模型'));
  });
}
