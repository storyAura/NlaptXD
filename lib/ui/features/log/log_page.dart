import 'package:flutter/material.dart';

import '../../../core/backups.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../workspace/workspace.dart';

String _when(DateTime t) {
  String two(int n) => '$n'.padLeft(2, '0');
  return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// 操作日志:每次批量操作一张卡,可整批回滚(旧版承诺过、但界面从没接上的那一项)。
class LogPage extends StatefulWidget {
  const LogPage({super.key, required this.ws});

  final Workspace ws;

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  int? _asking;
  bool _busy = false;

  Future<void> _rollback(OpRecord r) async {
    setState(() => _busy = true);
    try {
      final n = await widget.ws.rollback(r.id);
      if (mounted) showToast(context, '已回滚 $n 个文件 · ${r.title}');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _asking = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.ws,
    builder: (context, _) {
      final records = widget.ws.oplog?.records ?? const <OpRecord>[];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NlBar(
            children: [
              const Text('操作日志', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              Text('批量操作 · 自动备份', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
              const Spacer(),
              Text('快照存在「文档/NLaptXD/datasets」· 保留 $defaultKeep 份', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
            ],
          ),
          Expanded(
            child: records.isEmpty
                ? Center(
                    child: Text(widget.ws.root == null ? '先在标注台打开一个数据集' : '还没有批量操作',
                        style: TextStyle(color: NlColors.slate500)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(18),
                    itemCount: records.length,
                    itemBuilder: (_, i) => Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: PopIn(
                          key: ValueKey(records[i].id),
                          delay: Duration(milliseconds: 30 * i.clamp(0, 8)),
                          child: Padding(padding: const EdgeInsets.only(bottom: 10), child: _card(records[i])),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      );
    },
  );

  Widget _card(OpRecord r) {
    final (label, tone) = switch (r.status) {
      OpStatus.done => ('已完成', PillTone.ok),
      OpStatus.partial => ('已取消', PillTone.warn),
      OpStatus.rolledBack => ('已回滚', PillTone.mute),
    };
    return NlCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: NlColors.primaryBg, borderRadius: BorderRadius.circular(10)),
                child: Icon(
                  r.title.contains('推标') ? Icons.auto_awesome_outlined : r.title.contains('替换') ? Icons.find_replace : Icons.format_indent_increase,
                  size: 18,
                  color: NlColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(text: r.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(text: ' · ${r.detail}', style: TextStyle(color: NlColors.slate500)),
                    ])),
                    Text('${_when(r.time)} · ${r.changes.length} 个文件 · ${r.backup}',
                        overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
                  ],
                ),
              ),
              Pill(label, tone: tone),
              if (r.status != OpStatus.rolledBack) ...[
                const SizedBox(width: 8),
                NlButton(label: '整批回滚', icon: Icons.undo, tone: Tone.outline, onPressed: () => setState(() => _asking = r.id)),
              ],
            ],
          ),
          AnimatedSize(
            duration: Motion.base,
            curve: Motion.expand,
            child: _asking != r.id
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: NlCard(
                      color: NlColors.lock,
                      borderColor: NlColors.lockBorder,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('${r.changes.length} 个文件恢复到这次操作之前;之后对它们的修改也会被覆盖。',
                                style: TextStyle(fontSize: 12.5, color: NlColors.lockText)),
                          ),
                          NlButton(label: '确认回滚', tone: Tone.primary, busy: _busy, onPressed: () => _rollback(r)),
                          const SizedBox(width: 6),
                          NlButton(label: '取消', tone: Tone.outline, onPressed: () => setState(() => _asking = null)),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
