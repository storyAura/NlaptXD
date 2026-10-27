import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/core/llm/api_profile.dart';
import 'package:nlaptxd/core/llm/llm_client.dart';
import 'package:nlaptxd/core/llm/translate.dart';
import 'package:nlaptxd/data/app_config.dart';
import 'package:nlaptxd/data/legacy_import.dart';

Map<String, dynamic> _profile(String name, String type, String url, List<String> enabled) => {
  'name': name,
  'api_type': type,
  'base_url': url,
  'api_key': 'sk-$name',
  'models': [...enabled, 'unpicked'],
  'enabled_models': enabled,
  'text_model': '',
  'vision_model': '',
};

final _api = <String, dynamic>{
  'huggingface': {'token': ' hf_fake '},
  'translate': {'deeplx_url': 'https://dx.example/k/translate', 'deeplx_token': '', 'baidu_appid': ''},
  'llm': {
    'profiles': [
      _profile('aihubmix', 'openai', 'https://aihubmix.com/v1', ['flash']),
      _profile('openrouter', 'anthropic', 'https://openrouter.ai/api', ['muse']),
      _profile('vertex', 'gemini', 'https://aiplatform.googleapis.com/v1', ['argon']),
    ],
    'vision_target': {'profile': 'aihubmix', 'model': 'flash'},
    'text_target': {'profile': 'openrouter', 'model': 'muse'},
  },
};
final _cha = <String, dynamic>{
  'card_models': [
    {'profile': 'vertex', 'model': 'argon'},
    {'profile': 'aihubmix', 'model': 'flash'},
    {'profile': '', 'model': ''},
  ],
  'batch_model': {'profile': 'openrouter', 'model': 'muse'},
};
final _prompts = <String, dynamic>{
  'active': '中文',
  'prompts': {'中文': '你是一个图像分析系统。', 'other': 'x'},
  'user_prompt': '',
};

void main() {
  test('imports profiles, picked models, targets and the active system prompt', () {
    final c = importLegacy(const AppConfig(), api: _api, cha: _cha, prompts: _prompts, app: {'request': {'concurrency': 20}},
        translate: {'provider': 'deeplx', 'fallback_order': ['google', 'local_mt']});
    expect((c.translate.service, c.translate.fallbacks.single, c.translate.deeplxUrl), (TranslateService.deeplx, TranslateService.google, 'https://dx.example/k/translate'));
    expect(c.textModel, const ModelRef('nlapt-openrouter', 'muse'));
    expect(c.parallel, 20);
    expect([for (final p in c.profiles) (p.name, p.protocol, p.baseUrl, p.models.join(','), p.enabled, p.apiKey)], [
      ('aihubmix', ApiProtocol.openai, 'https://aihubmix.com/v1', 'flash', true, 'sk-aihubmix'),
      ('openrouter', ApiProtocol.anthropic, 'https://openrouter.ai/api', 'muse', true, 'sk-openrouter'),
      ('vertex', ApiProtocol.gemini, 'https://aiplatform.googleapis.com/v1', 'argon', true, 'sk-vertex'),
    ]);
    expect(c.vision, const ModelRef('nlapt-aihubmix', 'flash'));
    expect(c.chaCards, [const ModelRef('nlapt-vertex', 'argon'), const ModelRef('nlapt-aihubmix', 'flash'), null]);
    expect(c.chaScene, const ModelRef('nlapt-openrouter', 'muse'));
    expect(c.systemPrompts, {'中文': '你是一个图像分析系统。', 'other': 'x'});
    expect(c.systemName, '中文');
    expect(c.system, '你是一个图像分析系统。');
    expect(c.systemNames, ['结构化视觉编译', '客观视觉报告', '中文', 'other']);
    expect(c.prompt, defaultVisionPrompt);
    expect(c.hfToken, 'hf_fake');
    expect(c.legacyImport, legacyImportVersion);
  });

  test('fills only empty slots and skips profiles already imported', () {
    const mine = ModelRef('p1', 'm');
    final cur = AppConfig(
      profiles: const [ApiProfile(id: 'nlapt-aihubmix', name: 'renamed', baseUrl: 'u', apiKey: 'k')],
      vision: mine,
      systemPrompts: const {'中文': 'keep me'},
      systemName: '客观视觉报告',
      prompt: 'my prompt',
    );
    final c = importLegacy(cur, api: _api, cha: _cha, prompts: {..._prompts, 'user_prompt': 'old user'});
    expect([for (final p in c.profiles) p.name], ['renamed', 'openrouter', 'vertex']);
    expect(c.vision, mine);
    expect(c.systemPrompts, {'中文': 'keep me', 'other': 'x'});
    expect(c.systemName, '客观视觉报告');
    expect(c.prompt, 'my prompt');
  });

  test('step 2 only adds the presets and gives the single imported prompt its old name back', () {
    // 第 1 步导入时(旧版本)只存了一条 system,读进来是「系统提示词」方案。
    final cur = AppConfig.fromJson({'system': '你是一个图像分析系统。', 'legacyImported': true});
    expect((cur.systemName, cur.legacyImport), ('系统提示词', 1));
    final c = importLegacy(cur, api: _api, cha: _cha, prompts: _prompts);
    expect(c.profiles, isEmpty);
    expect(c.systemPrompts, {'中文': '你是一个图像分析系统。', 'other': 'x'});
    expect(c.systemName, '中文');
  });

  test('step 6 gives earlier imports their real format back, but leaves ones the user changed', () {
    final cur = AppConfig(
      legacyImport: 5,
      profiles: const [
        // 早先的做法:Anthropic 补 /v1 当 OpenAI 用,Google 停用。
        ApiProfile(id: 'nlapt-openrouter', name: 'openrouter', baseUrl: 'https://openrouter.ai/api/v1', apiKey: 'k'),
        ApiProfile(id: 'nlapt-vertex', name: 'vertex', baseUrl: 'https://aiplatform.googleapis.com/v1', apiKey: 'k', enabled: false),
        ApiProfile(id: 'nlapt-aihubmix', name: 'mine', baseUrl: 'https://changed', apiKey: 'k', protocol: ApiProtocol.anthropic),
      ],
    );
    final c = importLegacy(cur, api: _api);
    expect([for (final p in c.profiles) (p.protocol, p.baseUrl, p.enabled)], [
      (ApiProtocol.anthropic, 'https://openrouter.ai/api', true),
      (ApiProtocol.gemini, 'https://aiplatform.googleapis.com/v1', true),
      (ApiProtocol.anthropic, 'https://changed', true),
    ]);
    expect(c.legacyImport, legacyImportVersion);
  });

  test('missing files still mark the import done', () {
    final c = importLegacy(const AppConfig());
    expect(c.profiles, isEmpty);
    expect(c.legacyImport, legacyImportVersion);
  });
}
