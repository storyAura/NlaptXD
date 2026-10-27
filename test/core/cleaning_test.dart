import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nlaptxd/core/llm/cleaning.dart';
import 'package:nlaptxd/core/llm/openai_client.dart';
import 'package:nlaptxd/core/llm/vision_image.dart';

void main() {
  test('unwraps fences, whole-text quotes and label prefixes, but not two quoted phrases', () {
    expect(cleanCaption('```text\nCaption: “a girl, smiling”\n```'), 'a girl, smiling');
    expect(cleanCaption('标注：「蓝色头发」'), '蓝色头发');
    expect(cleanCaption('"blue eyes" and "red hair"'), '"blue eyes" and "red hair"');
  });

  test('refusals and empty replies are errors, so the batch keeps the original', () {
    for (final r in ["I'm sorry, but I can't describe this.", 'This violates our content policy.', '抱歉,我无法协助。']) {
      expect(() => cleanCaption(r), throwsA(isA<LlmError>().having((e) => e.message, 'message', contains('拒绝'))), reason: r);
    }
    expect(() => cleanCaption('  ```\n```  '), throwsA(isA<LlmError>()));
  });

  test('big images shrink to 1024 on the long edge, transparency turns white, small jpegs are sent as-is', () {
    final big = img.Image(width: 2048, height: 1024, numChannels: 4); // 全透明
    final out = prepareImageSync(Uint8List.fromList(img.encodePng(big)), 'image/png');
    expect(out.mime, 'image/jpeg');
    final back = img.decodeJpg(Uint8List.fromList(out.bytes))!;
    expect((back.width, back.height), (1024, 512));
    expect(back.getPixel(10, 10).r, greaterThan(250));

    final small = Uint8List.fromList(img.encodeJpg(img.Image(width: 300, height: 200)));
    expect(identical(prepareImageSync(small, 'image/jpeg').bytes, small), isTrue);
    final junk = Uint8List.fromList([1, 2, 3]);
    expect(prepareImageSync(junk, 'image/webp').bytes, junk, reason: '解不开的原样发');
  });
}
