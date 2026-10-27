import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/core/llm/llm_client.dart';
import 'package:nlaptxd/core/llm/translate.dart';

void main() {
  test('parses each service reply', () {
    expect(parseGoogle([
      [
        ['你好', 'hello'],
        ['世界', 'world'],
      ],
    ]), '你好世界');
    expect(parseBaidu({
      'trans_result': [
        {'src': 'a', 'dst': '甲'},
        {'src': 'b', 'dst': '乙'},
      ],
    }), '甲\n乙');
    expect(() => parseBaidu({'error_code': '54001', 'error_msg': 'Invalid Sign'}), throwsA(isA<LlmError>()));
    expect(parseDeepl({
      'translations': [
        {'text': 'hallo'},
      ],
    }), 'hallo');
    expect(parseDeeplx({'code': 200, 'data': ' 你好 '}), '你好');
    expect(() => parseDeeplx({'code': 429, 'message': 'busy'}), throwsA(isA<LlmError>()));
  });

  test('baidu sign is md5(appid + q + salt + key)', () {
    // 百度官方文档的示例。
    expect(baiduSign('2015063000000001', 'apple', '1435660288', '12345678'), 'f89f9594663708c1605f3d736d01d2d4');
  });

  test('chinese-heavy text goes to english, everything else to chinese', () {
    expect(autoTarget('紫色头发, smile'), 'en');
    expect(autoTarget('purple hair, 1girl'), 'zh');
    expect(autoTarget('   '), 'zh');
  });

  test('unconfigured services are skipped, the reply is unwrapped and cached', () async {
    var calls = 0;
    final t = Translator(
      const TranslateSettings(service: TranslateService.baidu, fallbacks: [TranslateService.deepl, TranslateService.llm]),
      llm: (prompt, system) async {
        calls++;
        expect(prompt, contains('into Simplified Chinese'));
        return 'Caption: “紫色头发”';
      },
    );
    expect(await t.translate('purple hair cached-test', 'zh'), '紫色头发');
    expect(await t.translate('purple hair cached-test', 'zh'), '紫色头发');
    expect(calls, 1);
  });

  test('with nothing usable the error says how to configure it', () async {
    final t = Translator(const TranslateSettings(service: TranslateService.llm));
    expect(() => t.translate('x', 'zh'), throwsA(isA<TranslateConfigError>().having((e) => e.message, 'm', contains('文本模型'))));
  });

  test('settings round-trip through json', () {
    const s = TranslateSettings(service: TranslateService.deeplx, fallbacks: [TranslateService.google], deeplxUrl: 'https://x/y');
    final back = TranslateSettings.fromJson(s.toJson());
    expect((back.service, back.fallbacks.single, back.deeplxUrl), (TranslateService.deeplx, TranslateService.google, 'https://x/y'));
    expect(back.chain, [TranslateService.deeplx, TranslateService.google]);
  });
}
