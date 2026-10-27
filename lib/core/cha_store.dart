import 'dart:convert';
import 'dart:io';

import 'backups.dart';
import 'cha.dart';
import 'text_io.dart';

/// 一张角色卡的存档:角色名、作品名、锁定的人物卡、主参考图、部件参考图。
typedef SavedCard = ({String name, String series, String text, String ref, List<ChaReference> references});

/// 上次确认的角色卡,存在数据集的 `.nlapt/cha_cards.json`,下次 CHA 可以直接复用(不用再花钱生成)。
/// 数据集里的图存相对路径,整个数据集挪了位置也能找回来。
File _file(Directory root) => File('${root.path}${Platform.pathSeparator}$sessionDirName${Platform.pathSeparator}cha_cards.json');

String _rel(Directory root, String path) {
  final base = '${root.absolute.path}${Platform.pathSeparator}';
  return path.startsWith(base) ? path.substring(base.length) : path;
}

String _abs(Directory root, String path) =>
    path.isEmpty || File(path).isAbsolute ? path : '${root.absolute.path}${Platform.pathSeparator}$path';

Future<void> saveChaCards(Directory root, List<SavedCard> cards) => writeAtomic(
  _file(root).path,
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
Future<({DateTime time, List<SavedCard> cards})?> loadChaCards(Directory root) async {
  try {
    final f = _file(root);
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
