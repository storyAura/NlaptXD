import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/core/llm/api_profile.dart';
import 'package:nlaptxd/core/llm/llm_client.dart';

void main() {
  late HttpServer server;
  late Map<String, dynamic> lastBody;
  late String? lastAuth;
  late HttpHeaders lastHeaders;
  late String lastPath;
  var status = 200;
  Object reply = {};

  setUp(() async {
    status = 200;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      lastAuth = req.headers.value('authorization');
      lastHeaders = req.headers;
      lastPath = req.uri.toString();
      final raw = await utf8.decodeStream(req);
      lastBody = raw.isEmpty ? {} : jsonDecode(raw) as Map<String, dynamic>;
      req.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(reply is String ? reply : jsonEncode(reply));
      await req.response.close();
    });
  });
  tearDown(() => server.close(force: true));

  ApiProfile profile() => ApiProfile(
    id: 'p',
    name: 'test',
    baseUrl: 'http://127.0.0.1:${server.port}/v1/',
    apiKey: 'sk-1',
    models: const ['m'],
  );

  test('caption sends the image as a data URL and returns trimmed text', () async {
    reply = {
      'choices': [
        {'message': {'content': '  1girl, solo \n'}},
      ],
    };
    final client = LlmClient(profile());
    final text = await client.caption(
      model: 'm',
      prompt: 'Describe',
      image: [1, 2, 3],
      mime: 'image/png',
    );
    expect(text, '1girl, solo');
    expect(lastAuth, 'Bearer sk-1');
    final content = (lastBody['messages'] as List).last['content'] as List;
    expect(content.first, {'type': 'text', 'text': 'Describe'});
    expect(content.last['image_url']['url'], 'data:image/png;base64,AQID');
  });

  test('extra reference images follow the main image in order', () async {
    reply = {
      'choices': [
        {'message': {'content': 'ok'}},
      ],
    };
    await LlmClient(profile()).caption(
      model: 'm',
      prompt: 'p',
      image: [1],
      mime: 'image/png',
      extra: [(bytes: [2], mime: 'image/jpeg')],
    );
    final content = (lastBody['messages'] as List).last['content'] as List;
    expect(content.map((c) => c['image_url']?['url']).whereType<String>(), [
      'data:image/png;base64,AQ==',
      'data:image/jpeg;base64,Ag==',
    ]);
  });

  test('content given as parts is joined', () async {
    reply = {
      'choices': [
        {
          'message': {
            'content': [
              {'type': 'text', 'text': 'a, '},
              {'type': 'text', 'text': 'b'},
            ],
          },
        },
      ],
    };
    expect(
      await LlmClient(profile()).caption(model: 'm', prompt: 'p', image: [0], mime: 'image/png'),
      'a, b',
    );
  });

  test('an HTTP error becomes an LlmError with the status and message', () async {
    status = 401;
    reply = {'error': {'message': 'bad key'}};
    expect(
      () => LlmClient(profile()).caption(model: 'm', prompt: 'p', image: [0], mime: 'image/png'),
      throwsA(isA<LlmError>().having((e) => e.message, 'message', allOf(contains('401'), contains('bad key')))),
    );
  });

  test('an empty reply is an error, never an empty caption', () async {
    reply = {'choices': [{'message': {'content': ''}}]};
    expect(
      () => LlmClient(profile()).caption(model: 'm', prompt: 'p', image: [0], mime: 'image/png'),
      throwsA(isA<LlmError>()),
    );
  });

  test('listModels reads data[].id', () async {
    reply = {'data': [{'id': 'b'}, {'id': 'a'}]};
    expect(await LlmClient(profile()).listModels(), ['a', 'b']);
  });

  ApiProfile as(ApiProtocol protocol, String path) =>
      profile().copyWith(protocol: protocol, baseUrl: 'http://127.0.0.1:${server.port}$path');

  test('anthropic: /v1/messages, x-api-key, image blocks before the text, text blocks joined', () async {
    reply = {
      'content': [
        {'type': 'text', 'text': '1girl, '},
        {'type': 'text', 'text': 'solo'},
      ],
    };
    final text = await LlmClient(as(ApiProtocol.anthropic, '/api')).caption(model: 'claude', prompt: 'Describe', system: 'sys', image: [1, 2, 3], mime: 'image/png');
    expect(text, '1girl, solo');
    expect(lastPath, '/api/v1/messages');
    expect((lastHeaders.value('x-api-key'), lastHeaders.value('anthropic-version'), lastAuth), ('sk-1', '2023-06-01', null));
    expect(lastBody['system'], 'sys');
    final content = (lastBody['messages'] as List).single['content'] as List;
    expect(content.first['source'], {'type': 'base64', 'media_type': 'image/png', 'data': 'AQID'});
    expect(content.last, {'type': 'text', 'text': 'Describe'});

    reply = {'data': [{'id': 'claude-b'}, {'id': 'claude-a'}]};
    expect(await LlmClient(as(ApiProtocol.anthropic, '/v1/')).listModels(), ['claude-a', 'claude-b']);
    expect(lastPath, '/v1/models', reason: '地址已带 /v1 就不再加');
  });

  test('google: generateContent under /v1beta, x-goog-api-key, inline_data, skips thought parts', () async {
    reply = {
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': 'thinking…', 'thought': true},
              {'text': 'purple hair'},
            ],
          },
        },
      ],
    };
    final text = await LlmClient(as(ApiProtocol.gemini, '')).caption(model: 'models/gemini-x', prompt: 'p', system: 's', image: [1], mime: 'image/jpeg');
    expect(text, 'purple hair');
    expect(lastPath, '/v1beta/models/gemini-x:generateContent');
    expect(lastHeaders.value('x-goog-api-key'), 'sk-1');
    expect((lastBody['contents'] as List).single['parts'][1], {'inline_data': {'mime_type': 'image/jpeg', 'data': 'AQ=='}});
    expect(lastBody['systemInstruction'], {'parts': [{'text': 's'}]});

    reply = {
      'models': [
        {'name': 'models/gemini-b', 'supportedGenerationMethods': ['generateContent']},
        {'name': 'models/embed', 'supportedGenerationMethods': ['embedContent']},
        {'name': 'models/gemini-a', 'supportedGenerationMethods': ['generateContent']},
      ],
    };
    expect(await LlmClient(as(ApiProtocol.gemini, '/v1')).listModels(), ['gemini-a', 'gemini-b']);
    expect(lastPath, '/v1/models?pageSize=1000');
  });

  test('google: a blocked prompt explains why; vertex urls go through publishers/google and have no model list', () async {
    reply = {'promptFeedback': {'blockReason': 'SAFETY'}};
    expect(
      () => LlmClient(as(ApiProtocol.gemini, '')).caption(model: 'g', prompt: 'p', image: [0], mime: 'image/png'),
      throwsA(isA<LlmError>().having((e) => e.message, 'm', contains('SAFETY'))),
    );
    expect(geminiGenerateUrl('https://aiplatform.googleapis.com/v1', 'gemini-4').toString(),
        'https://aiplatform.googleapis.com/v1/publishers/google/models/gemini-4:generateContent');
    expect(
      () => LlmClient(ApiProfile(id: 'v', name: 'v', baseUrl: 'https://aiplatform.googleapis.com/v1', apiKey: 'k', protocol: ApiProtocol.gemini)).listModels(),
      throwsA(isA<LlmError>().having((e) => e.message, 'm', contains('手动'))),
    );
  });

  test('ApiProfile round-trips through JSON', () {
    final p = profile().copyWith(protocol: ApiProtocol.gemini);
    expect(ApiProfile.fromJson(p.toJson()).toJson(), p.toJson());
    expect(ApiProfile.fromJson({'id': 'old'}).protocol, ApiProtocol.openai, reason: '老配置没有 protocol 就是 OpenAI');
  });
}
