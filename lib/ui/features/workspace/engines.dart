import 'dart:io';

import '../../../core/cha.dart';
import '../../../core/dataset.dart';
import '../../../core/llm/api_profile.dart';
import '../../../core/llm/openai_client.dart';
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
  final client = OpenAiClient(profile);
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
    llm: profile == null ? null : (prompt, system) => OpenAiClient(profile).chat(model: ref!.model, prompt: prompt, system: system),
  );
}

/// 界面上显示的模型名。
String modelLabel(ModelRef? ref, LocalStore local) =>
    ref == null ? '未设置' : ref.profileId == localProfileId ? '本地 · ${local.picked?.name ?? '未选模型'}' : ref.model;

/// 「LLM」引擎:当前视觉模型看图,用设置里的推标提示词。
CaptionFn? llmCaptioner(AppConfig c, LocalStore local) {
  final ask = askerFor(c.vision, c, local);
  if (ask == null) return null;
  return (ImageEntry e) async => ask(prompt: c.prompt, system: c.system, images: [await readImage(e.imagePath)]);
}

/// CHA 逐张推标:一次请求同时判定属于哪几张卡、核对服装、写画面段。
/// [counts] 累计每张卡匹配到几张图(给结束时的汇总用)。
CaptionFn chaCaptioner(List<ChaCard> roster, VisionAsk ask, Map<int, int> counts) {
  final prompt = buildScenePrompt(roster);
  final refPaths = rosterReferencePaths(roster);
  return (ImageEntry e) async {
    final images = [await readImage(e.imagePath), for (final p in refPaths) await readImage(p)];
    final verdict = parseReply(await ask(prompt: prompt, images: images), roster.length);
    final caption = assembleCaption(roster, verdict);
    for (final i in verdict.matched) {
      counts[i] = (counts[i] ?? 0) + 1;
    }
    return caption;
  };
}
