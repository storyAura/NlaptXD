import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'cha.dart';
import 'text_io.dart';

/// 一张角色卡的存档:角色名、作品名、锁定的人物卡、主参考图、部件参考图。
typedef SavedCard = ({String name, String series, String text, String ref, List<ChaReference> references});

/// 上次确认的角色卡,存在数据集数据目录 [data] 的 `cha_cards.json`(见 dataset_store.dart),
/// 下次 CHA 可以直接复用(不用再花钱生成)。数据集 [root] 里的图存相对路径,数据集挪了位置也能找回来。
File _file(Directory data) => File('${data.path}${Platform.pathSeparator}cha_cards.json');

String _rel(Directory root, String path) {
  final base = '${root.absolute.path}${Platform.pathSeparator}';
  return path.startsWith(base) ? path.substring(base.length) : path;
}

String _abs(Directory root, String path) =>
    path.isEmpty || File(path).isAbsolute ? path : '${root.absolute.path}${Platform.pathSeparator}$path';

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
          'references': [
            for (final r in c.references) {'path': _rel(root, r.path), 'label': r.label},
          ],
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
    String s(Object? v) => v is String ? v : '';
    final cards = <SavedCard>[
      for (final c in j['cards'] as List? ?? const [])
        if (c is Map && s(c['name']).trim().isNotEmpty && s(c['text']).trim().isNotEmpty)
          (
            name: s(c['name']),
            series: s(c['series']),
            text: s(c['text']),
            ref: File(_abs(root, s(c['ref']))).existsSync() ? _abs(root, s(c['ref'])) : '',
            references: [
              for (final r in c['references'] as List? ?? const [])
                if (r is Map && File(_abs(root, s(r['path']))).existsSync()) (path: _abs(root, s(r['path'])), label: s(r['label'])),
            ],
          ),
    ];
    if (cards.isEmpty) return null;
    return (time: DateTime.tryParse(s(j['time'])) ?? DateTime.now(), cards: cards);
  } on Object {
    return null;
  }
}

/// 一次 CHA 标注里的一张卡:卡文和匹配到的图(相对数据集根目录)。
typedef ChaRunCard = ({String name, String series, String text, List<String> images});

/// 一次 CHA 标注的记录。
typedef ChaRun = ({DateTime time, String model, List<ChaRunCard> cards, int written, int skipped, int failed, bool cancelled});

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
          'cards': [
            for (final c in r.cards) {'name': c.name, 'series': c.series, 'text': c.text, 'images': c.images},
          ],
        },
    ]),
  );
  return List.unmodifiable(kept);
}
