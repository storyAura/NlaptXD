import 'openai_client.dart';

/// 模型回答整理成干净的标注,并拦下「拒绝」类回答(不写进数据集)。
/// 移植自旧版 NLapt 的 nlapt/llm/cleaning.py,话术表原样搬来。

const _refusalPrefixes = ["i'm sorry", "i am sorry", "i apologize", "i apologise", "i cannot", "i can't", "i can not", "i'm unable", "i am unable", "i won't", "i will not", "as an ai", "sorry, but", "unfortunately, i", "抱歉", "很抱歉", "对不起", "我不能", "我无法", "作为ai", "作为一个ai", "作为人工智能"];
const _refusalMarkers = ["cannot assist", "can't assist", "unable to assist", "cannot help with", "can't help with", "against my guidelines", "content policy", "i must decline", "无法协助", "无法帮助", "不能提供", "无法提供"];
const _labels = ["caption", "output", "result", "标注", "输出"];
const _labelSeparators = [":", "："];
const _quotePairs = [("\"", "\""), ("'", "'"), ("“", "”"), ("‘", "’"), ("「", "」")];

/// 去掉整段外面的代码块、成对引号、「Caption:」这类前缀(反复做到不再变)。
/// 再检查是不是拒绝;是拒绝或洗完是空的,抛 [LlmError],这张图按失败处理、保留原文。
String cleanCaption(String raw) {
  final text = unwrapReply(raw);
  if (text.isEmpty) throw const LlmError('模型返回了空内容(可能被安全策略拦截),原文未改');
  final lower = text.toLowerCase();
  if (_refusalPrefixes.any(lower.startsWith) || _refusalMarkers.any(lower.contains)) {
    final preview = text.length > 80 ? text.substring(0, 80) : text;
    throw LlmError('模型拒绝了这张图(疑似触发安全拦截),原文未改:$preview');
  }
  return text;
}

/// 只剥外壳(代码块、引号、前缀),不查拒绝:译文本来就可能以「抱歉」开头。
String unwrapReply(String raw) {
  var text = raw.trim();
  for (var i = 0; i < 10; i++) {
    final before = text;
    text = _stripLabel(_stripQuotes(_stripFence(text).trim()).trim()).trim();
    if (text == before) break;
  }
  return text;
}

String _stripFence(String text) {
  const fence = '```';
  if (!text.startsWith(fence) || !text.endsWith(fence)) return text;
  final lines = text.split('\n');
  if (lines.length == 1) return text.length >= 6 ? text.substring(3, text.length - 3) : '';
  if (lines.last.trim() != fence) return text;
  return lines.sublist(1, lines.length - 1).join('\n');
}

/// 只剥包住整段的那一对:里面还出现收尾引号的(如 "blue eyes" and "red hair")不动。
String _stripQuotes(String text) {
  while (text.length >= 2) {
    final pair = _quotePairs.where((p) => text.startsWith(p.$1) && text.endsWith(p.$2)).firstOrNull;
    if (pair == null) break;
    final inner = text.substring(pair.$1.length, text.length - pair.$2.length);
    if (inner.contains(pair.$2)) break;
    text = inner.trim();
  }
  return text;
}

String _stripLabel(String text) {
  final lower = text.toLowerCase();
  for (final label in _labels) {
    for (final sep in _labelSeparators) {
      if (lower.startsWith('$label$sep')) return text.substring(label.length + sep.length).trimLeft();
    }
  }
  return text;
}
