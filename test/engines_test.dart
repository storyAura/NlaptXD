import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/core/cha.dart';
import 'package:nlaptxd/core/dataset.dart';
import 'package:nlaptxd/core/llm/api_profile.dart';
import 'package:nlaptxd/core/local/caption_catalog.dart';
import 'package:nlaptxd/data/app_config.dart';
import 'package:nlaptxd/ui/features/local/local_store.dart';
import 'package:nlaptxd/ui/features/workspace/engines.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('nlx_eng'));
  tearDown(() => tmp.deleteSync(recursive: true));

  ImageEntry image(String name, {String ref = ''}) {
    File('${tmp.path}/$name').writeAsBytesSync([1, 2, 3]);
    return ImageEntry(imagePath: '${tmp.path}/$name', txtPath: '${tmp.path}/$name.txt', folder: '');
  }

  group('chaCaptioner', () {
    final roster = [
      ChaCard.fromText('Aoba', '', 'Aoba has purple hair. She wears a white shirt.'),
      ChaCard.fromText('Yun', '', 'Yun has brown hair. She wears a coat.'),
    ];

    test('one call per image: roster prompt, image first, then references; counts matches', () async {
      File('${tmp.path}/back.png').writeAsBytesSync([9]);
      final withRef = [roster[0], ChaCard.fromText('Yun', '', roster[1].text, [(path: '${tmp.path}/back.png', label: '背面')])];
      final prompts = <String>[];
      final imageCounts = <int>[];
      final counts = <int, int>{};
      final run = chaCaptioner(withRef, ({required prompt, system = '', required images}) async {
        prompts.add(prompt);
        imageCounts.add(images.length);
        return 'CARD: 2\nOUTFIT 2: She wears pajamas.\n\nShe sleeps.';
      }, counts);
      final out = await run(image('a.png'));
      expect(out, 'Yun has brown hair. She wears pajamas.\n\nShe sleeps.');
      expect(prompts.single, contains('Card 2 — name: Yun'));
      expect(prompts.single, contains('reference of card 2 (Yun) — 背面'));
      expect(imageCounts.single, 2);
      expect(counts, {1: 1});
    });

    test('CARD: NONE returns null so the batch skips the image', () async {
      final run = chaCaptioner(roster, ({required prompt, system = '', required images}) async => 'CARD: NONE', {});
      expect(await run(image('b.png')), isNull);
    });
  });

  group('LocalStore', () {
    final gguf = captionModels.firstWhere((m) => !m.florence);

    test('recommended quant by default, picks persist across loads', () async {
      final a = LocalStore(Directory(tmp.path));
      expect(a.quantOf(gguf).recommended, isTrue);
      final other = gguf.quants.firstWhere((q) => !q.recommended);
      a.pickQuant(gguf, other.label);
      a.use(gguf);
      a.update(() => a.source = 'huggingface');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final b = LocalStore(Directory(tmp.path));
      await b.load();
      expect(b.quantOf(gguf).label, other.label);
      expect(b.picked?.id, gguf.id);
      expect(b.files(gguf).first.url, startsWith('https://huggingface.co/${gguf.repo}/resolve/main/'));
      a.dispose();
      b.dispose();
    });

    test('files land under models/gguf/<id> and include the vision component', () {
      final s = LocalStore(Directory(tmp.path));
      final fs = s.files(gguf);
      expect(fs.first.path, contains('${Platform.pathSeparator}models${Platform.pathSeparator}gguf${Platform.pathSeparator}${gguf.id}'));
      expect(fs.first.url, startsWith('https://hf-mirror.com/'));
      expect(fs, hasLength(2));
      s.dispose();
    });

    test('nothing downloaded: no local captioner, and CHA cannot pick the local slot', () {
      final s = LocalStore(Directory(tmp.path))..use(gguf);
      expect(s.installed(gguf), isFalse);
      expect(s.captioner(prompt: 'p'), isNull);
      expect(askerFor(const ModelRef(localProfileId, ''), const AppConfig(), s), isNull);
      s.dispose();
    });
  });
}
