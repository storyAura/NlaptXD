// 「llama-server」「下载」两组测试和两个假件原样取自 Penna 的 test/local_test.dart、fixtures.dart。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/core/local/download.dart';
import 'package:nlaptxd/core/local/llama_server.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('nlx_local'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('llama-server', () {
    test('参数:-1 层是全部放进显卡,有视觉组件才带 --mmproj', () {
      final spec = (
        exe: 'a.exe',
        model: 'm.gguf',
        mmproj: 'p.gguf',
        port: 9000,
        context: 2048,
        gpuLayers: -1,
      );
      final args = serverArgs(spec);
      expect(args.join(' '), contains('-ngl 999'));
      expect(args.join(' '), contains('--port 9000'));
      expect(args.sublist(args.length - 2), ['--mmproj', 'p.gguf']);
      expect(
        serverArgs((
          exe: 'a.exe',
          model: 'm.gguf',
          mmproj: '',
          port: 9000,
          context: 2048,
          gpuLayers: 20,
        )),
        isNot(contains('--mmproj')),
      );
    });

    test('等到 /health 通了才算起来;停掉会结束进程', () async {
      final process = FakeProcess();
      var polls = 0;
      final server = LlamaServer(
        start: (_, _) async => process,
        health: (_) async => ++polls >= 3,
      );

      final url = await server.start(fakeServerSpec(tmp), poll: Duration.zero);

      expect(url, 'http://127.0.0.1:8091/v1');
      expect(server.running, isTrue);
      await server.stop();
      expect(process.killed, isTrue);
      expect(server.running, isFalse);
    });

    test('起来后马上退出:报出最后一行输出', () async {
      final process = FakeProcess();
      final server = LlamaServer(
        start: (_, _) async {
          scheduleMicrotask(() => process.exit(1, 'loading\nout of memory\n'));
          return process;
        },
        health: (_) async => false,
      );

      await expectLater(
        server.start(
          fakeServerSpec(tmp),
          poll: const Duration(milliseconds: 5),
        ),
        throwsA(
          isA<LocalServerException>().having(
            (e) => e.message,
            'message',
            allOf(contains('退出了'), contains('out of memory')),
          ),
        ),
      );
      expect(server.running, isFalse);
    });

    test('加载途中点停止:说「已停止」,不当成崩了', () async {
      final server = LlamaServer(
        start: (_, _) async => FakeProcess(),
        health: (_) async => false,
      );

      final starting = server.start(
        fakeServerSpec(tmp),
        poll: const Duration(milliseconds: 5),
      );
      // 先挂上判断,不然它报错时还没人接。
      final check = expectLater(
        starting,
        throwsA(
          isA<LocalServerException>().having(
            (e) => e.message,
            'message',
            '已停止',
          ),
        ),
      );
      // 等它真的起了进程、开始等 /health 再停。
      while (!server.running) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await server.stop();
      await check;
    });

    test('找不到文件时不启动', () async {
      final server = LlamaServer(start: (_, _) => fail('不该启动'));
      await expectLater(
        server.start((
          exe: '${tmp.path}/none.exe',
          model: 'm',
          mmproj: '',
          port: 1,
          context: 1,
          gpuLayers: 0,
        )),
        throwsA(isA<LocalServerException>()),
      );
    });

    test('在解开的运行时里找最浅的 llama-server.exe', () {
      Directory('${tmp.path}/a/b').createSync(recursive: true);
      File('${tmp.path}/a/b/llama-server.exe').writeAsStringSync('');
      File('${tmp.path}/a/llama-server.exe').writeAsStringSync('');
      expect(
        findServerExe(tmp)!.path.replaceAll('\\', '/'),
        endsWith('/a/llama-server.exe'),
      );
      expect(findServerExe(Directory('${tmp.path}/none')), isNull);
    });
  });

  group('下载', () {
    // 这个文件里有 testWidgets,Flutter 会拦掉真实的网络请求;这组要连本机的假服务器。
    setUp(() => HttpOverrides.global = null);

    late HttpServer http;
    final body = List.generate(1000, (i) => i % 251);
    final ranges = <String?>[];

    setUp(() async {
      ranges.clear();
      http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      http.listen((request) async {
        final range = request.headers.value(HttpHeaders.rangeHeader);
        ranges.add(range);
        if (request.uri.path == '/missing') {
          request.response.statusCode = 404;
        } else if (range != null) {
          final from = int.parse(range.split('=')[1].split('-')[0]);
          request.response.statusCode = HttpStatus.partialContent;
          request.response.add(body.sublist(from));
        } else {
          request.response.add(body);
        }
        await request.response.close();
      });
    });
    tearDown(() => http.close(force: true));

    RemoteFile file({String path = '/f', String? sha}) => (
      url: 'http://127.0.0.1:${http.port}$path',
      path: '${tmp.path}/out.bin',
      size: body.length,
      sha256: sha,
    );

    test('从断开的地方接着下;校验通过才改成正式的名字', () async {
      File('${tmp.path}/out.bin.part').writeAsBytesSync(body.sublist(0, 400));
      final seen = <int>[];

      await downloadFile(
        file(sha: '${sha256.convert(body)}'),
        onProgress: (got, _) => seen.add(got),
      );

      expect(ranges, ['bytes=400-']);
      expect(File('${tmp.path}/out.bin').readAsBytesSync(), body);
      expect(File('${tmp.path}/out.bin.part').existsSync(), isFalse);
      expect(seen.last, 1000);
      expect(isDownloaded(file()), isTrue);
    });

    test('GitHub 上校验得了的文件先走加速,都不行再直连;别处和不校验的直连', () {
      const url = 'https://github.com/o/r/releases/download/v1/a.zip';
      RemoteFile at(String u, String? sha) =>
          (url: u, path: 'x', size: null, sha256: sha);
      expect(downloadUrls(at(url, 'ab')), [
        for (final p in githubProxies) '$p$url',
        url,
      ]);
      expect(downloadUrls(at(url, null)), [url]);
      expect(downloadUrls(at('https://hf-mirror.com/a', 'ab')), [
        'https://hf-mirror.com/a',
      ]);
    });

    test('一个地址下不了就换下一个,从头下', () async {
      File('${tmp.path}/out.bin.part').writeAsBytesSync([1, 2, 3]);
      final good = file(sha: '${sha256.convert(body)}');
      await downloadFile(
        good,
        urls: ['http://127.0.0.1:${http.port}/missing', good.url],
      );
      expect(File('${tmp.path}/out.bin').readAsBytesSync(), body);
      expect(ranges, ['bytes=3-', null]);
    });

    test('校验不对就删掉;找不到文件说人话', () async {
      await expectLater(
        downloadFile(file(sha: '00')),
        throwsA(
          isA<DownloadException>().having(
            (e) => e.message,
            'message',
            contains('校验'),
          ),
        ),
      );
      expect(File('${tmp.path}/out.bin.part').existsSync(), isFalse);
      expect(File('${tmp.path}/out.bin').existsSync(), isFalse);

      await expectLater(
        downloadFile(file(path: '/missing')),
        throwsA(
          isA<DownloadException>().having(
            (e) => e.message,
            'message',
            contains('404'),
          ),
        ),
      );
    });
  });
}

class FakeProcess implements Process {
  final _exit = Completer<int>();
  final _err = StreamController<List<int>>();
  bool killed = false;

  void exit(int code, [String stderr = '']) {
    _err.add(utf8.encode(stderr));
    _err.close();
    _exit.complete(code);
  }

  @override
  Future<int> get exitCode => _exit.future;
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => _err.stream;
  @override
  IOSink get stdin => throw UnimplementedError();
  @override
  int get pid => 1;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!_exit.isCompleted) exit(-1);
    return true;
  }
}

/// 临时文件夹里放好假的 llama-server.exe 和模型,返回启动参数。
ServerSpec fakeServerSpec(Directory dir) {
  for (final name in ['llama-server.exe', 'm.gguf']) {
    File('${dir.path}/$name').writeAsStringSync('x');
  }
  return (
    exe: '${dir.path}/llama-server.exe',
    model: '${dir.path}/m.gguf',
    mmproj: '',
    port: 8091,
    context: 4096,
    gpuLayers: -1,
  );
}
