import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/core/dataset.dart';
import 'package:nlaptxd/core/text_io.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nlx_ds');
  });
  tearDown(() => root.delete(recursive: true));

  void touch(String rel, [List<int> bytes = const []]) {
    File('${root.path}/$rel')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  }

  test('pairs images with same-stem txt, recursively, naturally sorted', () async {
    touch('10_aoba/img10.png');
    touch('10_aoba/img2.PNG');
    touch('10_aoba/img2.TXT', utf8.encode('a, b'));
    touch('root.jpg');
    touch('notes.txt');
    final entries = await scanDataset(root);
    expect(entries.map((e) => e.name), ['root.jpg', 'img2.PNG', 'img10.png']);
    expect(entries.map((e) => e.folder), ['', '10_aoba', '10_aoba']);
    expect(entries[1].txtPath.toLowerCase(), endsWith('img2.txt'));
    expect(entries[2].txtPath, endsWith('img10.txt'));
  });

  test('skips dot folders such as .backups and .nlapt', () async {
    touch('.backups/x.png');
    touch('.nlapt/y.png');
    touch('a.webp');
    expect((await scanDataset(root)).map((e) => e.name), ['a.webp']);
  });

  test('readCaption strips a BOM and flags non-UTF-8 text', () async {
    touch('a.txt', [0xEF, 0xBB, 0xBF, ...utf8.encode('解析')]);
    touch('b.txt', [0xC4, 0xE3]); // GBK bytes
    final a = await readCaption(File('${root.path}/a.txt'));
    expect(a.text, '解析');
    expect(a.utf8, isTrue);
    final b = await readCaption(File('${root.path}/b.txt'));
    expect(b.utf8, isFalse);
    final missing = await readCaption(File('${root.path}/none.txt'));
    expect(missing.text, '');
  });

  test('writeAtomic replaces the file and leaves no temp behind', () async {
    final path = '${root.path}/c.txt';
    await writeAtomic(path, 'one');
    await writeAtomic(path, 'two');
    expect(File(path).readAsStringSync(), 'two');
    expect(root.listSync().map((e) => e.path).where((p) => p.contains('tmp')), isEmpty);
  });
}
