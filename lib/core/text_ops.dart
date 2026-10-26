import 'package:flutter/foundation.dart';

import 'captions.dart';

/// 查找条件。匹配是整篇子串,不限于逗号段;查询里的正则符号按字面算。
@immutable
class FindSpec {
  const FindSpec(this.query, {this.caseSensitive = false, this.wholeWord = false});

  final String query;
  final bool caseSensitive;
  final bool wholeWord;

  RegExp? get pattern {
    if (query.isEmpty) return null;
    final body = RegExp.escape(query);
    return RegExp(wholeWord ? '\\b$body\\b' : body, caseSensitive: caseSensitive);
  }

  int count(String text) => pattern?.allMatches(text).length ?? 0;
}

/// 替换全部匹配。替换为空时等于删除,顺带收掉留下的空段和多余逗号。
String replaceIn(String text, FindSpec spec, String replacement) {
  final p = spec.pattern;
  if (p == null) return text;
  final out = text.replaceAll(p, replacement);
  return replacement.isEmpty ? joinSegments(splitSegments(out)) : out;
}

/// 加前缀 / 后缀。[asTag] 时作为独立标签:用逗号连接,已经在那一头就跳过
/// (按边界判断:`caterpillar` 不算已有 `cat`)。
String addAffix(String text, String affix, {required bool atStart, required bool asTag}) {
  if (!asTag) return atStart ? '$affix$text' : '$text$affix';
  final add = affix.trim();
  if (add.isEmpty) return text;
  final segments = splitSegments(text);
  if (segments.isEmpty) return add;
  final edge = atStart ? segments.first : segments.last;
  if (edge == add) return text;
  return joinSegments(atStart ? [add, ...segments] : [...segments, add]);
}
