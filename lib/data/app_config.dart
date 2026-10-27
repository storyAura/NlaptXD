import 'package:flutter/foundation.dart';

import '../core/llm/api_profile.dart';
import '../core/llm/llm_client.dart';
import '../core/llm/translate.dart';
import '../core/system_prompts.dart';

/// 同时发送的上限。
const maxParallel = 32;

/// 只有一条系统提示词的老 config.json 读进来时,放进这个名字的方案里。
const _singleSystemName = '系统提示词';

/// 存在「文档\NLaptXD\config.json」里的设置。整份不可变,改一项就换一份新的。
@immutable
class AppConfig {
  const AppConfig({
    this.profiles = const [],
    this.vision,
    this.chaCards = const [null, null, null],
    this.chaScene,
    this.darkMode = false,
    this.lastRoot = '',
    this.prompt = defaultVisionPrompt,
    this.systemPrompts = const {},
    this.systemName = '',
    this.legacyImport = 0,
    this.hfToken = '',
    this.parallel = 4,
    this.translate = const TranslateSettings(),
    this.textModel,
  });

  final List<ApiProfile> profiles;

  /// 推标用的视觉模型。
  final ModelRef? vision;

  /// CHA 三个人物卡候选各用哪个模型、整批画面用哪个;null = 沿用 [vision]。
  /// 接口 id 为 `local` 的是本地 GGUF 模型。
  final List<ModelRef?> chaCards;
  final ModelRef? chaScene;
  final bool darkMode;

  /// 上次打开的数据集,启动时自动重开。
  final String lastRoot;
  final String prompt;

  /// 用户存的系统提示词方案(名字 → 内容,按添加顺序);和内置方案同名时用户的优先。
  final Map<String, String> systemPrompts;

  /// 正在用的方案;空 = 不发系统提示词。
  final String systemName;

  /// 旧版 NLapt 的设置导入到第几步了(见 legacy_import.dart);每步只导一次,删掉的东西不会再冒出来。
  final int legacyImport;

  /// HuggingFace Token:下载受限模型(CL Tagger)用。和 API Key 一样存在这里(同旧版 api.json)。
  final String hfToken;

  /// 在线批量推标同时发几张(同旧版 config.json 的 request.concurrency,默认 4)。
  final int parallel;

  /// 翻译服务(含各家的密钥,同旧版 api.json 的 translate 段)。
  final TranslateSettings translate;

  /// 当前文本模型:翻译选「大模型」时用它。
  final ModelRef? textModel;

  /// 当前方案的内容。
  String get system => systemTextOf(systemName);

  String systemTextOf(String name) => systemPrompts[name] ?? builtinSystemPrompts[name] ?? '';

  /// 能选的方案名:内置的在前,再是用户自己的。
  List<String> get systemNames => [
    ...builtinSystemPrompts.keys,
    ...systemPrompts.keys.where((n) => !builtinSystemPrompts.containsKey(n)),
  ];

  /// 所有启用接口里勾选了的模型。
  List<ModelRef> get pool => [
    for (final p in profiles)
      if (p.enabled)
        for (final m in p.models) ModelRef(p.id, m),
  ];

  ApiProfile? profileOf(ModelRef? ref) {
    if (ref == null) return null;
    for (final p in profiles) {
      if (p.id == ref.profileId && p.enabled && p.models.contains(ref.model)) return p;
    }
    return null;
  }

  AppConfig copyWith({
    List<ApiProfile>? profiles,
    ModelRef? vision,
    bool clearVision = false,
    List<ModelRef?>? chaCards,
    (ModelRef?,)? chaScene,
    bool? darkMode,
    String? lastRoot,
    String? prompt,
    Map<String, String>? systemPrompts,
    String? systemName,
    int? legacyImport,
    String? hfToken,
    int? parallel,
    TranslateSettings? translate,
    (ModelRef?,)? textModel,
  }) => AppConfig(
    profiles: profiles ?? this.profiles,
    vision: clearVision ? null : vision ?? this.vision,
    chaCards: chaCards ?? this.chaCards,
    chaScene: chaScene == null ? this.chaScene : chaScene.$1,
    darkMode: darkMode ?? this.darkMode,
    lastRoot: lastRoot ?? this.lastRoot,
    prompt: prompt ?? this.prompt,
    systemPrompts: systemPrompts ?? this.systemPrompts,
    systemName: systemName ?? this.systemName,
    legacyImport: legacyImport ?? this.legacyImport,
    hfToken: hfToken ?? this.hfToken,
    parallel: parallel ?? this.parallel,
    translate: translate ?? this.translate,
    textModel: textModel == null ? this.textModel : textModel.$1,
  );

  Map<String, Object?> toJson() => {
    'profiles': [for (final p in profiles) p.toJson()],
    'vision': vision?.toJson(),
    'chaCards': [for (final r in chaCards) r?.toJson()],
    'chaScene': chaScene?.toJson(),
    'darkMode': darkMode,
    'lastRoot': lastRoot,
    'prompt': prompt,
    'systemPrompts': systemPrompts,
    'systemName': systemName,
    'legacyImport': legacyImport,
    'hfToken': hfToken,
    'parallel': parallel,
    'translate': translate.toJson(),
    'textModel': textModel?.toJson(),
  };

  factory AppConfig.fromJson(Map<String, dynamic> j) {
    // 老 config.json 只有一条 `system`:放进一个方案并选中它。
    final single = j['system'] as String? ?? '';
    final saved = j['systemPrompts'];
    final prompts = saved is Map
        ? {for (final MapEntry(:key, :value) in saved.entries) if (key is String && value is String) key: value}
        : {if (single.trim().isNotEmpty) _singleSystemName: single};
    return AppConfig(
      profiles: [
        for (final p in j['profiles'] as List? ?? const []) ApiProfile.fromJson(p as Map<String, dynamic>),
      ],
      vision: ModelRef.fromJson(j['vision']),
      chaCards: [for (var i = 0; i < 3; i++) ModelRef.fromJson((j['chaCards'] as List? ?? const []).elementAtOrNull(i))],
      chaScene: ModelRef.fromJson(j['chaScene']),
      darkMode: j['darkMode'] as bool? ?? false,
      lastRoot: j['lastRoot'] as String? ?? '',
      prompt: (j['prompt'] as String?)?.trim().isNotEmpty == true ? j['prompt'] as String : defaultVisionPrompt,
      systemPrompts: prompts,
      systemName: j['systemName'] as String? ?? (prompts.isEmpty ? '' : _singleSystemName),
      legacyImport: j['legacyImport'] as int? ?? (j['legacyImported'] == true ? 1 : 0),
      hfToken: j['hfToken'] as String? ?? '',
      parallel: ((j['parallel'] as int?) ?? 4).clamp(1, maxParallel),
      translate: j['translate'] is Map<String, dynamic> ? TranslateSettings.fromJson(j['translate'] as Map<String, dynamic>) : const TranslateSettings(),
      textModel: ModelRef.fromJson(j['textModel']),
    );
  }
}
