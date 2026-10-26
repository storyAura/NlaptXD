/// 标注文本的分段规则:按半角 / 全角逗号切,写回时用 ", " 连接(和旧版 NLapt 一致)。
library;

final _comma = RegExp(r'[,，]');
final _cjk = RegExp(r'[一-鿿]');

List<String> splitSegments(String text) => [
  for (final s in text.split(_comma))
    if (s.trim().isNotEmpty) s.trim(),
];

String joinSegments(Iterable<String> segments) => segments
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .join(', ');

bool hasCjk(String text) => _cjk.hasMatch(text);

/// 超过四个词的一段按自然语言句子显示(胶囊模式里占满一行)。
bool isSentence(String segment) => segment.trim().split(RegExp(r'\s+')).length > 4;
