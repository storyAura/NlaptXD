import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api_profile.dart';

/// 旧版 NLapt 的默认看图指令(用户提示词留空时用)。
const defaultVisionPrompt =
    'Describe this image in a detailed, objective natural language paragraph '
    'suitable for image-generation training. Reply with the caption text only.';

/// 随请求发出的一张图。
typedef ImagePart = ({List<int> bytes, String mime});

/// 接口出错。[message] 直接给用户看:短、中文、不带堆栈。
class LlmError implements Exception {
  const LlmError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 三种格式的接口,只用 dart:io。移植自旧版 NLapt 的 nlapt/llm/{openai,anthropic,gemini}_client.py 和 model_list.py:
/// - OpenAI 兼容:`{地址}/chat/completions`、`/models`,Bearer。
/// - Anthropic:`{地址}/v1/messages`、`/v1/models`(地址已带 /v1 就不再加),x-api-key。
/// - Google:`{地址}/v1beta/models/{模型}:generateContent`(地址已带版本就不再加;Vertex AI 的地址再加
///   `/publishers/google`),x-goog-api-key。Vertex 没有模型列表,要手动加模型 ID。
class LlmClient {
  LlmClient(this.profile, {this.timeout = const Duration(seconds: 120)});

  final ApiProfile profile;
  final Duration timeout;

  String get _base => profile.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  String get _key => profile.apiKey.trim();

  /// 看图回答。[extra] 是跟在主图后面的参考图(CHA 的多图参考),按顺序是 Image 2、3…
  Future<String> caption({
    required String model,
    required String prompt,
    required List<int> image,
    required String mime,
    String system = '',
    List<ImagePart> extra = const [],
  }) async {
    final text = (await _complete(model, prompt, system, [(bytes: image, mime: mime), ...extra])).trim();
    if (text.isEmpty) throw const LlmError('模型返回了空内容(可能被安全策略拦截),原文未改');
    return text;
  }

  /// 只发文字(翻译用)。
  Future<String> chat({required String model, required String prompt, String system = ''}) async {
    final text = (await _complete(model, prompt, system, const [])).trim();
    if (text.isEmpty) throw LlmError('${profile.name} 返回了空内容');
    return text;
  }

  /// 「测试连接」:发一句最短的话,接口没报错就算通(不看回答:有的模型先思考,几个字的额度出不了正文)。
  Future<Duration> ping(String model) async {
    final watch = Stopwatch()..start();
    await _complete(model, 'Reply with the single word: ok', '', const [], ping: true);
    return watch.elapsed;
  }

  Future<List<String>> listModels() async {
    final ids = switch (profile.protocol) {
      ApiProtocol.openai => _send('GET', Uri.parse('$_base/models'), null).then((r) => _ids(r, 'data', 'id')),
      ApiProtocol.anthropic => _send('GET', Uri.parse('${_anthropicRoot()}/models'), null).then((r) => _ids(r, 'data', 'id')),
      ApiProtocol.gemini => _geminiModels(),
    };
    return [...await ids]..sort();
  }

  Future<String> _complete(String model, String prompt, String system, List<ImagePart> images, {bool ping = false}) async {
    switch (profile.protocol) {
      case ApiProtocol.openai:
        final reply = await _send('POST', Uri.parse('$_base/chat/completions'), {
          'model': model,
          if (ping) 'max_tokens': 8,
          'messages': [
            if (system.trim().isNotEmpty) {'role': 'system', 'content': system},
            {
              'role': 'user',
              'content': images.isEmpty
                  ? prompt
                  : [
                      {'type': 'text', 'text': prompt},
                      for (final i in images)
                        {
                          'type': 'image_url',
                          'image_url': {'url': 'data:${i.mime};base64,${base64Encode(i.bytes)}'},
                        },
                    ],
            },
          ],
        });
        return ping ? '' : _openAiText(reply);
      case ApiProtocol.anthropic:
        final reply = await _send('POST', Uri.parse('${_anthropicRoot()}/messages'), {
          'model': model,
          'max_tokens': ping ? 8 : 4096,
          if (system.trim().isNotEmpty) 'system': system,
          'messages': [
            {
              'role': 'user',
              'content': [
                for (final i in images)
                  {
                    'type': 'image',
                    'source': {'type': 'base64', 'media_type': i.mime, 'data': base64Encode(i.bytes)},
                  },
                {'type': 'text', 'text': prompt},
              ],
            },
          ],
        });
        return ping ? '' : _anthropicText(reply);
      case ApiProtocol.gemini:
        final url = geminiGenerateUrl(_base, model);
        final reply = await _send('POST', url, {
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': prompt},
                for (final i in images)
                  {
                    'inline_data': {'mime_type': i.mime, 'data': base64Encode(i.bytes)},
                  },
              ],
            },
          ],
          if (system.trim().isNotEmpty)
            'systemInstruction': {
              'parts': [
                {'text': system},
              ],
            },
        }, notFound: '找不到 $url(检查地址和模型名)');
        return ping ? '' : _geminiText(reply);
    }
  }

  String _anthropicRoot() => _base.endsWith('/v1') ? _base : '$_base/v1';

  Future<List<String>> _geminiModels() async {
    if (isVertex(_base)) throw const LlmError('Vertex AI 不提供模型列表,请手动添加模型 ID(如 gemini-2.5-flash)');
    final reply = await _send('GET', Uri.parse('${geminiRoot(_base)}/models?pageSize=1000'), null);
    final models = reply['models'];
    if (models is! List) throw const LlmError('接口没有返回模型列表');
    return [
      for (final m in models)
        if (m is Map && m['name'] is String && (m['supportedGenerationMethods'] as List? ?? const []).contains('generateContent'))
          stripModelPrefix(m['name'] as String),
    ];
  }

  Map<String, String> get _headers => switch (profile.protocol) {
    ApiProtocol.openai => {if (_key.isNotEmpty) HttpHeaders.authorizationHeader: 'Bearer $_key'},
    ApiProtocol.anthropic => {'anthropic-version': '2023-06-01', if (_key.isNotEmpty) 'x-api-key': _key},
    ApiProtocol.gemini => {if (_key.isNotEmpty) 'x-goog-api-key': _key},
  };

  Future<Map<String, dynamic>> _send(String method, Uri url, Object? body, {String? notFound}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.openUrl(method, url).timeout(timeout);
      req.headers.contentType = ContentType.json;
      _headers.forEach(req.headers.set);
      if (body != null) req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(timeout);
      final raw = await utf8.decodeStream(res).timeout(timeout);
      if (res.statusCode == 404 && notFound != null) throw LlmError('${profile.name} 404:$notFound');
      if (res.statusCode >= 400) throw LlmError('${profile.name} ${res.statusCode}:${_errorText(raw)}');
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) throw const LlmError('接口返回的不是 JSON 对象');
      return json;
    } on TimeoutException {
      throw LlmError('${profile.name} 超时(${timeout.inSeconds} 秒)');
    } on SocketException catch (e) {
      throw LlmError('连不上 ${profile.name}:${e.osError?.message ?? e.message}');
    } on FormatException {
      throw LlmError('${profile.name} 返回的内容无法解析');
    } on ArgumentError {
      throw LlmError('${profile.name} 的地址不对:$url');
    } finally {
      client.close(force: true);
    }
  }

  /// 三家的出错格式都是 {"error": {"message": …}} 或 {"error": "…"}。
  static String _errorText(String raw) {
    try {
      final j = jsonDecode(raw);
      final msg = j is Map ? (j['error'] is Map ? j['error']['message'] : j['error'] ?? j['message']) : null;
      if (msg is String && msg.isNotEmpty) return msg;
    } on FormatException {
      // 不是 JSON:截一段原文。
    }
    return raw.length > 160 ? '${raw.substring(0, 160)}…' : raw;
  }

  static List<String> _ids(Map<String, dynamic> reply, String list, String id) {
    final data = reply[list];
    if (data is! List) throw const LlmError('接口没有返回模型列表');
    return [for (final m in data) if (m is Map && m[id] is String) m[id] as String];
  }

  static String _openAiText(Map<String, dynamic> reply) {
    final choices = reply['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final content = (choices.first as Map)['message']?['content'];
    if (content is String) return content;
    if (content is List) {
      return content.map((p) => p is Map && p['text'] is String ? p['text'] as String : '').join();
    }
    return '';
  }

  static String _anthropicText(Map<String, dynamic> reply) => [
    for (final b in reply['content'] as List? ?? const [])
      if (b is Map && b['type'] == 'text' && b['text'] is String) b['text'] as String,
  ].join();

  /// 只要正文,跳过思考段;整段被拦时说明原因。
  static String _geminiText(Map<String, dynamic> reply) {
    final candidates = reply['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      final reason = (reply['promptFeedback'] as Map?)?['blockReason'];
      throw LlmError(reason != null ? 'Google 拦下了这次请求:$reason' : 'Google 没有返回结果');
    }
    final first = candidates.first as Map;
    final text = [
      for (final p in (first['content'] as Map?)?['parts'] as List? ?? const [])
        if (p is Map && p['text'] is String && p['thought'] != true) p['text'] as String,
    ].join();
    if (text.isEmpty) throw LlmError('Google 没有返回正文(${first['finishReason'] ?? '无内容'})');
    return text;
  }
}

/// Vertex AI(含 {region}-aiplatform…)而不是 Gemini Developer API。
bool isVertex(String baseUrl) => baseUrl.contains('aiplatform.googleapis.com');

/// 带上版本号的根地址:地址末尾已经是 /v1、/v1beta 这类就不再加,否则加 /v1beta。
String geminiRoot(String baseUrl) {
  final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  return RegExp(r'/v\d+(beta|alpha)?\d*$').hasMatch(trimmed) ? trimmed : '$trimmed/v1beta';
}

/// `models/gemini-x` → `gemini-x`(模型列表返回带前缀的写法)。
String stripModelPrefix(String model) => model.startsWith('models/') ? model.substring(7) : model;

/// generateContent 的完整地址;Vertex 的模型要写成 publishers/google/models/{id}。
Uri geminiGenerateUrl(String baseUrl, String model) {
  var root = geminiRoot(baseUrl);
  if (isVertex(baseUrl) && !root.contains('/publishers/google')) root += '/publishers/google';
  return Uri.parse('$root/models/${stripModelPrefix(model)}:generateContent');
}

/// 按扩展名给图片的 MIME 类型。
String imageMime(String path) => switch (path.toLowerCase().split('.').last) {
  'jpg' || 'jpeg' => 'image/jpeg',
  'webp' => 'image/webp',
  'bmp' => 'image/bmp',
  _ => 'image/png',
};
