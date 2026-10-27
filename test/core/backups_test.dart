import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/core/backups.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nlx_bk');
  });
  tearDown(() => root.delete(recursive: true));

  void write(String rel, String text) =>
      File('${root.path}/$rel')
        ..createSync(recursive: true)
        ..writeAsStringSync(text);

  test('snapshot zips every txt except .backups/.nlapt', () async {
    write('a.txt', 'A');
    write('sub/b.txt', 'B');
    write('.nlapt/x.txt', 'X');
    final name = await snapshotCaptions(root, Directory('${root.path}/.backups'), '查找替换', now: DateTime(2026, 10, 26, 14, 28));
    expect(name, '2026-10-26_1428_查找替换.zip');
    final zip = ZipDecoder().decodeBytes(File('${root.path}/.backups/$name').readAsBytesSync());
    expect(zip.files.map((f) => f.name).toList()..sort(), ['a.txt', 'sub/b.txt']);
  });

  test('a second snapshot in the same minute gets a suffix', () async {
    write('a.txt', 'A');
    final t = DateTime(2026, 1, 1, 9, 5);
    await snapshotCaptions(root, Directory('${root.path}/.backups'), 'op', now: t);
    expect(await snapshotCaptions(root, Directory('${root.path}/.backups'), 'op', now: t), '2026-01-01_0905_op_2.zip');
  });

  test('keeps only the newest [keep] snapshots', () async {
    write('a.txt', 'A');
    for (var m = 0; m < 4; m++) {
      await snapshotCaptions(root, Directory('${root.path}/.backups'), 'op', now: DateTime(2026, 1, 1, 9, m), keep: 2);
    }
    final left = Directory('${root.path}/.backups').listSync().map((f) => f.uri.pathSegments.last).toList()..sort();
    expect(left, ['2026-01-01_0902_op.zip', '2026-01-01_0903_op.zip']);
  });

  group('OpLog', () {
    OpRecord rec(int id) => OpRecord(
      id: id,
      title: '前缀',
      detail: '「aoba」',
      time: DateTime(2026, 10, 26),
      backup: 'b.zip',
      changes: const [OpChange('a.txt', 'old')],
    );

    test('persists records newest first and reloads them', () async {
      final log = OpLog(Directory('${root.path}/.nlapt'));
      await log.load();
      await log.add(rec(log.nextId));
      await log.add(rec(log.nextId));
      final again = OpLog(Directory('${root.path}/.nlapt'));
      await again.load();
      expect(again.records.map((r) => r.id), [2, 1]);
      expect(again.records.first.changes.single.before, 'old');
    });

    test('marking rolled back is persisted', () async {
      final log = OpLog(Directory('${root.path}/.nlapt'));
      await log.load();
      await log.add(rec(1));
      await log.setStatus(1, OpStatus.rolledBack);
      final again = OpLog(Directory('${root.path}/.nlapt'));
      await again.load();
      expect(again.records.single.status, OpStatus.rolledBack);
    });

    test('a corrupt log file loads as empty instead of crashing', () async {
      write('.nlapt/oplog.json', '{not json');
      final log = OpLog(Directory('${root.path}/.nlapt'));
      await log.load();
      expect(log.records, isEmpty);
    });
  });
}
