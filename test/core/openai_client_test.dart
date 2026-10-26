import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/core/llm/api_profile.dart';
import 'package:nlaptxd/core/llm/openai_client.dart';

void main() {
  late HttpServer server;
  late Map<String, dynamic> lastBody;
  late String? lastAuth;
  var status = 200;
  Object reply = {};

  setUp(() async {
    status = 200;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      lastAuth = req.headers.value('authorization');
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
    final client = OpenAiClient(profile());
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
      await OpenAiClient(profile()).caption(model: 'm', prompt: 'p', image: [0], mime: 'image/png'),
      'a, b',
    );
  });

  test('an HTTP error becomes an LlmError with the status and message', () async {
    status = 401;
    reply = {'error': {'message': 'bad key'}};
    expect(
      () => OpenAiClient(profile()).caption(model: 'm', prompt: 'p', image: [0], mime: 'image/png'),
      throwsA(isA<LlmError>().having((e) => e.message, 'message', allOf(contains('401'), contains('bad key')))),
    );
  });

  test('an empty reply is an error, never an empty caption', () async {
    reply = {'choices': [{'message': {'content': ''}}]};
    expect(
      () => OpenAiClient(profile()).caption(model: 'm', prompt: 'p', image: [0], mime: 'image/png'),
      throwsA(isA<LlmError>()),
    );
  });

  test('listModels reads data[].id', () async {
    reply = {'data': [{'id': 'b'}, {'id': 'a'}]};
    expect(await OpenAiClient(profile()).listModels(), ['a', 'b']);
  });

  test('ApiProfile round-trips through JSON', () {
    final p = profile();
    expect(ApiProfile.fromJson(p.toJson()).toJson(), p.toJson());
  });
}
