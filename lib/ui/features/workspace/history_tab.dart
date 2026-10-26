import 'package:flutter/material.dart';

import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'workspace.dart';

String _clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 当前文件的逐步历史:回退只挪位置,不删后面的记录。
class HistoryTab extends StatelessWidget {
  const HistoryTab({super.key, required this.ws, required this.onGoLog});

  final Workspace ws;
  final VoidCallback onGoLog;

  @override
  Widget build(BuildContext context) {
    final h = ws.history!;
    final rows = h.entries.indexed.toList().reversed.toList();
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            Icon(Icons.description_outlined, size: 14, color: NlColors.slate500),
            const SizedBox(width: 6),
            Expanded(child: Text(ws.entry!.name, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: NlColors.slate500))),
            NlButton(label: '操作日志', icon: Icons.history, tone: Tone.ghost, onPressed: onGoLog),
          ],
        ),
        const SizedBox(height: 8),
        for (final (k, (i, e)) in rows.indexed)
          PopIn(
            key: ValueKey('${e.time.microsecondsSinceEpoch}$i'),
            delay: Duration(milliseconds: 20 * k.clamp(0, 10)),
            child: AnimatedContainer(
              duration: Motion.base,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: i == h.cursor ? NlColors.primaryBg : NlColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: i == h.cursor ? NlColors.primaryBorder : NlColors.border),
              ),
              child: Row(
                children: [
                  Text(_clock(e.time), style: TextStyle(fontSize: 11, color: NlColors.slate500)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        Text(e.text.isEmpty ? '(空)' : e.text, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: NlColors.slate500)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  i == h.cursor
                      ? const Pill('当前', tone: PillTone.blue)
                      : NlButton(label: '回退', tone: Tone.outline, onPressed: () => ws.jumpHistory(i)),
                ],
              ),
            ),
          ),
        if (h.entries.length > 1)
          Align(
            alignment: Alignment.centerLeft,
            child: NlButton(label: '清空历史', icon: Icons.delete_sweep_outlined, tone: Tone.ghost, onPressed: ws.clearHistory),
          ),
      ],
    );
  }
}
