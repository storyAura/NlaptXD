import 'package:flutter/material.dart';

import '../../../core/text_ops.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'side_panel.dart';
import 'workspace.dart';

/// 批量修改:查找替换、前缀 / 后缀。都写盘、都能在操作日志整批回滚。
class BatchEditTab extends StatefulWidget {
  const BatchEditTab({super.key, required this.ws, required this.onGoLog});

  final Workspace ws;
  final VoidCallback onGoLog;

  @override
  State<BatchEditTab> createState() => _BatchEditTabState();
}

class _BatchEditTabState extends State<BatchEditTab> {
  Workspace get ws => widget.ws;
  Scope _scope = Scope.all;
  final _find = TextEditingController();
  final _repl = TextEditingController();
  final _affix = TextEditingController();
  bool _cs = false, _word = false, _atStart = true, _asTag = true, _running = false;

  @override
  void dispose() {
    _find.dispose();
    _repl.dispose();
    _affix.dispose();
    super.dispose();
  }

  FindSpec get _spec => FindSpec(_find.text, caseSensitive: _cs, wholeWord: _word);

  Future<void> _apply(Future<int> Function() op, String noneMessage) async {
    setState(() => _running = true);
    try {
      final n = await op();
      if (!mounted) return;
      if (n == 0) return showToast(context, noneMessage, warn: true);
      final id = ws.oplog!.records.first.id;
      showToast(context, '已写入 $n 个文件', action: ('整批撤销', () => ws.rollback(id)));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ws.scopeEntries(_scope);
    final total = list.fold(0, (s, e) => s + _spec.count(ws.textOf(e)));
    final files = list.where((e) => _spec.count(ws.textOf(e)) > 0).length;
    TextField field(TextEditingController c, String hint) => TextField(
      controller: c,
      style: monoStyle.copyWith(height: 1.3),
      onChanged: (_) => setState(() {}),
      decoration: fieldDecoration(hint),
    );
    final countStyle = TextStyle(fontSize: 11.5, color: NlColors.slate500);
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const Label('应用范围'),
        scopeChips(ws, const [Scope.current, Scope.folder, Scope.selected, Scope.all], _scope, (s) => setState(() => _scope = s)),
        const SizedBox(height: 14),
        PopIn(
          child: _Section(
            icon: Icons.find_replace,
            title: '查找替换',
            children: [
              field(_find, '查找,如 long hair'),
              field(_repl, '替换为(留空即删除)'),
              Row(
                children: [
                  NlChip(label: 'Aa 大小写', selected: _cs, onTap: () => setState(() => _cs = !_cs)),
                  const SizedBox(width: 6),
                  NlChip(label: '整词', selected: _word, onTap: () => setState(() => _word = !_word)),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: Motion.snap,
                      child: Text(
                        _find.text.isEmpty ? '输入要查找的文字' : total == 0 ? '没有匹配' : '匹配 $total 处 · $files 个文件',
                        key: ValueKey('$total/$files/${_find.text.isEmpty}'),
                        style: total > 0 ? countStyle.copyWith(color: NlColors.primary) : countStyle,
                      ),
                    ),
                  ),
                  NlButton(
                    label: '全部替换',
                    tone: Tone.primary,
                    busy: _running,
                    onPressed: total == 0 ? null : () => _apply(() => ws.findReplace(_scope, _spec, _repl.text), '没有匹配'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PopIn(
          delay: const Duration(milliseconds: 40),
          child: _Section(
            icon: Icons.format_indent_increase,
            title: '前缀 / 后缀',
            children: [
              field(_affix, '如 aoba, masterpiece'),
              Row(
                children: [
                  Seg<bool>(
                    value: _atStart,
                    onChanged: (v) => setState(() => _atStart = v),
                    items: const [(true, '加到开头', null), (false, '加到结尾', null)],
                  ),
                  const Spacer(),
                  NlChip(label: '独立标签', selected: _asTag, onTap: () => setState(() => _asTag = !_asTag)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: Text(_asTag ? '已有则跳过' : '按原样拼接', style: countStyle)),
                  NlButton(
                    label: '应用',
                    tone: Tone.primary,
                    busy: _running,
                    onPressed: _affix.text.trim().isEmpty
                        ? null
                        : () => _apply(() => ws.addAffixTo(_scope, _affix.text, atStart: _atStart, asTag: _asTag), '范围内都已包含'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Center(child: NlButton(label: '操作日志', icon: Icons.history, tone: Tone.ghost, onPressed: widget.onGoLog)),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.children});

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => NlCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: NlColors.slate700),
            const SizedBox(width: 6),
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        for (final c in children) ...[const SizedBox(height: 10), c],
      ],
    ),
  );
}
