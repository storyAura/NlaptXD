import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'llm/cleaning.dart';
import 'llm/llm_client.dart';

/// JSON 标注:看图反推成某个生图模型认的结构化 JSON。先只有 MOSS-Image 的布局 JSON。
enum JsonFormat {
  moss('MOSS');

  const JsonFormat(this.label);
  final String label;
}

/// 让模型回草稿格式:bbox 是 0–1000 的比例坐标、左上角原点的 xyxy,程序再按图的宽高换成官方坐标。
/// 写法照 MOSS-Image 官方 USERGUIDE 的 Layout Prompts 和 Penna 的 moss-layout 技能(都不写质量词、标签串、画师)。
const mossPrompt = '''Describe this image as a MOSS-Image layout JSON. Output only the JSON object, no prose before or after.

{
  "summary": {
    "meta": ["illustration"],
    "canvas": "single",
    "style": "...",
    "caption": "..."
  },
  "items": [
    {"label": "character", "caption": "...", "bbox": [x_min, y_min, x_max, y_max]},
    {"label": "text", "text": "EXACT TEXT", "caption": "...", "bbox": [x_min, y_min, x_max, y_max]}
  ]
}

Fields:
- meta: one or two genre words (illustration, photo, poster, comic, ...).
- canvas: "single" for one picture, "multi_panel" for a comic page with panels, "collage" for a collage.
- style: 40 to 100 words on the rendering style only (medium, line work, coloring, shading, light treatment, texture), ending with one sentence "Palette: ..." listing the main colors. Do not describe the content here.
- summary.caption: one paragraph of 120 to 250 words, as if describing a finished picture: first say what it is, then composition and camera (where the subject sits, how much of the frame, shot size, camera height), who the subject is and what they are doing, the setting and background, where the light comes from and the time of day, the main colors and mood. Say what is in front and what is behind, what overlaps what, and what is cut off by the frame edges. End by quoting every piece of visible text from top to bottom in double quotes, with where it sits.
- items: 1 to 8 distinct visible elements, ordered from front to back. Do not box the background; it belongs in summary.caption.
  - Box whole objects only: a person as a whole, not their hat, hair or hands; a building, not its windows or roof.
  - Every character gets its own item. Similar small things that repeat (trees, chairs, petals, a crowd) are one item boxing the group, or are left to summary.caption.
  - label: "character" for people and characters, "text" for written text (put the exact text, unchanged, in "text"), "object" for everything else.
  - caption: 2 to 4 sentences, 30 to 80 words, only what is visible in this element. A character starts with who it is: a recognizable named character is written as "Hatsune Miku from Vocaloid", otherwise a short description; then hair, eyes, expression, clothing from top to bottom with colors and materials, pose, hands, gaze. An object: what it is, shape, material, color, light and shadow on it. A text: font type, weight, color, size level, alignment, effects. Also say where it sits in the frame and what it overlaps or is hidden by.
  - bbox: [x_min, y_min, x_max, y_max] on a 0 to 1000 scale, where the top-left corner of the image is 0 and the bottom-right is 1000. Fit the box tightly to the element's real outline; a character's box runs from the top of the head to the lowest visible part. Elements cut by the image edge use 0 or 1000 on that side.

Rules:
- English natural-language sentences only, describing only what is visible. Do not speculate.
- No Danbooru tag lists (1girl, solo, ...), no weights or brackets, no quality words (masterpiece, best quality, 8k, ...), no camera models, renderers or artist names.
- Use the same words for an element in summary.caption and in its own caption.''';

/// 布局里的一块。[bbox] 是官方坐标:画面中心为原点的 [y_min, x_min, y_max, x_max] 像素。
@immutable
class MossItem {
  const MossItem({required this.label, required this.caption, this.text = '', required this.bbox});

  final String label;
  final String caption;

  /// label 是 text 时要画出来的字。
  final String text;
  final List<int> bbox;

  MossItem copyWith({String? label, String? caption, String? text}) =>
      MossItem(label: label ?? this.label, caption: caption ?? this.caption, text: text ?? this.text, bbox: bbox);

  Map<String, Object> toJson() => {
    'label': label,
    'caption': caption,
    if (label == 'text' && text.isNotEmpty) 'text': text,
    'bbox': bbox,
  };
}

/// MOSS-Image 的布局 JSON(summary + items,abs_centralized / yxyx)。
@immutable
class MossLayout {
  const MossLayout({this.meta = const [], this.canvas = 'single', required this.caption, this.items = const []});

  final List<String> meta;
  final String canvas;
  final String caption;

  /// 从前到后。
  final List<MossItem> items;

  MossLayout copyWith({List<String>? meta, String? canvas, String? caption, List<MossItem>? items}) => MossLayout(
    meta: meta ?? this.meta,
    canvas: canvas ?? this.canvas,
    caption: caption ?? this.caption,
    items: items ?? this.items,
  );

  String toJson() => const JsonEncoder.withIndent('  ').convert({
    'summary': {if (meta.isNotEmpty) 'meta': meta, 'canvas': canvas, 'caption': caption},
    'items': [for (final it in items) it.toJson()],
    'bbox_coord_space': 'abs_centralized',
    'bbox_format': 'yxyx',
  });
}

const mossLabels = ['character', 'text', 'object'];
const mossCanvases = ['single', 'multi_panel', 'collage'];

/// 读标注里的 MOSS 布局 JSON;不是 JSON、没有 summary.caption 时为 null。读不了的块去掉。
MossLayout? readMossLayout(String text) {
  final Object? j;
  try {
    j = jsonDecode(text);
  } on FormatException {
    return null;
  }
  return j is Map ? _layout(j, (b) => [for (final v in b) (v as num).round()]) : null;
}

/// summary 和各块照 [j] 读,bbox 交给 [box] 换算(返回 null 的块去掉)。
MossLayout? _layout(Map<dynamic, dynamic> j, List<int>? Function(List<dynamic> bbox) box) {
  final summary = j['summary'];
  final caption = summary is Map ? _str(summary['caption']) : '';
  if (summary is! Map || caption.isEmpty) return null;
  final meta = summary['meta'];
  return MossLayout(
    meta: [
      if (meta is List) for (final m in meta) if ('$m'.trim().isNotEmpty) '$m'.trim(),
      if (meta is String && meta.trim().isNotEmpty) meta.trim(),
    ],
    canvas: mossCanvases.contains(summary['canvas']) ? summary['canvas'] as String : 'single',
    caption: caption,
    items: [
      for (final it in (j['items'] as List?) ?? const [])
        if (it is Map && _str(it['caption']).isNotEmpty && it['bbox'] is List && (it['bbox'] as List).length == 4 && (it['bbox'] as List).every((v) => v is num))
          if (box(it['bbox'] as List) case final b?)
            MossItem(
              label: mossLabels.contains(it['label']) ? it['label'] as String : 'object',
              caption: _str(it['caption']),
              text: it['label'] == 'text' ? _str(it['text']) : '',
              bbox: b,
            ),
    ].take(8).toList(),
  );
}

/// 模型回的草稿 JSON 换成 MOSS 官方布局 JSON(abs_centralized / yxyx,同 Penna 的 mossLayoutJson):
/// 0–1000 的 bbox 按 [width]×[height] 换成像素,再减去宽高的一半(整除);style 接在 caption 前面。
/// 拒绝、不是 JSON、缺 caption 时抛 [LlmError],这张图按失败处理。
String mossLayoutFromReply(String raw, int width, int height) {
  final text = cleanCaption(raw);
  final start = text.indexOf('{'), end = text.lastIndexOf('}');
  if (start < 0 || end <= start) throw LlmError('回复里没有 JSON,原文未改:${_preview(text)}');
  final Object? j;
  try {
    j = jsonDecode(text.substring(start, end + 1));
  } on FormatException {
    throw LlmError('回复的 JSON 解析不了,原文未改:${_preview(text)}');
  }
  final w2 = width ~/ 2, h2 = height ~/ 2;
  int px(Object v, int side) => ((v as num).clamp(0, 1000) * side / 1000).round();
  List<int>? box(List<dynamic> b) {
    final [l, t, r, btm] = [for (final (i, v) in b.indexed) px(v as Object, i.isEven ? width : height)];
    return r > l && btm > t ? [t - h2, l - w2, btm - h2, r - w2] : null;
  }

  final layout = j is Map ? _layout(j, box) : null;
  if (layout == null) throw LlmError('回复缺 summary.caption,原文未改:${_preview(text)}');
  final style = j is Map ? _str((j['summary'] as Map)['style']) : '';
  final caption = layout.caption;
  return layout.copyWith(caption: [if (style.isNotEmpty && !caption.contains(style)) _sentence(style), caption].join(' ')).toJson();
}

String _str(Object? v) => v is String ? v.trim() : '';

String _sentence(String s) => RegExp(r'[.!?。]$').hasMatch(s) ? s : '$s.';

String _preview(String s) => s.length > 80 ? s.substring(0, 80) : s;
