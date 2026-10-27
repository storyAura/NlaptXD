import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

import '../../../core/dataset.dart';
import '../../../core/l10n.dart';
import '../../../core/llm/api_profile.dart';
import '../../../core/llm/openai_client.dart';
import '../../../core/local/caption_catalog.dart';
import '../../../core/local/download.dart';
import '../../../core/local/florence.dart';
import '../../../core/local/llama_server.dart';
import '../../../core/text_io.dart';
import '../../../data/local/florence_engine.dart';
import '../workspace/workspace.dart';

/// 模型池里「本地模型」那一项的接口 id(CHA 的模型位可以选它)。
const localProfileId = 'local';

/// 下载来源:官方和国内镜像(取自 Penna 的 tagger_catalog.dart)。
const hfSources = {'huggingface': 'https://huggingface.co', 'mirror': 'https://hf-mirror.com'};

String hfFileUrl(String source, String repo, String file) =>
    '${hfSources[source] ?? hfSources['huggingface']}/$repo/resolve/main/$file';

String fileName(String path) => path.split(RegExp(r'[\\/]')).last;

typedef Progress = ({int received, int? total});

/// 本地推理:模型清单(取自 Penna,由 NLapt 的 catalog.py 生成)、下载、llama.cpp 运行时、
/// llama-server 起停,以及 Florence-2 在程序里直接跑。设置存在 [home]/local.json,
/// 模型在 models\gguf\<id>\,运行时在 runtime\。下载、起服务、解压的写法照搬 Penna 的 LocalModel。
class LocalStore extends ChangeNotifier {
  LocalStore(this.home, {LlamaServer? server, this.idle = const Duration(seconds: 30)})
    : server = server ?? LlamaServer() {
    this.server.onExit = notifyListeners;
  }

  final Directory home;
  final LlamaServer server;

  /// 推理时拉起的服务空闲这么久就停(用户自己点「启动」的不停)。
  final Duration idle;

  // —— 存盘的设置 ——
  String source = 'mirror';
  String pick = '';
  Map<String, String> quantPicks = const {};
  String florenceTask = florenceTaskLabels.keys.first;
  int port = 8091;
  int context = 8192;
  int gpuLayers = -1;

  // —— 只在内存里 ——
  final _downloads = <String, Progress>{};
  final _cancels = <String, DownloadCancel>{};
  Future<String>? _starting;
  bool _autoStarted = false;
  int _busy = 0;
  Timer? _idleTimer;
  FlorenceEngine? _florence;
  String? _florenceFor;

  String get _sep => Platform.pathSeparator;
  String get _home => home.path;

  Progress? progressOf(String key) => _downloads[key];
  bool get starting => _starting != null;

  CaptionModel? get picked => captionModels.where((m) => m.id == pick).firstOrNull;

  Quant quantOf(CaptionModel m) =>
      m.quants.where((q) => q.label == quantPicks[m.id]).firstOrNull ??
      m.quants.where((q) => q.recommended).firstOrNull ??
      m.quants.first;

  String _folderOf(CaptionModel m) => '$_home${_sep}models${_sep}gguf$_sep${m.id}';

  RemoteFile _remote(CaptionModel m, ModelFile f) =>
      (url: hfFileUrl(source, m.repo, f.path), path: '${_folderOf(m)}$_sep${fileName(f.path)}', size: f.size, sha256: f.sha256);

  /// 要下载的文件:量化档,加视觉组件(GGUF)或另外几个 ONNX 和分词器(Florence-2)。
  List<RemoteFile> files(CaptionModel m, [Quant? quant]) => [
    _remote(m, (quant ?? quantOf(m)).file),
    if (m.mmproj case final mm?) _remote(m, mm),
    for (final e in m.extra) _remote(m, e),
  ];

  bool installed(CaptionModel m) => files(m).every(isDownloaded);

  int sizeOf(CaptionModel m) => files(m).fold(0, (s, f) => s + (f.size ?? 0));

  // —— 运行时 ——

  RemoteFile get _runtimeZip =>
      (url: llamaRuntimeUrl, path: '$_home${_sep}runtime$_sep$llamaRuntimeFile', size: llamaRuntimeSize, sha256: llamaRuntimeSha256);

  Directory get _runtimeDir => Directory('$_home${_sep}runtime${_sep}llama.cpp-$llamaCppTag');

  String? get serverExe => findServerExe(_runtimeDir)?.path;

  /// 下载并解开 llama.cpp 运行时(先解到旁边的临时文件夹,全解完才换上)。
  Future<String?> downloadRuntime() async {
    final zip = _runtimeZip;
    final problem = await download('runtime', [zip]);
    if (problem != null) return problem;
    final target = _runtimeDir.path;
    try {
      final from = zip.path;
      await Isolate.run(() => _extractInto(from, '$target.tmp', target));
      await File(zip.path).delete();
    } on Object catch (e) {
      return tr('运行时解压失败({0})', [e.runtimeType]);
    }
    notifyListeners();
    return serverExe == null ? '运行时里没找到 llama-server.exe' : null;
  }

  // —— 下载 ——

  /// 依次下载 [files],进度记在 [key] 下。失败时返回给用户看的原因。
  Future<String?> download(String key, List<RemoteFile> files) async {
    if (_downloads.containsKey(key)) return '正在下载';
    final cancel = _cancels[key] = DownloadCancel();
    final total = files.fold<int>(0, (a, f) => a + (f.size ?? 0));
    var before = 0;
    _downloads[key] = (received: 0, total: total);
    notifyListeners();
    String? problem;
    try {
      for (final f in files) {
        await downloadFile(
          f,
          cancel: cancel,
          onProgress: (got, _) {
            _downloads[key] = (received: before + got, total: total);
            notifyListeners();
          },
        );
        before += File(f.path).lengthSync();
      }
    } on DownloadException catch (e) {
      problem = e.message;
    } on FileSystemException catch (e) {
      problem = '存不下来:${e.osError?.message ?? e.message}';
    }
    _downloads.remove(key);
    _cancels.remove(key);
    notifyListeners();
    return problem;
  }

  void cancelDownload(String key) => _cancels[key]?.cancel();

  /// 下载一个模型(选中的量化档);还没选本地模型时下好就选它。
  Future<String?> downloadModel(CaptionModel m) async {
    final problem = await download(m.id, files(m));
    if (problem == null && picked == null) use(m);
    return problem;
  }

  /// 删掉这一档;视觉组件只在别的档也没了时才删(几档共用一个)。
  Future<String?> removeModel(CaptionModel m) async {
    final fs = files(m);
    if (server.running && fs.any((f) => f.path == server.spec?.model)) return '这个模型正在用,先停止服务';
    final shared = m.quants.any((q) => q.label != quantOf(m).label && isDownloaded(_remote(m, q.file)));
    if (_florenceFor == _folderOf(m)) await _dropFlorence();
    try {
      for (final f in m.florence || !shared ? fs : fs.take(1)) {
        for (final file in [File(f.path), File('${f.path}.part')]) {
          if (file.existsSync()) await file.delete();
        }
      }
    } on FileSystemException catch (e) {
      return '删不掉:${e.osError?.message ?? e.message}';
    }
    notifyListeners();
    return null;
  }

  void use(CaptionModel m) => update(() => pick = m.id);
  void pickQuant(CaptionModel m, String label) => update(() => quantPicks = Map.unmodifiable({...quantPicks, m.id: label}));

  /// Florence-2 这次用的指令:选过的,它不认就用它的第一个。
  String florenceTaskOf(CaptionModel m) => m.tasks.contains(florenceTask) ? florenceTask : m.tasks.first;

  // —— llama-server ——

  /// 用户点「启动」:起来后不会因为空闲被停。
  Future<String?> startServer() async {
    final m = picked;
    if (m == null || m.florence) return '先选一个 GGUF 模型';
    try {
      await _ensureServer(m);
      _autoStarted = false;
      return null;
    } on LlmError catch (e) {
      return e.message;
    }
  }

  Future<void> stopServer() async {
    _idleTimer?.cancel();
    await server.stop();
    notifyListeners();
  }

  /// 起(或换成)这个模型的 llama-server,返回接口地址。运行时缺了先自动下载。
  Future<String> _ensureServer(CaptionModel m) {
    final fs = files(m);
    if (!fs.every(isDownloaded)) throw LlmError('先在「模型」页下载 ${m.name}');
    if (server.running && server.spec?.model == fs[0].path) return Future.value(server.baseUrl!);
    return _starting ??= () async {
      notifyListeners();
      try {
        if (serverExe == null) {
          final problem = await downloadRuntime();
          if (problem != null) throw LlmError('llama.cpp 运行时:$problem');
        }
        _autoStarted = true;
        return await server.start((
          exe: serverExe!,
          model: fs[0].path,
          mmproj: fs.length > 1 ? fs[1].path : '',
          port: port,
          context: context,
          gpuLayers: gpuLayers,
        ));
      } on LocalServerException catch (e) {
        throw LlmError(e.message);
      } finally {
        _starting = null;
        notifyListeners();
      }
    }();
  }

  /// 推理完一次:服务是推理时拉起的,就在空闲 [idle] 后停掉;新的推理会取消这次停止。
  void _done() {
    _busy--;
    _idleTimer?.cancel();
    if (_busy == 0 && _autoStarted && server.running) {
      _idleTimer = Timer(idle, () {
        if (_busy == 0 && _autoStarted) stopServer();
      });
    }
  }

  // —— 推理 ——

  /// 让本地 GGUF 模型看图回答(CHA 也走这里)。Florence-2 不认自定义提示词。
  Future<String> ask({required String prompt, String system = '', required List<ImagePart> images}) async {
    final m = picked;
    if (m == null) throw const LlmError('先在「模型」页选一个本地模型');
    if (m.florence) throw const LlmError('Florence-2 不支持自定义提示词,请改用 LLM 或 GGUF 模型');
    _busy++;
    _idleTimer?.cancel();
    try {
      final url = await _ensureServer(m);
      final client = OpenAiClient(
        ApiProfile(id: localProfileId, name: '本机 llama-server', baseUrl: url, apiKey: ''),
        timeout: const Duration(minutes: 10),
      );
      return await client.caption(
        model: 'local',
        prompt: prompt,
        system: system,
        image: images.first.bytes,
        mime: images.first.mime,
        extra: images.skip(1).toList(),
      );
    } finally {
      _done();
    }
  }

  /// 标注台用的推标函数;还没选模型或没下载时为 null。
  CaptionFn? captioner({required String prompt, String system = ''}) {
    final m = picked;
    if (m == null || !installed(m)) return null;
    return (ImageEntry e) async {
      final bytes = await File(e.imagePath).readAsBytes();
      if (m.florence) return _florenceCaption(m, bytes);
      return ask(prompt: prompt, system: system, images: [(bytes: bytes, mime: imageMime(e.imagePath))]);
    };
  }

  /// Florence-2:第一次用时加载四个 ONNX,之后留着;换了模型才重新加载。
  Future<String> _florenceCaption(CaptionModel m, Uint8List bytes) async {
    final dir = _folderOf(m);
    try {
      if (_florenceFor != dir) {
        await _dropFlorence();
        _florence = await FlorenceEngine.load(dir);
        _florenceFor = dir;
      }
      final pixels = await _decode(bytes, florenceImageSize);
      final text = await _florence!.caption(florencePixels(pixels, florenceImageSize), florenceTaskOf(m));
      if (text.trim().isEmpty) throw const LlmError('模型没有返回内容');
      return text.trim();
    } on FlorenceException catch (e) {
      await _dropFlorence();
      throw LlmError(e.message);
    }
  }

  Future<void> _dropFlorence() async {
    final old = _florence;
    _florence = null;
    _florenceFor = null;
    await old?.close().catchError((Object _) {});
  }

  // —— 存盘 ——

  void update(void Function() change) {
    change();
    notifyListeners();
    unawaited(_save());
  }

  File get _file => File('$_home${_sep}local.json');

  Future<void> _save() async {
    try {
      await writeAtomic(_file.path, jsonEncode({
        'source': source,
        'pick': pick,
        'quantPicks': quantPicks,
        'florenceTask': florenceTask,
        'port': port,
        'context': context,
        'gpuLayers': gpuLayers,
      }));
    } on FileSystemException catch (e) {
      debugPrint('local.json 写入失败:$e');
    }
  }

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      source = j['source'] as String? ?? source;
      pick = j['pick'] as String? ?? '';
      quantPicks = Map.unmodifiable((j['quantPicks'] as Map? ?? const {}).cast<String, String>());
      florenceTask = j['florenceTask'] as String? ?? florenceTask;
      port = j['port'] as int? ?? port;
      context = j['context'] as int? ?? context;
      gpuLayers = j['gpuLayers'] as int? ?? gpuLayers;
    } on Object catch (e) {
      debugPrint('local.json 读取失败,用默认设置:$e');
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    for (final c in _cancels.values) {
      c.cancel();
    }
    unawaited(server.stop());
    unawaited(_dropFlorence());
    super.dispose();
  }
}

/// 把图解码并缩到 [size]×[size] 的 RGBA(Florence-2 的输入),用 dart:ui,不另装解码库。
Future<Uint8List> _decode(Uint8List bytes, int size) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final codec = await descriptor.instantiateCodec(targetWidth: size, targetHeight: size);
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  frame.image.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  if (data == null) throw const LlmError('读不了这张图');
  return data.buffer.asUint8List();
}

/// 把 [zip] 解到 [temp],全解完再换成 [target](取自 Penna)。
Future<void> _extractInto(String zip, String temp, String target) async {
  final dir = Directory(temp);
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  await extractFileToDisk(zip, temp);
  final old = Directory(target);
  if (old.existsSync()) old.deleteSync(recursive: true);
  dir.renameSync(target);
}
