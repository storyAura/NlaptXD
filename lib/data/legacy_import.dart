import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/llm/api_profile.dart';
import '../core/llm/openai_client.dart';
import '../core/llm/translate.dart';
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

/// 导入分几步,[AppConfig.legacyImport] 记着做到了哪步:1 接口与模型位,2 全部系统提示词方案,3 HuggingFace Token,4 同时发送数,
/// 5 翻译服务(选哪家、备选顺序、各家密钥)和当前文本模型。
const legacyImportVersion = 5;

/// 把旧版的 api.json(接口、推标模型)、cha_annotation.json(CHA 模型位)、vision_prompts.json
/// (系统提示词方案、推标提示词)并进 [cur]。只做还没做过的步骤;只填空位、不覆盖已有设置。
AppConfig importLegacy(
  AppConfig cur, {
  Map<String, dynamic>? api,
  Map<String, dynamic>? cha,
  Map<String, dynamic>? prompts,
  Map<String, dynamic>? app,
  Map<String, dynamic>? translate,
}) {
  var c = cur;
  if (cur.legacyImport < 1) c = _importApi(c, api, cha);
  if (cur.legacyImport < 2) c = _importPrompts(c, prompts);
  final token = api?['huggingface'] is Map ? (api!['huggingface'] as Map)['token'] : null;
  if (cur.legacyImport < 3 && c.hfToken.isEmpty && token is String) c = c.copyWith(hfToken: token.trim());
  final request = app?['request'];
  final n = request is Map ? request['concurrency'] : null;
  if (cur.legacyImport < 4 && n is int && n > 0) c = c.copyWith(parallel: n.clamp(1, maxParallel));
  if (cur.legacyImport < 5) c = _importTranslate(c, api, translate);
  return c.copyWith(legacyImport: legacyImportVersion);
}

/// 旧版 translate.json 的 provider / fallback_order(本地 Hy-MT2 还没做,跳过)+ api.json 的 translate 段密钥。
AppConfig _importTranslate(AppConfig cur, Map<String, dynamic>? api, Map<String, dynamic>? translate) {
  final byName = TranslateService.values.asNameMap();
  final creds = api?['translate'] is Map ? api!['translate'] as Map : const {};
  // 旧版是空的就不动,免得把新版已经填的冲掉。
  String? s(String k) => creds[k] is String && (creds[k] as String).trim().isNotEmpty ? (creds[k] as String).trim() : null;
  final llm = api?['llm'] is Map ? api!['llm'] as Map : const {};
  return cur.copyWith(
    translate: cur.translate.copyWith(
      service: byName[translate?['provider']],
      fallbacks: translate?['fallback_order'] is List ? [for (final f in translate!['fallback_order'] as List) ?byName[f]] : null,
      baiduAppid: s('baidu_appid'),
      baiduKey: s('baidu_key'),
      deeplKey: s('deepl_key'),
      deeplxUrl: s('deeplx_url'),
      deeplxToken: s('deeplx_token'),
      customBaseUrl: s('custom_base_url'),
      customKey: s('custom_api_key'),
      customModel: s('custom_model'),
    ),
    textModel: (cur.textModel ?? _ref(llm['text_target']),),
  );
}

/// 旧版的每套方案按原名导入;之前单条导进来的同一段文字换回旧版的名字。
AppConfig _importPrompts(AppConfig cur, Map<String, dynamic>? prompts) {
  final old = prompts?['prompts'] is Map ? prompts!['prompts'] as Map : const {};
  final merged = {...cur.systemPrompts};
  for (final MapEntry(:key, :value) in old.entries) {
    if (key is! String || value is! String || key.trim().isEmpty) continue;
    merged.removeWhere((k, v) => v == value && k != key);
    merged.putIfAbsent(key, () => value);
  }
  final names = cur.copyWith(systemPrompts: merged).systemNames;
  final active = prompts?['active'];
  final user = prompts?['user_prompt'];
  return cur.copyWith(
    systemPrompts: merged,
    // 正在用的方案还在就不动;没选或被合并掉了,换成旧版选中的那套。
    systemName: names.contains(cur.systemName) ? cur.systemName : active is String && names.contains(active) ? active : '',
    prompt: cur.prompt == defaultVisionPrompt && user is String && user.trim().isNotEmpty ? user : null,
  );
}

AppConfig _importApi(AppConfig cur, Map<String, dynamic>? api, Map<String, dynamic>? cha) {
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
  return cur.copyWith(
    profiles: [...cur.profiles, ...added],
    vision: cur.vision ?? _ref(llm['vision_target']),
    chaCards: [for (var i = 0; i < cur.chaCards.length; i++) cur.chaCards[i] ?? _ref(cards.elementAtOrNull(i))],
    chaScene: (cur.chaScene ?? _ref(cha?['batch_model']),),
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
    app: await _readJson('$appData${sep}NLapt${sep}config.json'),
    translate: await _readJson('$appData${sep}NLapt${sep}translate.json'),
  );
}
