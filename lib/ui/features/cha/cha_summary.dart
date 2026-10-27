import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/cha.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../workspace/workspace.dart';

/// CHA 跑完后的汇总:每张卡匹配了几张(可复制卡文)、没归类的(没写)、失败的(原文未改)。
Future<void> showChaSummary(
  BuildContext context, {
  required List<ChaCard> roster,
  required Map<int, int> counts,
  required InferJob job,
  required String model,
}) => showDialog<void>(
  context: context,
  builder: (context) {
    final label = TextStyle(fontSize: 11.5, color: NlColors.slate500);
    Future<void> copy(String text, String done) async {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) showToast(context, done);
    }

    Widget names(List<String> list) => Text(
      list.take(12).join('、') + (list.length > 12 ? ' 等 ${list.length} 张' : ''),
      style: TextStyle(fontSize: 12, color: NlColors.slate700),
    );
    return AlertDialog(
      title: Text(job.cancelled ? 'CHA标注已取消' : 'CHA标注完成', style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 560,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text('写入 ${job.changes.length} 张 · 没归类 ${job.skipped.length} · 失败 ${job.failed} · 整批画面 $model', style: label),
            const SizedBox(height: 12),
            for (final (i, c) in roster.indexed)
              PopIn(
                delay: Duration(milliseconds: 40 * i),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: NlCard(
                    child: Row(children: [
                      Expanded(
                        child: Text('卡 ${i + 1} · ${c.name}${c.series.isEmpty ? '' : ' · ${c.series}'}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      Pill('匹配 ${counts[i] ?? 0} 张', tone: PillTone.blue),
                      const SizedBox(width: 6),
                      NlButton(label: '复制', icon: Icons.content_copy_outlined, tone: Tone.ghost, onPressed: () => copy(c.text, '已复制卡 ${i + 1}')),
                    ]),
                  ),
                ),
              ),
            if (job.skipped.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('没归类 ${job.skipped.length} 张(不属于任何角色卡,没写)', style: label),
              const SizedBox(height: 4),
              names([for (final e in job.skipped) e.name]),
            ],
            if (job.failed > 0) ...[
              const SizedBox(height: 10),
              Text('失败 ${job.failed} 张(重试一次仍失败,原文未改)· 原因:', style: label.copyWith(color: NlColors.diffDelText)),
              const SizedBox(height: 4),
              for (final (reason, n) in job.failureReasons.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Pill('$n 张', tone: PillTone.bad),
                    const SizedBox(width: 6),
                    Expanded(child: SelectableText(reason, style: TextStyle(fontSize: 12, color: NlColors.slate700))),
                  ]),
                ),
              const SizedBox(height: 4),
              names([for (final e in job.failedEntries) e.name]),
            ],
          ],
        ),
      ),
      actions: [
        NlButton(label: '复制全部人物卡', tone: Tone.outline, onPressed: () => copy(roster.map((c) => c.text).join('\n\n'), '已复制全部人物卡')),
        NlButton(label: '关闭', tone: Tone.primary, onPressed: () => Navigator.pop(context)),
      ],
    );
  },
);
