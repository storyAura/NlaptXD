import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/core/llm/api_profile.dart';
import 'package:nlaptxd/core/llm/openai_client.dart';
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
  'llm': {
    'profiles': [
      _profile('aihubmix', 'openai', 'https://aihubmix.com/v1', ['flash']),
      _profile('openrouter', 'anthropic', 'https://openrouter.ai/api', ['muse']),
      _profile('vertex', 'gemini', 'https://aiplatform.googleapis.com/v1', ['argon']),
    ],
    'vision_target': {'profile': 'aihubmix', 'model': 'flash'},
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
    final c = importLegacy(const AppConfig(), api: _api, cha: _cha, prompts: _prompts);
    expect([for (final p in c.profiles) (p.name, p.baseUrl, p.models.join(','), p.enabled, p.apiKey)], [
      ('aihubmix', 'https://aihubmix.com/v1', 'flash', true, 'sk-aihubmix'),
      ('openrouter', 'https://openrouter.ai/api/v1', 'muse', true, 'sk-openrouter'),
      ('vertex', 'https://aiplatform.googleapis.com/v1', 'argon', false, 'sk-vertex'),
    ]);
    expect(c.vision, const ModelRef('nlapt-aihubmix', 'flash'));
    expect(c.chaCards, [const ModelRef('nlapt-vertex', 'argon'), const ModelRef('nlapt-aihubmix', 'flash'), null]);
    expect(c.chaScene, const ModelRef('nlapt-openrouter', 'muse'));
    expect(c.system, '你是一个图像分析系统。');
    expect(c.prompt, defaultVisionPrompt);
    expect(c.legacyImported, isTrue);
  });

  test('fills only empty slots and skips profiles already imported', () {
    const mine = ModelRef('p1', 'm');
    final cur = AppConfig(
      profiles: const [ApiProfile(id: 'nlapt-aihubmix', name: 'renamed', baseUrl: 'u', apiKey: 'k')],
      vision: mine,
      system: 'keep me',
      prompt: 'my prompt',
    );
    final c = importLegacy(cur, api: _api, cha: _cha, prompts: {..._prompts, 'user_prompt': 'old user'});
    expect([for (final p in c.profiles) p.name], ['renamed', 'openrouter', 'vertex']);
    expect(c.vision, mine);
    expect(c.system, 'keep me');
    expect(c.prompt, 'my prompt');
  });

  test('missing files still mark the import done', () {
    final c = importLegacy(const AppConfig());
    expect(c.profiles, isEmpty);
    expect(c.legacyImported, isTrue);
  });
}
