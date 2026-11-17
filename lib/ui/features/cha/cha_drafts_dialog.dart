import 'package:flutter/material.dart';

import '../../../core/cha_store.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

String _when(DateTime t) {
  String two(int n) => '$n'.padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// 角色卡草稿记录:最近的在上面,点一份打开(接着改 / 回看候选 / 复用)。
Future<ChaDraft?> showChaDrafts(BuildContext context, List<ChaDraft> drafts) => showDialog<ChaDraft>(
  context: context,
  builder: (context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * .7),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Text('角色卡草稿', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Pill('${drafts.length} 份', tone: PillTone.blue),
              const Spacer(),
              NlIconButton(Icons.close, tooltip: '关闭', onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 4),
            Text('编辑时自动保存 · 留最近 $chaDraftsKeep 份', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final d in drafts.reversed)
                    Padding(padding: const EdgeInsets.only(bottom: 8), child: _row(context, d)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

Widget _row(BuildContext context, ChaDraft d) {
  final names = [for (final c in d.cards) c.name.trim().isEmpty ? '(未命名)' : c.name.trim()];
  final made = d.cards.fold(0, (n, c) => n + c.cands.where((t) => t.trim().isNotEmpty).length);
  return Hover(
    cursor: SystemMouseCursors.click,
    builder: (hover) => GestureDetector(
      onTap: () => Navigator.pop(context, d),
      child: NlCard(
        borderColor: hover ? NlColors.primaryBorder : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(_when(d.time), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Pill(d.done ? '已开始标注' : '未完成', tone: d.done ? PillTone.blue : PillTone.warn),
              const Spacer(),
              Text('${d.cards.length} 张卡 · $made 个候选', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
            ]),
            const SizedBox(height: 4),
            Text(names.join('、'), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: NlColors.slate700)),
          ],
        ),
      ),
    ),
  );
}
