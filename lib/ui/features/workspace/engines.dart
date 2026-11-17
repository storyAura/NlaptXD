import 'dart:io';

import 'package:image/image.dart' as img;

import '../../../core/cha.dart';
import '../../../core/dataset.dart';
import '../../../core/json_caption.dart';
import '../../../core/llm/api_profile.dart';
import '../../../core/llm/llm_client.dart';
import '../../../core/llm/translate.dart';
import '../../../core/llm/vision_image.dart';
import '../../../data/app_config.dart';
import '../local/local_store.dart';
import 'workspace.dart';

/// 给提示词和图(第一张是主图),拿回模型的回答。在线接口和本地 GGUF 都统一成这一种。
typedef VisionAsk = Future<String> Function({required String prompt, String system, required List<ImagePart> images});

/// 读图并缩好(长边 1024、JPEG),在线接口和本地 llama-server 都发这个。
Future<ImagePart> readImage(String path) async => prepareImage(await File(path).readAsBytes(), imageMime(path));

/// [ref] 指的模型能用时给出问它的函数;接口停用了、模型没勾、本地模型没下载或是 Florence-2 时为 null。
VisionAsk? askerFor(ModelRef? ref, AppConfig c, LocalStore local) {
  if (ref == null) return null;
  if (ref.profileId == localProfileId) {
    final m = local.picked;
    return m == null || m.florence || !local.installed(m) ? null : local.ask;
  }
  final profile = c.profileOf(ref);
  if (profile == null) return null;
  final client = LlmClient(profile);
  return ({required String prompt, String system = '', required List<ImagePart> images}) => client.caption(
    model: ref.model,
    prompt: prompt,
    system: system,
    image: images.first.bytes,
    mime: images.first.mime,
    extra: images.skip(1).toList(),
  );
}

/// 按设置里的翻译服务给出翻译器;「大模型」走当前文本模型(没选或接口停用时那一家跳过)。
Translator translatorFor(AppConfig c) {
  final ref = c.textModel;
  final profile = c.profileOf(ref);
  return Translator(
    c.translate,
    llm: profile == null ? null : (prompt, system) => LlmClient(profile).chat(model: ref!.model, prompt: prompt, system: system),
  );
}

/// 界面上显示的模型名。
String modelLabel(ModelRef? ref, LocalStore local) =>
    ref == null ? '未设置' : ref.profileId == localProfileId ? '本地 · ${local.picked?.name ?? '未选模型'}' : ref.model;

/// 「LLM」引擎:当前视觉模型看图,照当前系统提示词方案写。
CaptionFn? llmCaptioner(AppConfig c, LocalStore local) {
  final ask = askerFor(c.vision, c, local);
  if (ask == null) return null;
  return (ImageEntry e) async => ask(prompt: c.captionPrompt, system: c.system, images: [await readImage(e.imagePath)]);
}

/// JSON 标注:视觉模型看图回草稿 JSON,按原图宽高换成 [format] 的官方 JSON。
CaptionFn jsonCaptioner(JsonFormat format, VisionAsk ask) => (ImageEntry e) async {
  final bytes = await File(e.imagePath).readAsBytes();
  final info = img.findDecoderForData(bytes)?.startDecode(bytes);
  if (info == null) throw const LlmError('读不出图片尺寸');
  final (prompt, parse) = switch (format) {
    JsonFormat.moss => (mossPrompt, mossLayoutFromReply),
  };
  return parse(await ask(prompt: prompt, images: [await prepareImage(bytes, imageMime(e.imagePath))]), info.width, info.height);
};

/// CHA 逐张推标:一次请求同时判定属于哪几张卡、核对服装、写画面段。
/// 绑定了子文件夹的卡按卡上的勾选发参考图 / 文字:单人绑定的文件夹只在绑它的卡之间判定(只绑一张就直接是它);
/// 多人绑定的文件夹用全部卡认人,绑定的卡一定算上。其余的图用全部卡认人。
/// [hits] 记下每张卡匹配到哪些图(给结束时的汇总和 CHA 记录用)。
CaptionFn chaCaptioner(List<ChaCard> roster, VisionAsk ask, Map<int, List<ImageEntry>> hits) {
  final everyone = [for (var i = 0; i < roster.length; i++) i];
  ({List<int> idx, List<ChaCard> cards, List<int> known, String prompt, List<String> refs}) group(
    List<int> idx, {
    Set<int> bound = const {},
    bool solo = false,
  }) {
    final cards = [for (final i in idx) bound.contains(i) ? boundCard(roster[i]) : roster[i]];
    final known = solo ? const <int>[] : [for (final (k, i) in idx.indexed) if (bound.contains(i)) k];
    return (
      idx: idx,
      cards: cards,
      known: known,
      prompt: buildScenePrompt(cards, bound: solo, known: known),
      refs: rosterReferencePaths(cards),
    );
  }

  final all = group(everyone);
  final byFolder = <String, ({List<int> idx, List<ChaCard> cards, List<int> known, String prompt, List<String> refs})>{};
  for (final f in {for (final c in roster) ?c.bind?.folder}) {
    final bound = [for (final (i, c) in roster.indexed) if (c.bind?.folder == f) i];
    // 绑这个文件夹的卡全是单人才跳过认人;有一张是多人就用全部卡认。
    byFolder[f] = bound.every((i) => roster[i].bind!.solo)
        ? group(bound, bound: bound.toSet(), solo: true)
        : group(everyone, bound: bound.toSet());
  }
  return (ImageEntry e) async {
    final g = byFolder[e.folder] ?? all;
    final images = [await readImage(e.imagePath), for (final p in g.refs) await readImage(p)];
    final verdict = withKnown(parseReply(await ask(prompt: g.prompt, images: images), g.cards.length), g.known);
    final caption = assembleCaption(g.cards, verdict);
    for (final k in verdict.matched) {
      (hits[g.idx[k]] ??= []).add(e);
    }
    return caption;
  };
}
