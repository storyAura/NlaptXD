import 'package:flutter/foundation.dart';

/// 接口格式(同旧版 api_type):OpenAI 兼容 / Anthropic Messages / Google Gemini(含 Vertex AI)。
enum ApiProtocol {
  openai('OpenAI', 'https://openrouter.ai/api/v1'),
  anthropic('Anthropic', 'https://api.anthropic.com'),
  gemini('Google', 'https://generativelanguage.googleapis.com');

  const ApiProtocol(this.label, this.defaultUrl);

  final String label;

  /// 新建接口时填的地址。
  final String defaultUrl;
}

/// 一个接口:OpenAI 兼容(OpenRouter、DeepSeek、硅基流动、llama-server、Ollama 的 /v1 都算)、
/// Anthropic 或 Google,看 [protocol]。
@immutable
class ApiProfile {
  const ApiProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    this.models = const [],
    this.enabled = true,
    this.protocol = ApiProtocol.openai,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;

  /// 用户勾选进模型池的模型。
  final List<String> models;
  final bool enabled;
  final ApiProtocol protocol;

  ApiProfile copyWith({String? name, String? baseUrl, String? apiKey, List<String>? models, bool? enabled, ApiProtocol? protocol}) =>
      ApiProfile(
        id: id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        models: models ?? this.models,
        enabled: enabled ?? this.enabled,
        protocol: protocol ?? this.protocol,
      );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'models': models,
    'enabled': enabled,
    'protocol': protocol.name,
  };

  factory ApiProfile.fromJson(Map<String, dynamic> j) => ApiProfile(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    baseUrl: j['baseUrl'] as String? ?? '',
    apiKey: j['apiKey'] as String? ?? '',
    models: [for (final m in j['models'] as List? ?? const []) m as String],
    enabled: j['enabled'] as bool? ?? true,
    protocol: ApiProtocol.values.asNameMap()[j['protocol']] ?? ApiProtocol.openai,
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
