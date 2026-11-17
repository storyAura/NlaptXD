import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'cha.dart';
import 'text_io.dart';

/// 一张角色卡的存档:角色名、作品名、锁定的人物卡、主参考图、部件参考图、绑定的子文件夹。
typedef SavedCard = ({String name, String series, String text, String ref, List<ChaReference> references, ChaBinding? bind});

/// 上次确认的角色卡,存在数据集数据目录 [data] 的 `cha_cards.json`(见 dataset_store.dart),
/// 下次 CHA 可以直接复用(不用再花钱生成)。数据集 [root] 里的图存相对路径,数据集挪了位置也能找回来。
File _file(Directory data) => File('${data.path}${Platform.pathSeparator}cha_cards.json');

String _rel(Directory root, String path) {
  final base = '${root.absolute.path}${Platform.pathSeparator}';
  return path.startsWith(base) ? path.substring(base.length) : path;
}

String _abs(Directory root, String path) =>
    path.isEmpty || File(path).isAbsolute ? path : '${root.absolute.path}${Platform.pathSeparator}$path';

String _s(Object? v) => v is String ? v : '';

/// 存的相对路径换回绝对路径;图已经不在了给空。
String _existing(Directory root, Object? path) {
  final p = _abs(root, _s(path));
  return p.isNotEmpty && File(p).existsSync() ? p : '';
}

List<Map<String, String>> _refsJson(Directory root, List<ChaReference> refs) => [
  for (final r in refs) {'path': _rel(root, r.path), 'label': r.label},
];

List<ChaReference> _refsFrom(Directory root, Object? j) => [
  for (final r in j is List ? j : const [])
    if (r is Map && _existing(root, r['path']).isNotEmpty) (path: _existing(root, r['path']), label: _s(r['label'])),
];

Map<String, Object>? _bindJson(ChaBinding? b) => b == null ? null : {'folder': b.folder, 'solo': b.solo, 'refs': b.refs, 'text': b.text};

ChaBinding? _bindFrom(Object? j) =>
    j is Map ? (folder: _s(j['folder']), solo: j['solo'] == true, refs: j['refs'] != false, text: j['text'] != false) : null;

Future<void> saveChaCards(Directory data, Directory root, List<SavedCard> cards) => writeAtomic(
  _file(data).path,
  const JsonEncoder.withIndent('  ').convert({
    'time': DateTime.now().toIso8601String(),
    'cards': [
      for (final c in cards)
        {
          'name': c.name,
          'series': c.series,
          'text': c.text,
          'ref': _rel(root, c.ref),
          'references': _refsJson(root, c.references),
          'bind': ?_bindJson(c.bind),
        },
    ],
  }),
);

/// 读不到或读坏了返回 null(不挡 CHA,只是不提示复用)。找不到的参考图去掉。
Future<({DateTime time, List<SavedCard> cards})?> loadChaCards(Directory data, Directory root) async {
  try {
    final f = _file(data);
    if (!await f.exists()) return null;
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    final cards = <SavedCard>[
      for (final c in j['cards'] as List? ?? const [])
        if (c is Map && _s(c['name']).trim().isNotEmpty && _s(c['text']).trim().isNotEmpty)
          (
            name: _s(c['name']),
            series: _s(c['series']),
            text: _s(c['text']),
            ref: _existing(root, c['ref']),
            references: _refsFrom(root, c['references']),
            bind: _bindFrom(c['bind']),
          ),
    ];
    if (cards.isEmpty) return null;
    return (time: DateTime.tryParse(_s(j['time'])) ?? DateTime.now(), cards: cards);
  } on Object {
    return null;
  }
}

/// 向导里的一张角色卡草稿:三个候选全留着(没选的也算记录),[pick] = -1 是还没选。
typedef DraftCard = ({
  String name,
  String series,
  String ref,
  List<ChaReference> references,
  List<String> cands,
  int pick,
  ChaBinding? bind,
});

/// CHA 向导的一份草稿:编辑时自动存,突然关机下次也能接着改;[done] = 已经点了开始。
typedef ChaDraft = ({String id, DateTime time, bool done, int step, List<DraftCard> cards});

const chaDraftsKeep = 20;

File _draftsFile(Directory data) => File('${data.path}${Platform.pathSeparator}cha_drafts.json');

/// 读草稿记录(旧的在前)。读不到或读坏了返回空表;找不到的参考图去掉。
Future<List<ChaDraft>> loadChaDrafts(Directory data, Directory root) async {
  try {
    final f = _draftsFile(data);
    if (!await f.exists()) return const [];
    return [
      for (final d in jsonDecode(await f.readAsString()) as List)
        if (d is Map)
          (
            id: _s(d['id']),
            time: DateTime.tryParse(_s(d['time'])) ?? DateTime(2000),
            done: d['done'] == true,
            step: (d['step'] is int ? d['step'] as int : 1).clamp(1, 3),
            cards: [
              for (final c in d['cards'] as List? ?? const [])
                if (c is Map)
                  (
                    name: _s(c['name']),
                    series: _s(c['series']),
                    ref: _existing(root, c['ref']),
                    references: _refsFrom(root, c['references']),
                    cands: [for (var i = 0; i < 3; i++) _s((c['cands'] as List?)?.elementAtOrNull(i))],
                    pick: c['pick'] is int ? c['pick'] as int : -1,
                    bind: _bindFrom(c['bind']),
                  ),
            ],
          ),
    ];
  } on Object {
    return const [];
  }
}

/// 放进一份草稿(同 [ChaDraft.id] 的换掉),按时间排好,只留最近 [chaDraftsKeep] 份。返回新表。
List<ChaDraft> withDraft(List<ChaDraft> drafts, ChaDraft draft) {
  final all = [for (final d in drafts) if (d.id != draft.id) d, draft]..sort((a, b) => a.time.compareTo(b.time));
  return List.unmodifiable(all.sublist(math.max(0, all.length - chaDraftsKeep)));
}

Future<void> saveChaDrafts(Directory data, Directory root, List<ChaDraft> kept) async {
  await writeAtomic(
    _draftsFile(data).path,
    const JsonEncoder.withIndent('  ').convert([
      for (final d in kept)
        {
          'id': d.id,
          'time': d.time.toIso8601String(),
          'done': d.done,
          'step': d.step,
          'cards': [
            for (final c in d.cards)
              {
                'name': c.name,
                'series': c.series,
                'ref': _rel(root, c.ref),
                'references': _refsJson(root, c.references),
                'cands': c.cands,
                'pick': c.pick,
                'bind': ?_bindJson(c.bind),
              },
          ],
        },
    ]),
  );
}

/// 一次 CHA 标注里的一张卡:卡文和匹配到的图(相对数据集根目录)。
typedef ChaRunCard = ({String name, String series, String text, List<String> images});

/// 一次 CHA 标注的记录。
/// [missed]:这批里没标上的图(没认出角色、失败、取消后没推到的),相对数据集根目录;旧记录没有这项,是空表。
typedef ChaRun = ({
  DateTime time,
  String model,
  List<ChaRunCard> cards,
  int written,
  int skipped,
  int failed,
  bool cancelled,
  List<String> missed,
});

const chaRunsKeep = 30;

File _runsFile(Directory data) => File('${data.path}${Platform.pathSeparator}cha_runs.json');

/// 读每次 CHA 标注的记录(旧的在前)。读不到或读坏了返回空表。
Future<List<ChaRun>> loadChaRuns(Directory data) async {
  try {
    final f = _runsFile(data);
    if (!await f.exists()) return const [];
    String s(Object? v) => v is String ? v : '';
    int n(Object? v) => v is int ? v : 0;
    return [
      for (final r in jsonDecode(await f.readAsString()) as List)
        if (r is Map)
          (
            time: DateTime.tryParse(s(r['time'])) ?? DateTime(2000),
            model: s(r['model']),
            cards: [
              for (final c in r['cards'] as List? ?? const [])
                if (c is Map)
                  (name: s(c['name']), series: s(c['series']), text: s(c['text']), images: [for (final i in c['images'] as List? ?? const []) s(i)]),
            ],
            written: n(r['written']),
            skipped: n(r['skipped']),
            failed: n(r['failed']),
            cancelled: r['cancelled'] == true,
            missed: [for (final m in r['missed'] as List? ?? const []) s(m)],
          ),
    ];
  } on Object {
    return const [];
  }
}

/// 把 [run] 加到记录末尾,只留最近 [chaRunsKeep] 次。返回新的整张表。
Future<List<ChaRun>> appendChaRun(Directory data, ChaRun run) async {
  final all = [...await loadChaRuns(data), run];
  final kept = all.sublist(math.max(0, all.length - chaRunsKeep));
  await writeAtomic(
    _runsFile(data).path,
    const JsonEncoder.withIndent('  ').convert([
      for (final r in kept)
        {
          'time': r.time.toIso8601String(),
          'model': r.model,
          'written': r.written,
          'skipped': r.skipped,
          'failed': r.failed,
          'cancelled': r.cancelled,
          'missed': r.missed,
          'cards': [
            for (final c in r.cards) {'name': c.name, 'series': c.series, 'text': c.text, 'images': c.images},
          ],
        },
    ]),
  );
  return List.unmodifiable(kept);
}
