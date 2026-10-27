import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'api_profile.dart';
import 'cleaning.dart';
import 'llm_client.dart';

/// 翻译服务:大模型 / Google / 百度 / DeepL / DeepLX / 自定义 OpenAI 兼容,按顺序备选。
/// 移植自旧版 NLapt 的 nlapt/llm/translate.py、web_translate.py、fallback.py。译文只用来对照或预览,
/// 写不写进标注由界面决定。

enum TranslateService {
  llm('大模型'),
  google('Google(免费)'),
  baidu('百度翻译'),
  deepl('DeepL'),
  deeplx('DeepLX(免费)'),
  custom('自定义 OpenAI 兼容');

  const TranslateService(this.label);

  final String label;
}

/// 目标语言:中文 / 英文 / 日文。
const translateLangs = {'zh': '中文', 'en': 'English', 'ja': '日本語'};

@immutable
class TranslateSettings {
  const TranslateSettings({
    this.service = TranslateService.google,
    this.fallbacks = const [],
    this.baiduAppid = '',
    this.baiduKey = '',
    this.deeplKey = '',
    this.deeplxUrl = '',
    this.deeplxToken = '',
    this.customBaseUrl = '',
    this.customKey = '',
    this.customModel = '',
  });

  final TranslateService service;

  /// 首选失败(或没配好)时依次试的。
  final List<TranslateService> fallbacks;
  final String baiduAppid, baiduKey, deeplKey, deeplxUrl, deeplxToken, customBaseUrl, customKey, customModel;

  List<TranslateService> get chain => [service, ...fallbacks.where((s) => s != service).toSet()];

  TranslateSettings copyWith({
    TranslateService? service,
    List<TranslateService>? fallbacks,
    String? baiduAppid,
    String? baiduKey,
    String? deeplKey,
    String? deeplxUrl,
    String? deeplxToken,
    String? customBaseUrl,
    String? customKey,
    String? customModel,
  }) => TranslateSettings(
    service: service ?? this.service,
    fallbacks: fallbacks ?? this.fallbacks,
    baiduAppid: baiduAppid ?? this.baiduAppid,
    baiduKey: baiduKey ?? this.baiduKey,
    deeplKey: deeplKey ?? this.deeplKey,
    deeplxUrl: deeplxUrl ?? this.deeplxUrl,
    deeplxToken: deeplxToken ?? this.deeplxToken,
    customBaseUrl: customBaseUrl ?? this.customBaseUrl,
    customKey: customKey ?? this.customKey,
    customModel: customModel ?? this.customModel,
  );

  Map<String, Object> toJson() => {
    'service': service.name,
    'fallbacks': [for (final s in fallbacks) s.name],
    'baiduAppid': baiduAppid,
    'baiduKey': baiduKey,
    'deeplKey': deeplKey,
    'deeplxUrl': deeplxUrl,
    'deeplxToken': deeplxToken,
    'customBaseUrl': customBaseUrl,
    'customKey': customKey,
    'customModel': customModel,
  };

  factory TranslateSettings.fromJson(Map<String, dynamic> j) {
    String s(String k) => j[k] is String ? j[k] as String : '';
    final byName = TranslateService.values.asNameMap();
    return TranslateSettings(
      service: byName[j['service']] ?? TranslateService.google,
      fallbacks: [for (final f in j['fallbacks'] as List? ?? const []) ?byName[f]],
      baiduAppid: s('baiduAppid'),
      baiduKey: s('baiduKey'),
      deeplKey: s('deeplKey'),
      deeplxUrl: s('deeplxUrl'),
      deeplxToken: s('deeplxToken'),
      customBaseUrl: s('customBaseUrl'),
      customKey: s('customKey'),
      customModel: s('customModel'),
    );
  }
}

/// 某个服务没配好:备选时跳过它。
class TranslateConfigError extends LlmError {
  const TranslateConfigError(super.message);
}

bool _isCjk(int r) => (r >= 0x4E00 && r <= 0x9FFF) || (r >= 0x3400 && r <= 0x4DBF) || (r >= 0xF900 && r <= 0xFAFF);

/// 中日韩汉字占三成以上就当中文(旧版 detect_direction):自动翻译时中文译成英文,其余译成中文。
String autoTarget(String text) {
  final chars = text.runes.where((r) => String.fromCharCode(r).trim().isNotEmpty).toList();
  if (chars.isEmpty) return 'zh';
  final cjk = chars.where(_isCjk);
  return cjk.length / chars.length >= .3 ? 'en' : 'zh';
}

const _langNames = {'zh': 'Simplified Chinese', 'en': 'English', 'ja': 'Japanese'};
const _googleLang = {'zh': 'zh-CN', 'en': 'en', 'ja': 'ja'};
const _baiduLang = {'zh': 'zh', 'en': 'en', 'ja': 'jp'};
const _deeplLang = {'zh': 'ZH', 'en': 'EN-US', 'ja': 'JA'};
const _deeplxLang = {'zh': 'ZH', 'en': 'EN', 'ja': 'JA'};

/// 大模型翻译的提示词(旧版 templates.py 的 translate_to_*)。
String llmTranslatePrompt(String text, String lang) =>
    'Translate the following image caption into ${_langNames[lang]}. '
    'Keep the meaning, tag structure and comma separation intact.\n\nCaption: $text';
const llmTranslateSystem = 'Output only the final caption text. No explanations, quotes, or code blocks.';

/// 用「大模型」翻译:给提示词和系统提示词,拿回模型的回答。界面按当前文本模型给出;没配好为 null。
typedef LlmChat = Future<String> Function(String prompt, String system);

class Translator {
  Translator(this.settings, {this.llm, this.sleep = _realSleep});

  final TranslateSettings settings;
  final LlmChat? llm;

  /// 重试前等一等;测试里换成不等的。
  final Future<void> Function(Duration) sleep;

  static Future<void> _realSleep(Duration d) => Future<void>.delayed(d);

  /// 同样的文字只翻一次(按内容缓存,同旧版)。
  static final _cache = <String, String>{};
  static const _cacheLimit = 2000;

  /// DeepLX 社区实例限流:两次请求至少隔 1 秒(整个程序共用)。
  static DateTime _deeplxLast = DateTime.fromMillisecondsSinceEpoch(0);

  /// 译成 [lang](zh / en / ja)。首选不行就按备选顺序试;没配好的跳过。都不行抛最后一个错。
  Future<String> translate(String text, String lang) async {
    final src = text.trim();
    if (src.isEmpty) return '';
    final key = '$lang\u0000$src';
    if (_cache[key] case final hit?) return hit;
    LlmError? last;
    for (final s in settings.chain) {
      try {
        final out = (await translateWith(s, src, lang)).trim();
        if (out.isEmpty) {
          last = LlmError('${s.label}没有返回译文');
          continue;
        }
        if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
        return _cache[key] = out;
      } on LlmError catch (e) {
        last = e;
      }
    }
    throw last is TranslateConfigError && settings.chain.length == 1 ? last : LlmError('翻译失败:${last?.message ?? '没有可用的翻译服务'}');
  }

  /// 只用 [s] 翻(「测试翻译」用;备选链也走这里)。
  Future<String> translateWith(TranslateService s, String text, String lang) => switch (s) {
    TranslateService.llm => _llm(text, lang),
    TranslateService.google => _google(text, lang),
    TranslateService.baidu => _baidu(text, lang),
    TranslateService.deepl => _deepl(text, lang),
    TranslateService.deeplx => _deeplx(text, lang),
    TranslateService.custom => _custom(text, lang),
  };

  Future<String> _llm(String text, String lang) async {
    final chat = llm;
    if (chat == null) throw const TranslateConfigError('大模型翻译要先在「模型」页选当前文本模型');
    return unwrapReply(await chat(llmTranslatePrompt(text, lang), llmTranslateSystem));
  }

  Future<String> _google(String text, String lang) async {
    final url = Uri.https('translate.googleapis.com', '/translate_a/single', {
      'client': 'gtx',
      'sl': 'auto',
      'tl': _googleLang[lang]!,
      'dt': 't',
      'q': text,
    });
    for (var attempt = 0; ; attempt++) {
      final (code, body) = await _http('GET', url, name: 'Google 翻译');
      if (code == 429 && attempt < 2) {
        await sleep(Duration(milliseconds: 500 * (attempt + 1)));
        continue;
      }
      if (code >= 400) throw LlmError('Google 翻译返回 HTTP $code');
      return parseGoogle(_json(body, 'Google 翻译'));
    }
  }

  Future<String> _baidu(String text, String lang) async {
    final (appid, key) = (settings.baiduAppid.trim(), settings.baiduKey.trim());
    if (appid.isEmpty || key.isEmpty) throw const TranslateConfigError('百度翻译要填 APPID 和密钥(fanyi-api.baidu.com)');
    final salt = '${math.Random().nextInt(1 << 31)}';
    final (code, body) = await _http(
      'POST',
      Uri.https('fanyi-api.baidu.com', '/api/trans/vip/translate'),
      name: '百度翻译',
      form: {'q': text, 'from': 'auto', 'to': _baiduLang[lang]!, 'appid': appid, 'salt': salt, 'sign': baiduSign(appid, text, salt, key)},
    );
    if (code >= 400) throw LlmError('百度翻译返回 HTTP $code');
    return parseBaidu(_json(body, '百度翻译'));
  }

  Future<String> _deepl(String text, String lang) async {
    final key = settings.deeplKey.trim();
    if (key.isEmpty) throw const TranslateConfigError('DeepL 要填 API Key(deepl.com/pro-api)');
    final (code, body) = await _http(
      'POST',
      Uri.https('api-free.deepl.com', '/v2/translate'),
      name: 'DeepL',
      headers: {'Authorization': 'DeepL-Auth-Key $key'},
      form: {'text': text, 'target_lang': _deeplLang[lang]!},
    );
    if (code >= 400) throw LlmError('DeepL 返回 HTTP $code');
    return parseDeepl(_json(body, 'DeepL'));
  }

  Future<String> _deeplx(String text, String lang) async {
    final base = settings.deeplxUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) throw const TranslateConfigError('DeepLX 要填实例地址(自建或 deeplx.owo.network 的免费实例)');
    final url = Uri.parse(base.split('?').first.endsWith('/translate') ? base : '$base/translate');
    final token = settings.deeplxToken.trim();
    for (var attempt = 0; ; attempt++) {
      final wait = _deeplxLast.add(const Duration(seconds: 1)).difference(DateTime.now());
      if (wait > Duration.zero) await sleep(wait);
      _deeplxLast = DateTime.now();
      final (code, body) = await _http(
        'POST',
        url,
        name: 'DeepLX',
        headers: {if (token.isNotEmpty) 'Authorization': 'Bearer $token'},
        json: {'text': text, 'source_lang': 'auto', 'target_lang': _deeplxLang[lang]!},
      );
      final busy = {418, 429, 503}.contains(code);
      if (busy && attempt < 3) {
        await sleep(Duration(seconds: 1 << attempt));
        continue;
      }
      if (busy) throw const LlmError('DeepLX 请求过于频繁,请稍后再试或换用自建实例');
      if (code >= 400) throw LlmError('DeepLX 返回 HTTP $code');
      return parseDeeplx(_json(body, 'DeepLX'));
    }
  }

  Future<String> _custom(String text, String lang) async {
    if (settings.customBaseUrl.trim().isEmpty || settings.customModel.trim().isEmpty) {
      throw const TranslateConfigError('自定义翻译要填 Base URL 和模型');
    }
    final client = LlmClient(
      ApiProfile(id: 'translate', name: '自定义翻译', baseUrl: settings.customBaseUrl, apiKey: settings.customKey),
      timeout: const Duration(seconds: 60),
    );
    return unwrapReply(await client.chat(
      model: settings.customModel.trim(),
      system: 'You translate image-caption tags. Output only the translation. Keep comma-separated tag structure. No quotes or commentary.',
      prompt: 'Translate into ${_langNames[lang]}:\n\n$text',
    ));
  }
}

Object? _json(String body, String name) {
  try {
    return jsonDecode(body);
  } on FormatException {
    throw LlmError('$name 返回的内容无法解析');
  }
}

Future<(int, String)> _http(
  String method,
  Uri url, {
  required String name,
  Map<String, String> headers = const {},
  Map<String, String>? form,
  Object? json,
}) async {
  const timeout = Duration(seconds: 15);
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.openUrl(method, url).timeout(timeout);
    headers.forEach(req.headers.set);
    if (form != null) {
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.add(utf8.encode(Uri(queryParameters: form).query));
    } else if (json != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(json)));
    }
    final res = await req.close().timeout(timeout);
    return (res.statusCode, await utf8.decodeStream(res).timeout(timeout));
  } on TimeoutException {
    throw LlmError('$name 超时');
  } on SocketException catch (e) {
    throw LlmError('连不上 $name:${e.osError?.message ?? e.message}');
  } on HttpException catch (e) {
    throw LlmError('$name 请求失败:${e.message}');
  } finally {
    client.close(force: true);
  }
}

String baiduSign(String appid, String q, String salt, String key) => md5.convert(utf8.encode('$appid$q$salt$key')).toString();

String parseGoogle(Object? data) {
  if (data is! List || data.isEmpty || data.first is! List) throw const LlmError('Google 翻译响应结构异常');
  final out = [for (final seg in data.first as List) if (seg is List && seg.isNotEmpty && seg.first is String) seg.first as String].join().trim();
  if (out.isEmpty) throw const LlmError('Google 翻译没有返回译文');
  return out;
}

String parseBaidu(Object? data) {
  if (data is! Map) throw const LlmError('百度翻译响应结构异常');
  if (data['error_code'] case final code? when '$code' != '52000') throw LlmError('百度翻译错误 $code:${data['error_msg'] ?? ''}');
  final out = [for (final r in data['trans_result'] as List? ?? const []) if (r is Map && '${r['dst'] ?? ''}'.isNotEmpty) '${r['dst']}'].join('\n').trim();
  if (out.isEmpty) throw const LlmError('百度翻译没有返回译文');
  return out;
}

String parseDeepl(Object? data) {
  if (data is! Map) throw const LlmError('DeepL 响应结构异常');
  final out = [for (final t in data['translations'] as List? ?? const []) if (t is Map && '${t['text'] ?? ''}'.isNotEmpty) '${t['text']}'].join('\n').trim();
  if (out.isEmpty) throw const LlmError('DeepL 没有返回译文');
  return out;
}

String parseDeeplx(Object? data) {
  if (data is! Map) throw const LlmError('DeepLX 响应结构异常');
  final code = data['code'];
  if (code != null && code != 200) throw LlmError('DeepLX 错误 $code ${data['message'] ?? data['msg'] ?? ''}'.trim());
  final out = data['data'];
  if (out is String && out.trim().isNotEmpty) return out.trim();
  throw const LlmError('DeepLX 没有返回译文');
}
