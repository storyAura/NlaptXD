import 'package:flutter/foundation.dart';

import 'cha_prompts.dart';

/// CHA 标注(组合分层推标):先给每个角色定一张人物卡,再逐张图判定属于哪几张卡、
/// 核对服装,写成「人物卡 + 空行 + 画面段」。移植自旧版 NLapt 的 nlapt_gui/layered_prompts.py。

const maxCards = 8;

class ChaReplyError implements Exception {
  const ChaReplyError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 人物卡切成两块:固定外貌、官方服装(找不到服装句时 [outfit] 为空,之后不改写服装)。
typedef CardParts = ({String appearance, String outfit});

/// 一张额外参考图(背面、武器、发饰特写……)和它拍的是什么。
typedef ChaReference = ({String path, String label});

/// 锁定的一张人物卡。
@immutable
class ChaCard {
  const ChaCard({required this.name, required this.series, required this.text, required this.parts, this.references = const []});

  factory ChaCard.fromText(String name, String series, String text, [List<ChaReference> references = const []]) {
    final t = text.trim();
    return ChaCard(name: name.trim(), series: series.trim(), text: t, parts: splitCard(t, name), references: references);
  }

  final String name;
  final String series;
  final String text;
  final CardParts parts;
  final List<ChaReference> references;
}

/// 一张图的判定:匹配到的卡(0 起的序号,升序;空 = NONE)、每张卡的服装(null = SAME)、
/// 每张卡按这张图删掉看不见细节后的写法(null = ALL / 没给)、画面段。
typedef ChaVerdict = ({List<int> matched, List<String?> outfits, List<String?> visible, String scene});

/// NLaptXD 加的(旧版没有):参考图一多,人物卡写得很全,可很多图的角度看不见其中一部分(正面看不到背后、
/// 半身看不到鞋)。让模型逐张判断,只留这张图看得见的细节;原文措辞不变、不许加新东西。
const sceneVisibilityNote = '''Visibility check (header block, one VISIBLE line per matched card, right after its OUTFIT line, before the blank line that starts the paragraph):
The card text is the full reference description of the character, written from several reference images. Some of its details may not be visible in this image — for example back details in a front view, shoes or socks when the image is cropped above the knees, an ornament on the far side of the head, or a tattoo covered by clothing.
- If every detail of the card can be seen in this image, write "VISIBLE <card number>: ALL".
- Otherwise write "VISIBLE <card number>: " followed by the card text rewritten to keep only the details that can actually be seen in this image. Start with the same subject words as the card, keep the original wording for everything you keep, delete the phrases or sentences for details that cannot be seen, and never add anything that is not in the card. If the OUTFIT line reports a different outfit, describe that outfit here instead of the card's official outfit.
- Judge each detail from the image yourself; when unsure whether a detail is visible, keep it.''';

String _fill(String template, Map<String, String> values) {
  var out = template;
  values.forEach((k, v) => out = out.replaceAll('{$k}', v));
  return out;
}

String _label(String label) {
  final l = label.trim().split(RegExp(r'\s+')).join(' ');
  return l.isEmpty ? refLabelFallback : l;
}

String _oneLine(String s) => s.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');

/// 生成人物卡的提示词。[variant] 0..2 对应三个候选,各带一句不同的侧重,免得三个写成一样。
String buildCardPrompt(String name, String series, {int variant = 0, List<String> referenceLabels = const []}) {
  final n = name.trim();
  final opening = series.trim().isEmpty ? n : '$n from ${series.trim()}';
  final hint = cardVariantHints[variant.clamp(0, cardVariantHints.length - 1)];
  final prompt = '${_fill(characterCardPrompt, {'name': n, 'opening': opening}).trimRight()}\n\n$hint';
  if (referenceLabels.isEmpty) return prompt;
  final lines = [for (final (i, l) in referenceLabels.indexed) '- Image ${i + 2}: ${_label(l)}'].join('\n');
  return '$prompt\n\n${_fill(cardReferencesNote, {'name': n, 'LINES': lines})}';
}

/// 逐张推标的提示词:列出每张卡的外貌和官方服装;卡带参考图时,说明第 2 张起各是谁的参考。
String buildScenePrompt(List<ChaCard> roster) {
  final lines = [
    for (final (i, c) in roster.indexed)
      'Card ${i + 1} — name: ${c.name}; appearance: "${_oneLine(c.parts.appearance)}"; '
          'official outfit: "${_oneLine(c.parts.outfit).isEmpty ? outfitReferenceMissing : _oneLine(c.parts.outfit)}"',
  ];
  final names = [...{for (final c in roster) if (c.name.isNotEmpty) c.name}];
  final prompt = _fill(poseScenePrompt, {'ROSTER': lines.join('\n'), 'NAMES': names.join(', ')});
  final refs = [
    for (final (i, c) in roster.indexed)
      for (final r in c.references) (card: i + 1, name: c.name, label: r.label),
  ];
  final withVisible = '${prompt.trimRight()}\n\n$sceneVisibilityNote';
  if (refs.isEmpty) return withVisible;
  final refLines = [
    for (final (k, r) in refs.indexed) '- Image ${k + 2}: reference of card ${r.card} (${r.name}) — ${_label(r.label)}',
  ].join('\n');
  return '$withVisible\n\n${_fill(sceneReferencesNote, {'LINES': refLines})}';
}

/// 逐张推标时随图发送的参考图路径,顺序和 [buildScenePrompt] 里的说明一致。
List<String> rosterReferencePaths(List<ChaCard> roster) => [
  for (final c in roster)
    for (final r in c.references) r.path,
];

List<int> _sentenceStarts(String text) => [0, for (final m in RegExp(r'[.!?]\s+(?=\S)').allMatches(text)) m.end];

/// 在服装段的第一句切开:优先「<名字>|She|He|They wears / is wearing / is dressed in」,
/// 其次是第一句提到衣物的句子(第一句不算);都没有时整张都是外貌。
CardParts splitCard(String card, [String name = '']) {
  final text = card.trim();
  if (text.isEmpty) return (appearance: '', outfit: '');
  final subjects = ['she', 'he', 'they', if (name.trim().isNotEmpty) RegExp.escape(name.trim())];
  final verbs = outfitOpenerVerbs.map(RegExp.escape).join('|');
  final opener = RegExp('^(?:${subjects.join('|')})\\s+(?:$verbs)\\b', caseSensitive: false);
  final garment = RegExp('\\b(?:${garmentWords.map(RegExp.escape).join('|')})\\b', caseSensitive: false);
  final starts = _sentenceStarts(text);
  String sentence(int i) => text.substring(starts[i], i + 1 < starts.length ? starts[i + 1] : text.length);
  CardParts at(int i) => (appearance: text.substring(0, starts[i]).trimRight(), outfit: text.substring(starts[i]).trim());
  for (var i = 0; i < starts.length; i++) {
    if (opener.hasMatch(sentence(i))) return at(i);
  }
  for (var i = 1; i < starts.length; i++) {
    if (garment.hasMatch(sentence(i))) return at(i);
  }
  return (appearance: text, outfit: '');
}

/// SAME(大小写、标点、后面多一个词都算)为 null,否则是压成一行的服装描述。
String? _outfitVerdict(String body) {
  final v = body.replaceAll(RegExp(r'[^A-Za-z ]'), '').trim().toUpperCase();
  if (body.trim().isEmpty || v == 'SAME' || v.startsWith('SAME ')) return null;
  return _oneLine(body);
}

final _cardLine = RegExp(r'^\s*CARD\s*:\s*(.*)$', caseSensitive: false);
final _outfitLine = RegExp(r'^\s*OUTFIT\s*(\d+)?\s*:\s*(.*)$', caseSensitive: false);
final _visibleLine = RegExp(r'^\s*VISIBLE\s*(\d+)?\s*:\s*(.*)$', caseSensitive: false);

/// 读一张图的回复:开头一块是 CARD / OUTFIT / VISIBLE 头,空一行后是画面段。
/// 编号超出范围的丢掉;不带编号的 OUTFIT / VISIBLE 归唯一匹配的那张;
/// 没有头时只有一张卡才当成旧的单卡格式,否则报错。
ChaVerdict parseReply(String text, int rosterSize) {
  final stripped = text.trim();
  if (stripped.isEmpty) return (matched: const [], outfits: const [], visible: const [], scene: '');
  final blocks = [for (final b in stripped.split(RegExp(r'\n\s*\n'))) if (b.trim().isNotEmpty) b.trim()];
  final head = blocks.first.toUpperCase();
  if (!head.startsWith('CARD') && !head.startsWith('OUTFIT')) {
    if (rosterSize != 1) throw const ChaReplyError('模型回复缺少 CARD: 判定行,无法确定属于哪张角色卡');
    return (matched: const [0], outfits: const [null], visible: const [null], scene: stripped);
  }
  List<int>? matched;
  final entries = <({bool visible, int? n, String body})>[];
  for (final line in blocks.first.split('\n')) {
    final c = _cardLine.firstMatch(line);
    if (c != null && matched == null) {
      final body = c.group(1)!;
      matched = body.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase() == 'NONE'
          ? const []
          : ({
              for (final m in RegExp(r'\d+').allMatches(body))
                if (int.parse(m[0]!) >= 1 && int.parse(m[0]!) <= rosterSize) int.parse(m[0]!) - 1,
            }.toList()..sort());
      continue;
    }
    final o = _outfitLine.firstMatch(line) ?? _visibleLine.firstMatch(line);
    if (o != null) {
      entries.add((visible: _visibleLine.hasMatch(line), n: int.tryParse(o.group(1) ?? ''), body: o.group(2)!));
    } else if (entries.isNotEmpty && line.trim().isNotEmpty) {
      final last = entries.removeLast();
      entries.add((visible: last.visible, n: last.n, body: '${last.body} ${line.trim()}'));
    }
  }
  final scene = blocks.skip(1).join('\n\n').trim();
  if (matched == null) {
    if (rosterSize != 1) throw const ChaReplyError('模型回复缺少 CARD: 判定行,无法确定属于哪张角色卡');
    matched = const [0];
  }
  if (matched.isEmpty) return (matched: const [], outfits: const [], visible: const [], scene: scene);
  final outfits = <int, String?>{}, visible = <int, String?>{};
  for (final e in entries) {
    // 不带编号的归唯一匹配的那张。
    final card = e.n == null ? (matched.length == 1 ? matched.first : null) : e.n! - 1;
    if (card == null || !matched.contains(card)) continue;
    if (e.visible) {
      final v = e.body.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase();
      visible[card] = v == 'ALL' || e.body.trim().isEmpty ? null : e.body.trim();
    } else {
      outfits[card] = _outfitVerdict(e.body);
    }
  }
  return (
    matched: matched,
    outfits: [for (final i in matched) outfits[i]],
    visible: [for (final i in matched) visible[i]],
    scene: scene,
  );
}

/// 匹配到的卡 + 空行 + 画面段;NONE 时为 null(这张图不写)。每张卡优先用按这张图删掉看不见细节的写法,
/// 其次是外貌 + 改写的服装,否则原样。
String? assembleCaption(List<ChaCard> roster, ChaVerdict v) {
  if (v.matched.isEmpty) return null;
  if (v.scene.trim().isEmpty) throw const ChaReplyError('模型回复缺少画面段');
  final bodies = [
    for (final (k, i) in v.matched.indexed)
      if (i >= 0 && i < roster.length)
        if (trimmedCardOk(roster[i], v.visible.elementAtOrNull(k)))
          _oneLine(v.visible[k]!)
        else if (v.outfits[k] == null || roster[i].parts.outfit.isEmpty)
          roster[i].text
        else
          '${roster[i].parts.appearance.trimRight()} ${v.outfits[k]!.trim()}',
  ];
  return [...bodies, v.scene.trim()].join('\n\n');
}

/// 保护:删过的写法必须还以角色名开头(每张图里同一个角色叫法一致,训练时不会认成两个人),
/// 不能短到只剩名字,也不能比原卡长出一截(那是加了东西)。不满足就用完整的卡。
bool trimmedCardOk(ChaCard card, String? trimmed) {
  final t = trimmed?.trim() ?? '';
  if (t.isEmpty || card.name.isEmpty) return false;
  if (!t.toLowerCase().startsWith(card.name.toLowerCase())) return false;
  return t.length >= card.name.length + 30 && t.length <= card.text.length * 1.15 + 40;
}
