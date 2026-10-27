import 'package:flutter/foundation.dart';

import '../core/llm/api_profile.dart';
import '../core/llm/openai_client.dart';

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
    this.system = '',
    this.legacyImported = false,
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
  final String system;

  /// 旧版 NLapt 的设置导入过了(只导一次,之后删掉的接口不会再冒出来)。
  final bool legacyImported;

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
    String? system,
    bool? legacyImported,
  }) => AppConfig(
    profiles: profiles ?? this.profiles,
    vision: clearVision ? null : vision ?? this.vision,
    chaCards: chaCards ?? this.chaCards,
    chaScene: chaScene == null ? this.chaScene : chaScene.$1,
    darkMode: darkMode ?? this.darkMode,
    lastRoot: lastRoot ?? this.lastRoot,
    prompt: prompt ?? this.prompt,
    system: system ?? this.system,
    legacyImported: legacyImported ?? this.legacyImported,
  );

  Map<String, Object?> toJson() => {
    'profiles': [for (final p in profiles) p.toJson()],
    'vision': vision?.toJson(),
    'chaCards': [for (final r in chaCards) r?.toJson()],
    'chaScene': chaScene?.toJson(),
    'darkMode': darkMode,
    'lastRoot': lastRoot,
    'prompt': prompt,
    'system': system,
    'legacyImported': legacyImported,
  };

  factory AppConfig.fromJson(Map<String, dynamic> j) => AppConfig(
    profiles: [
      for (final p in j['profiles'] as List? ?? const []) ApiProfile.fromJson(p as Map<String, dynamic>),
    ],
    vision: ModelRef.fromJson(j['vision']),
    chaCards: [for (var i = 0; i < 3; i++) ModelRef.fromJson((j['chaCards'] as List? ?? const []).elementAtOrNull(i))],
    chaScene: ModelRef.fromJson(j['chaScene']),
    darkMode: j['darkMode'] as bool? ?? false,
    lastRoot: j['lastRoot'] as String? ?? '',
    prompt: (j['prompt'] as String?)?.trim().isNotEmpty == true ? j['prompt'] as String : defaultVisionPrompt,
    system: j['system'] as String? ?? '',
    legacyImported: j['legacyImported'] as bool? ?? false,
  );
}
