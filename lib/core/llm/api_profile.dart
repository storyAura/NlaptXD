import 'package:flutter/foundation.dart';

/// 一个 OpenAI 兼容接口(OpenRouter、DeepSeek、硅基流动、llama-server、Ollama 的 /v1 都算)。
@immutable
class ApiProfile {
  const ApiProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    this.models = const [],
    this.enabled = true,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;

  /// 用户勾选进模型池的模型。
  final List<String> models;
  final bool enabled;

  ApiProfile copyWith({String? name, String? baseUrl, String? apiKey, List<String>? models, bool? enabled}) =>
      ApiProfile(
        id: id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        models: models ?? this.models,
        enabled: enabled ?? this.enabled,
      );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'models': models,
    'enabled': enabled,
  };

  factory ApiProfile.fromJson(Map<String, dynamic> j) => ApiProfile(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    baseUrl: j['baseUrl'] as String? ?? '',
    apiKey: j['apiKey'] as String? ?? '',
    models: [for (final m in j['models'] as List? ?? const []) m as String],
    enabled: j['enabled'] as bool? ?? true,
  );
}

/// 模型池里的一项:哪个接口的哪个模型。
@immutable
class ModelRef {
  const ModelRef(this.profileId, this.model);

  final String profileId;
  final String model;

  Map<String, String> toJson() => {'profile': profileId, 'model': model};

  static ModelRef? fromJson(Object? j) =>
      j is Map && j['profile'] is String && j['model'] is String ? ModelRef(j['profile'] as String, j['model'] as String) : null;

  @override
  bool operator ==(Object other) => other is ModelRef && other.profileId == profileId && other.model == model;

  @override
  int get hashCode => Object.hash(profileId, model);
}
