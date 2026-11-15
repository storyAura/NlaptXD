import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/cha_store.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../workspace/workspace.dart';

String _when(DateTime t) {
  String two(int n) => '$n'.padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// 「CHA 记录」:这个数据集做过的每次 CHA 标注,从最近一次开始,‹ › 按顺序往前翻;
/// 每张角色卡的全文和它写进去的图(点图跳过去)。
Future<void> showChaRuns(BuildContext context, Workspace ws) =>
    showDialog<void>(context: context, builder: (_) => _ChaRunsDialog(ws: ws));

class _ChaRunsDialog extends StatefulWidget {
  const _ChaRunsDialog({required this.ws});

  final Workspace ws;

  @override
  State<_ChaRunsDialog> createState() => _ChaRunsDialogState();
}

class _ChaRunsDialogState extends State<_ChaRunsDialog> {
  late final List<ChaRun> _runs = widget.ws.chaRuns;
  late int _at = _runs.length - 1;

  Future<void> _copy(String text, String done) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showToast(context, done);
  }

  void _open(int index) {
    Navigator.pop(context);
    widget.ws.select(index);
  }

  @override
  Widget build(BuildContext context) {
    final r = _runs[_at];
    final label = TextStyle(fontSize: 11.5, color: NlColors.slate500);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 620, maxHeight: MediaQuery.sizeOf(context).height * .82),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Text('CHA 记录', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Pill('第 ${_at + 1} / ${_runs.length} 次', tone: PillTone.blue),
                const Spacer(),
                NlIconButton(Icons.chevron_left, tooltip: '上一次', onPressed: _at > 0 ? () => setState(() => _at--) : null),
                NlIconButton(Icons.chevron_right, tooltip: '下一次', onPressed: _at < _runs.length - 1 ? () => setState(() => _at++) : null),
                const SizedBox(width: 4),
                NlIconButton(Icons.close, tooltip: '关闭', onPressed: () => Navigator.pop(context)),
              ]),
              const SizedBox(height: 4),
              Text(
                [
                  _when(r.time),
                  if (r.model.isNotEmpty) r.model,
                  '写入 ${r.written}',
                  if (r.skipped > 0) '没归类 ${r.skipped}',
                  if (r.failed > 0) '失败 ${r.failed}',
                  if (r.cancelled) '已取消',
                ].join(' · '),
                style: label,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: AnimatedSwitcher(
                  duration: Motion.of(context, Motion.base),
                  child: ListView(
                    key: ValueKey(_at),
                    shrinkWrap: true,
                    children: [
                      for (final (i, c) in r.cards.indexed)
                        PopIn(
                          delay: Duration(milliseconds: 40 * i),
                          child: Padding(padding: const EdgeInsets.only(bottom: 8), child: _card(i, c)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: NlButton(
                  label: '复制全部人物卡',
                  tone: Tone.outline,
                  onPressed: () => _copy(r.cards.map((c) => c.text).join('\n\n'), '已复制全部人物卡'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(int i, ChaRunCard c) {
    final ws = widget.ws;
    final index = {for (final (k, e) in ws.entries.indexed) ws.relImage(e): k};
    return NlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('卡 ${i + 1} · ${c.name}${c.series.isEmpty ? '' : ' · ${c.series}'}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Pill('写入 ${c.images.length} 张', tone: PillTone.blue),
            const SizedBox(width: 6),
            NlButton(label: '复制', icon: Icons.content_copy_outlined, tone: Tone.ghost, onPressed: () => _copy(c.text, '已复制卡 ${i + 1}')),
          ]),
          const SizedBox(height: 6),
          SelectableText(c.text, style: TextStyle(fontSize: 12, color: NlColors.slate700, height: 1.5)),
          if (c.images.isNotEmpty) ...[
            const SizedBox(height: 8),
            // ponytail: 图多时只列前 40 张,要全看再加展开。
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in c.images.take(40))
                NlChip(
                  label: p.split(RegExp(r'[\\/]')).last,
                  selected: false,
                  onTap: index[p] == null ? null : () => _open(index[p]!),
                ),
              if (c.images.length > 40) Text('等 ${c.images.length} 张', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
            ]),
          ],
        ],
      ),
    );
  }
}
