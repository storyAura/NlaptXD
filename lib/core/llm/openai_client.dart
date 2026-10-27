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

/// OpenAI 兼容的 `/chat/completions` + `/models`,只用 dart:io。
class OpenAiClient {
  OpenAiClient(this.profile, {this.timeout = const Duration(seconds: 120)});

  final ApiProfile profile;
  final Duration timeout;

  Uri _url(String path) {
    final base = profile.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  /// 看图回答。[extra] 是跟在主图后面的参考图(CHA 的多图参考),按顺序是 Image 2、3…
  Future<String> caption({
    required String model,
    required String prompt,
    required List<int> image,
    required String mime,
    String system = '',
    List<ImagePart> extra = const [],
  }) async {
    final body = {
      'model': model,
      'messages': [
        if (system.trim().isNotEmpty) {'role': 'system', 'content': system},
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            for (final (bytes, type) in [(image, mime), for (final e in extra) (e.bytes, e.mime)])
              {
                'type': 'image_url',
                'image_url': {'url': 'data:$type;base64,${base64Encode(bytes)}'},
              },
          ],
        },
      ],
    };
    final reply = await _send('POST', '/chat/completions', body);
    final text = _content(reply).trim();
    if (text.isEmpty) throw const LlmError('模型返回了空内容(可能被安全策略拦截),原文未改');
    return text;
  }

  /// 「测试连接」:发一句最短的话,返回耗时。
  Future<Duration> ping(String model) async {
    final watch = Stopwatch()..start();
    await _send('POST', '/chat/completions', {
      'model': model,
      'max_tokens': 8,
      'messages': [
        {'role': 'user', 'content': 'Reply with the single word: ok'},
      ],
    });
    return watch.elapsed;
  }

  Future<List<String>> listModels() async {
    final reply = await _send('GET', '/models', null);
    final data = reply['data'];
    if (data is! List) throw const LlmError('接口没有返回模型列表');
    return [for (final m in data) if (m is Map && m['id'] is String) m['id'] as String]..sort();
  }

  Future<Map<String, dynamic>> _send(String method, String path, Object? body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.openUrl(method, _url(path)).timeout(timeout);
      req.headers.contentType = ContentType.json;
      if (profile.apiKey.trim().isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${profile.apiKey.trim()}');
      }
      if (body != null) req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(timeout);
      final raw = await utf8.decodeStream(res).timeout(timeout);
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
    } finally {
      client.close(force: true);
    }
  }

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

  static String _content(Map<String, dynamic> reply) {
    final choices = reply['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final content = (choices.first as Map)['message']?['content'];
    if (content is String) return content;
    if (content is List) {
      return content.map((p) => p is Map && p['text'] is String ? p['text'] as String : '').join();
    }
    return '';
  }
}

/// 按扩展名给图片的 MIME 类型。
String imageMime(String path) => switch (path.toLowerCase().split('.').last) {
  'jpg' || 'jpeg' => 'image/jpeg',
  'webp' => 'image/webp',
  'bmp' => 'image/bmp',
  _ => 'image/png',
};
