import 'package:flutter/material.dart';

import '../../../core/captions.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'workspace.dart';

/// 推理 / 翻译结果和现在的标注逐段对比(删的红、增的绿),采纳才写进编辑区。
class DiffCard extends StatelessWidget {
  const DiffCard({super.key, required this.ws, required this.result});

  final Workspace ws;
  final PendingResult result;

  @override
  Widget build(BuildContext context) {
    final old = splitSegments(ws.textOf(ws.entry!));
    final next = splitSegments(result.text);
    final del = old.where((s) => !next.contains(s)).toList();
    final add = next.where((s) => !old.contains(s)).toList();
    Widget line(String s, bool added) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: added ? NlColors.diffAdd : NlColors.diffDel, borderRadius: BorderRadius.circular(6)),
      child: Text(
        s,
        style: monoStyle.copyWith(
          color: added ? NlColors.diffAddText : NlColors.diffDelText,
          decoration: added ? null : TextDecoration.lineThrough,
          decorationColor: NlColors.diffDelText,
        ),
      ),
    );
    return NlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(result.translated ? Icons.translate : Icons.auto_awesome_outlined, size: 15, color: NlColors.primary),
            const SizedBox(width: 6),
            Text(result.translated ? '翻译结果' : '推理结果', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            const Spacer(),
            Flexible(child: Pill(result.model)),
          ]),
          const SizedBox(height: 10),
          for (final (i, s) in del.indexed) PopIn(delay: Duration(milliseconds: 30 * i), child: line(s, false)),
          for (final (i, s) in add.indexed) PopIn(delay: Duration(milliseconds: 30 * (del.length + i)), child: line(s, true)),
          if (del.isEmpty && add.isEmpty) Text('和现在的标注一样', style: TextStyle(fontSize: 12, color: NlColors.slate500)),
          const SizedBox(height: 6),
          Text('保留 ${old.length - del.length} 段 · 删 ${del.length} · 增 ${add.length}', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
          const SizedBox(height: 10),
          Row(children: [
            NlButton(label: '采纳', icon: Icons.check, tone: Tone.primary, onPressed: ws.acceptPending),
            const SizedBox(width: 6),
            NlButton(label: '驳回', tone: Tone.outline, onPressed: ws.rejectPending),
          ]),
        ],
      ),
    );
  }
}
