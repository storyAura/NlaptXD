import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/core/json_caption.dart';
import 'package:nlaptxd/core/llm/llm_client.dart';

void main() {
  group('mossLayoutFromReply', () {
    test('ref1000 xyxy → abs_centralized yxyx, style before caption, junk items dropped', () {
      const reply = '''```json
{"summary": {"meta": "illustration", "canvas": "poster", "style": "Flat cel shading. Palette: aqua, navy", "caption": "A girl in the rain."},
 "items": [
  {"label": "character", "caption": "Miku stands.", "bbox": [250, 200, 750, 1000]},
  {"label": "text", "text": "MIKU", "caption": "Big letters.", "bbox": [100, 50, 900, 1200]},
  {"label": "lamp", "caption": "A lamp.", "bbox": [500, 500, 500, 600]},
  {"label": "object", "caption": "", "bbox": [0, 0, 10, 10]}
 ]}
```''';
      final j = jsonDecode(mossLayoutFromReply(reply, 832, 1216)) as Map;
      expect(j['summary'], {
        'meta': ['illustration'],
        'canvas': 'single',
        'caption': 'Flat cel shading. Palette: aqua, navy. A girl in the rain.',
      });
      final items = j['items'] as List;
      expect(items, hasLength(2));
      // x 250→208、750→624,y 200→243、1000→1216;再减 w/2=416、h/2=608。
      expect(items[0], {'label': 'character', 'caption': 'Miku stands.', 'bbox': [-365, -208, 608, 208]});
      // 超出 1000 的截到 1000。
      expect(items[1], {'label': 'text', 'caption': 'Big letters.', 'text': 'MIKU', 'bbox': [-547, -333, 608, 333]});
      expect(j['bbox_coord_space'], 'abs_centralized');
      expect(j['bbox_format'], 'yxyx');
    });

    test('readMossLayout round-trips what mossLayoutFromReply writes; non-layout text is null', () {
      final out = mossLayoutFromReply('{"summary": {"caption": "A cat."}, "items": [{"label": "text", "text": "HI", "caption": "Big.", "bbox": [0, 0, 500, 500]}]}', 100, 100);
      final l = readMossLayout(out)!;
      expect(l.items.single.text, 'HI');
      expect(l.items.single.bbox, [-50, -50, 0, 0]);
      expect(l.toJson(), out);
      expect(l.copyWith(items: [l.items.single.copyWith(label: 'object')]).toJson(), isNot(contains('"text"')));
      expect(readMossLayout('aoba, 1girl'), isNull);
      expect(readMossLayout('{"a": 1}'), isNull);
    });

    test('refusal, non-JSON and missing caption throw', () {
      expect(() => mossLayoutFromReply("I'm sorry, I can't help.", 100, 100), throwsA(isA<LlmError>()));
      expect(() => mossLayoutFromReply('A girl in the rain.', 100, 100), throwsA(isA<LlmError>()));
      expect(() => mossLayoutFromReply('{"summary": {"caption": ""}}', 100, 100), throwsA(isA<LlmError>()));
    });
  });
}
