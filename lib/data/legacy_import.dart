import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/llm/api_profile.dart';
import '../core/llm/openai_client.dart';
import 'app_config.dart';

/// 旧版 NLapt 导进来的接口 id 前缀(旧版用接口名当 id)。
const legacyIdPrefix = 'nlapt-';

/// 旧版的接口地址换成 OpenAI 兼容地址;换不了的返回 null(接口照样导入,但先停用)。
/// Anthropic 风格的地址不带 /v1,客户端自己拼 /v1/messages;OpenAI 兼容的要带(OpenRouter 就是这样)。
String? openAiBase(String type, String url) {
  final u = url.trim().replaceFirst(RegExp(r'/+$'), '');
  return switch (type) {
    'openai' => u,
    'anthropic' => u.endsWith('/v1') ? u : '$u/v1',
    _ => null,
  };
}

ModelRef? _ref(Object? j) {
  if (j is! Map) return null;
  final profile = j['profile'], model = j['model'];
  if (profile is! String || model is! String || profile.isEmpty || model.isEmpty) return null;
  return ModelRef('$legacyIdPrefix$profile', model);
}

/// 把旧版的 api.json(接口、推标模型)、cha_annotation.json(CHA 模型位)、vision_prompts.json
/// (系统提示词、推标提示词)并进 [cur]。只填空位、不覆盖已有设置;id 已存在的接口跳过。
AppConfig importLegacy(AppConfig cur, {Map<String, dynamic>? api, Map<String, dynamic>? cha, Map<String, dynamic>? prompts}) {
  final llm = api?['llm'] is Map ? api!['llm'] as Map : const {};
  final have = {for (final p in cur.profiles) p.id};
  final added = <ApiProfile>[];
  for (final p in llm['profiles'] as List? ?? const []) {
    if (p is! Map || p['name'] is! String || (p['name'] as String).isEmpty) continue;
    final id = '$legacyIdPrefix${p['name']}';
    if (have.contains(id)) continue;
    final base = openAiBase(p['api_type'] as String? ?? 'openai', p['base_url'] as String? ?? '');
    final enabled = [for (final m in p['enabled_models'] as List? ?? const []) if (m is String && m.isNotEmpty) m];
    final picked = enabled.isNotEmpty ? enabled : {p['text_model'], p['vision_model']}.whereType<String>().where((m) => m.isNotEmpty);
    added.add(ApiProfile(
      id: id,
      name: p['name'] as String,
      baseUrl: base ?? p['base_url'] as String? ?? '',
      apiKey: p['api_key'] as String? ?? '',
      models: [...picked],
      enabled: base != null,
    ));
  }
  final cards = cha?['card_models'] as List? ?? const [];
  final presets = prompts?['prompts'] is Map ? prompts!['prompts'] as Map : const {};
  final system = presets[prompts?['active']];
  final user = prompts?['user_prompt'];
  return cur.copyWith(
    profiles: [...cur.profiles, ...added],
    vision: cur.vision ?? _ref(llm['vision_target']),
    chaCards: [for (var i = 0; i < cur.chaCards.length; i++) cur.chaCards[i] ?? _ref(cards.elementAtOrNull(i))],
    chaScene: (cur.chaScene ?? _ref(cha?['batch_model']),),
    system: cur.system.trim().isEmpty && system is String ? system : null,
    prompt: cur.prompt == defaultVisionPrompt && user is String && user.trim().isNotEmpty ? user : null,
    legacyImported: true,
  );
}

Future<Map<String, dynamic>?> _readJson(String path) async {
  try {
    final f = File(path);
    if (!await f.exists()) return null;
    final j = jsonDecode(await f.readAsString());
    return j is Map<String, dynamic> ? j : null;
  } on Object catch (e) {
    debugPrint('旧版设置读不了,跳过 $path:$e');
    return null;
  }
}

/// 从本机旧版的位置读:接口在「文档\NLapt\api.json」,其余在「%APPDATA%\NLapt\」。
Future<AppConfig> importLegacyFiles(AppConfig cur, {required String documents, required String appData}) async {
  final sep = Platform.pathSeparator;
  return importLegacy(
    cur,
    api: await _readJson('$documents${sep}NLapt${sep}api.json'),
    cha: await _readJson('$appData${sep}NLapt${sep}cha_annotation.json'),
    prompts: await _readJson('$appData${sep}NLapt${sep}vision_prompts.json'),
  );
}
