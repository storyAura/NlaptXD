import 'cl_tagger.dart';

/// Danbooru 角色对照表(danbooru_character_tags.csv):查一个角色的整个家族(父角色、子角色、同级)。
/// 移植自旧版 NLapt 的 nlapt/local/character_index.py。旧版没去掉文件开头的 BOM,
/// 第一列名对不上,表一行都没读进来,所以从来只显示识别到的那个角色;这里修好了。
class CharacterIndex {
  CharacterIndex._(this._byTag, this._children);

  final Map<String, CharacterEntry> _byTag;
  final Map<String, List<CharacterEntry>> _children;

  int get length => _byTag.length;

  /// 解析整张表(要表头)。表有十几 MB,放 isolate 里跑。
  factory CharacterIndex.parse(String csv) {
    final rows = parseCsv(csv.startsWith('﻿') ? csv.substring(1) : csv);
    if (rows.isEmpty) return CharacterIndex._({}, {});
    final head = rows.first;
    int col(String name) => head.indexOf(name);
    final (tagAt, seriesAt, parentAt, countAt) = (col('character_tag'), col('copyright'), col('parent_tag'), col('post_count'));
    String cell(List<String> r, int i) => i >= 0 && i < r.length ? r[i] : '';
    final byTag = <String, CharacterEntry>{};
    final children = <String, List<CharacterEntry>>{};
    for (final r in rows.skip(1)) {
      final tag = normalizeTag(cell(r, tagAt));
      if (tag.isEmpty) continue;
      final e = (
        tag: tag,
        copyright: normalizeTag(cell(r, seriesAt)),
        parent: normalizeTag(cell(r, parentAt)),
        posts: int.tryParse(cell(r, countAt).trim()) ?? 0,
      );
      byTag[tag] = e;
      if (e.parent.isNotEmpty) (children[e.parent] ??= []).add(e);
    }
    return CharacterIndex._(byTag, children);
  }

  CharacterEntry? lookup(String tag) => _byTag[normalizeTag(tag)];

  /// 最上层的祖先 + 它的所有后代 + 自己,按帖子数从多到少。查不到返回空。
  List<CharacterEntry> family(String tag) {
    final start = lookup(tag);
    if (start == null) return const [];
    var root = start;
    final seen = {start.tag};
    while (root.parent.isNotEmpty) {
      final p = _byTag[root.parent];
      if (p == null || !seen.add(p.tag)) break;
      root = p;
    }
    final found = <String, CharacterEntry>{};
    final stack = [root];
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      if (found.containsKey(cur.tag)) continue;
      found[cur.tag] = cur;
      stack.addAll(_children[cur.tag] ?? const []);
    }
    found[start.tag] ??= start;
    return found.values.toList()..sort((a, b) => b.posts.compareTo(a.posts));
  }

  /// [entry] 相对识别到的 [detected] 是什么关系。
  CharacterRelation relationOf(CharacterEntry entry, String detected) {
    if (entry.tag == detected) return CharacterRelation.detected;
    final seen = <String>{};
    for (var c = _byTag[detected]; c != null && c.parent.isNotEmpty && seen.add(c.tag); c = _byTag[c.parent]) {
      if (c.parent == entry.tag) return CharacterRelation.parent;
    }
    seen.clear();
    for (CharacterEntry? c = entry; c != null && c.parent.isNotEmpty && seen.add(c.tag); c = _byTag[c.parent]) {
      if (c.parent == detected) return CharacterRelation.child;
    }
    return CharacterRelation.sibling;
  }
}

typedef CharacterEntry = ({String tag, String copyright, String parent, int posts});

enum CharacterRelation {
  detected(''),
  parent('父标签'),
  child('子标签'),
  sibling('同级');

  const CharacterRelation(this.label);

  final String label;
}

/// 给角色卡填的一个候选。
typedef CharacterCandidate = ({String name, String series, double prob, CharacterRelation relation});

/// 识别结果展开成候选:每个识别到的角色连同它的家族,去重;作品名查不到时用概率最高的作品标签。
List<CharacterCandidate> expandCandidates(
  ({List<ScoredTag> characters, List<ScoredTag> copyrights}) tags,
  CharacterIndex index,
) {
  final fallback = tags.copyrights.isEmpty ? '' : normalizeTag(tags.copyrights.first.tag);
  final seen = <String>{};
  final out = <CharacterCandidate>[];
  for (final s in tags.characters.take(clMaxDetected)) {
    final detected = normalizeTag(s.tag);
    final members = index.family(detected);
    if (members.isEmpty) {
      if (seen.add(detected)) {
        out.add((name: displayName(s.tag), series: displaySeries(fallback), prob: s.prob, relation: CharacterRelation.detected));
      }
      continue;
    }
    for (final m in members) {
      if (!seen.add(m.tag)) continue;
      out.add((
        name: displayName(m.tag),
        series: displaySeries(m.copyright.isEmpty ? fallback : m.copyright),
        prob: m.tag == detected ? s.prob : 0,
        relation: index.relationOf(m, detected),
      ));
    }
  }
  return out;
}

/// Danbooru 写法:去首尾空白、小写、空格换下划线。
String normalizeTag(String text) => text.trim().toLowerCase().replaceAll(' ', '_');

/// 给人看的角色名:下划线换空格,去掉末尾的 (限定词),再按 Python 的 str.title() 大写。
String displayName(String tag) {
  final text = tag.trim().replaceAll('_', ' ').replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
  return text.isEmpty ? tag : pyTitle(text);
}

/// 给人看的作品名:去掉末尾的 (series)。
String displaySeries(String copyright) {
  final text = copyright.trim().replaceAll('_', ' ').replaceFirst(RegExp(r'\s*\(series\)\s*$', caseSensitive: false), '').trim();
  return text.isEmpty ? '' : pyTitle(text);
}

/// Python 的 str.title():前一个字不是有大小写的字母时大写,否则小写(o'neill → O'Neill)。
String pyTitle(String s) {
  final out = StringBuffer();
  var prevCased = false;
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final cased = c.toUpperCase() != c.toLowerCase();
    out.write(cased ? (prevCased ? c.toLowerCase() : c.toUpperCase()) : c);
    prevCased = cased;
  }
  return out.toString();
}

/// 带引号的 CSV(字段里可以有逗号、换行、"" 转义的引号)。
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c != '"') {
        field.write(c);
      } else if (i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = false;
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) rows.add([...row, field.toString()]);
  return rows;
}
