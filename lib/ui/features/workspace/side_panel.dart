import 'package:flutter/material.dart';

import '../../../core/captions.dart';
import '../../../core/llm/api_profile.dart';
import '../../../data/config_store.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'batch_edit_tab.dart';
import 'history_tab.dart';
import 'workspace.dart';

enum _Tab { infer, edit, history }

enum _Engine { llm, local, cha, compare }

const scopeLabels = {
  Scope.current: '当前',
  Scope.folder: '文件夹',
  Scope.selected: '已选',
  Scope.unlabeled: '未标注',
  Scope.all: '全部',
};

/// 一排范围药丸。[only] 之外的禁用。
Widget scopeChips(Workspace ws, List<Scope> scopes, Scope value, ValueChanged<Scope> onChanged) => Wrap(
  spacing: 6,
  runSpacing: 6,
  children: [
    for (final s in scopes)
      NlChip(
        label: scopeLabels[s]!,
        count: s == Scope.current ? null : ws.scopeEntries(s).length,
        selected: s == value,
        onTap: (s == Scope.selected && ws.selected.isEmpty) || ws.scopeEntries(s).isEmpty ? null : () => onChanged(s),
      ),
  ],
);

/// 右栏:推标 / 批量修改 / 历史。
class SidePanel extends StatefulWidget {
  const SidePanel({super.key, required this.ws, required this.config, required this.onGoModels, required this.onGoLog});

  final Workspace ws;
  final ConfigStore config;
  final VoidCallback onGoModels;
  final VoidCallback onGoLog;

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  _Tab _tab = _Tab.infer;

  @override
  Widget build(BuildContext context) => Container(
    color: NlColors.bg,
    child: Column(
      children: [
        NlBar(
          padding: 12,
          children: [
            Expanded(
              child: Seg<_Tab>(
                expand: true,
                value: _tab,
                onChanged: (t) => setState(() => _tab = t),
                items: const [(_Tab.infer, '推标', null), (_Tab.edit, '批量修改', null), (_Tab.history, '历史', null)],
              ),
            ),
          ],
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.base),
            switchInCurve: Motion.enter,
            layoutBuilder: fillLayout,
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: const Offset(0, .02), end: Offset.zero).animate(a), child: c),
            ),
            child: KeyedSubtree(
              key: ValueKey(_tab),
              child: switch (_tab) {
                _Tab.infer => _InferTab(ws: widget.ws, config: widget.config, onGoModels: widget.onGoModels),
                _Tab.edit => BatchEditTab(ws: widget.ws, onGoLog: widget.onGoLog),
                _Tab.history => HistoryTab(ws: widget.ws, onGoLog: widget.onGoLog),
              },
            ),
          ),
        ),
      ],
    ),
  );
}

class _InferTab extends StatefulWidget {
  const _InferTab({required this.ws, required this.config, required this.onGoModels});

  final Workspace ws;
  final ConfigStore config;
  final VoidCallback onGoModels;

  @override
  State<_InferTab> createState() => _InferTabState();
}

class _InferTabState extends State<_InferTab> {
  Workspace get ws => widget.ws;
  _Engine _engine = _Engine.llm;
  Scope _scope = Scope.current;
  bool _confirm = false;

  String get _modelName => widget.config.config.vision?.model ?? '未设置视觉模型';

  Future<void> _run() async {
    if (_scope == Scope.current) {
      final err = await ws.inferCurrent(_modelName);
      if (err != null && mounted) showToast(context, err, warn: true);
      return;
    }
    final over = ws.scopeEntries(_scope).where((e) => ws.textOf(e).trim().isNotEmpty).length;
    if (over > 0 && !_confirm) return setState(() => _confirm = true);
    setState(() => _confirm = false);
    final err = await ws.startBatch(_scope);
    if (!mounted) return;
    final j = ws.lastJob;
    if (err != null) return showToast(context, err, warn: true);
    if (j != null) {
      showToast(
        context,
        j.cancelled ? '已取消 · 完成 ${j.changes.length} 张' : '推标完成:成功 ${j.changes.length} / 失败 ${j.failed}',
        warn: j.failed > 0,
      );
    }
  }

  Future<void> _pickModel(BuildContext context) async {
    final cfg = widget.config.config;
    final box = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final at = box.localToGlobal(Offset(0, box.size.height + 6), ancestor: overlay);
    final pool = cfg.pool;
    final picked = await showMenu<ModelRef?>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + box.size.width, at.dy),
      items: [
        if (pool.isEmpty)
          const PopupMenuItem(value: null, height: 34, child: Text('去「模型」页添加接口', style: TextStyle(fontSize: 13))),
        for (final p in cfg.profiles.where((p) => p.enabled && p.models.isNotEmpty)) ...[
          PopupMenuItem(enabled: false, height: 26, child: Text(p.name, style: TextStyle(fontSize: 11, color: NlColors.slate400))),
          for (final m in p.models)
            PopupMenuItem(
              value: ModelRef(p.id, m),
              height: 34,
              child: Row(
                children: [
                  Expanded(child: Text(m, style: const TextStyle(fontSize: 13))),
                  if (cfg.vision == ModelRef(p.id, m)) Icon(Icons.check, size: 15, color: NlColors.primary),
                ],
              ),
            ),
        ],
      ],
    );
    if (picked != null) {
      await widget.config.update(cfg.copyWith(vision: picked));
    } else if (pool.isEmpty) {
      widget.onGoModels();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config.config;
    final ready = cfg.profileOf(cfg.vision) != null;
    final n = ws.scopeEntries(_scope).length;
    final over = ws.scopeEntries(_scope).where((e) => ws.textOf(e).trim().isNotEmpty).length;
    final pending = ws.pending;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            Expanded(
              child: Builder(
                builder: (context) => Hover(
                  cursor: SystemMouseCursors.click,
                  builder: (hover) => GestureDetector(
                    onTap: () => _pickModel(context),
                    child: AnimatedContainer(
                      duration: Motion.base,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: NlColors.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: hover ? NlColors.primaryBorder : NlColors.border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome_outlined, size: 16, color: NlColors.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_modelName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                          Icon(Icons.expand_more, size: 16, color: NlColors.slate500),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ready ? const Pill('就绪', tone: PillTone.ok) : const Pill('未配置', tone: PillTone.warn),
          ],
        ),
        const SizedBox(height: 14),
        const Label('引擎'),
        Seg<_Engine>(
          expand: true,
          value: _engine,
          onChanged: (e) => setState(() => _engine = e),
          items: const [(_Engine.llm, 'LLM', null), (_Engine.local, '本地', null), (_Engine.cha, 'CHA', null), (_Engine.compare, '多对比', null)],
        ),
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.expand,
          child: _engine == _Engine.llm
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: NlCard(
                    child: Row(
                      children: [
                        Icon(Icons.schedule, size: 15, color: NlColors.slate500),
                        const SizedBox(width: 8),
                        Text('下一阶段接入', style: TextStyle(fontSize: 12.5, color: NlColors.slate500)),
                      ],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 14),
        Label('提示词', trailing: Text('「模型」页可改', style: TextStyle(fontSize: 11, color: NlColors.slate400))),
        Text(cfg.prompt, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: NlColors.slate700, height: 1.5)),
        const SizedBox(height: 14),
        const Label('范围'),
        scopeChips(ws, Scope.values, _scope, (s) => setState(() {
          _scope = s;
          _confirm = false;
        })),
        const SizedBox(height: 14),
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.expand,
          child: _confirm
              ? PopIn(
                  child: NlCard(
                    color: NlColors.lock,
                    borderColor: NlColors.lockBorder,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('将覆盖 $over 张现有标注,执行前自动备份。', style: TextStyle(fontSize: 12.5, color: NlColors.lockText)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            NlButton(label: '开始推标', tone: Tone.primary, onPressed: _run),
                            const SizedBox(width: 6),
                            NlButton(label: '取消', tone: Tone.outline, onPressed: () => setState(() => _confirm = false)),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    NlButton(
                      expand: true,
                      tone: Tone.primary,
                      busy: ws.busy,
                      icon: Icons.play_arrow_rounded,
                      label: ws.busy ? '推理中…' : _scope == Scope.current ? '推标当前图片' : '推标 $n 张',
                      onPressed: _engine != _Engine.llm || ws.job != null ? null : _run,
                    ),
                    if (_scope != Scope.current)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('自动备份 · 可整批回滚', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: Motion.of(context, Motion.sheet),
          switchInCurve: Motion.enter,
          transitionBuilder: (c, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(position: Tween(begin: const Offset(0, .06), end: Offset.zero).animate(a), child: c),
          ),
          child: pending == null || pending.key != ws.entry?.key
              ? const SizedBox.shrink()
              : _DiffCard(key: ValueKey(pending), ws: ws, result: pending),
        ),
      ],
    );
  }
}

class _DiffCard extends StatelessWidget {
  const _DiffCard({super.key, required this.ws, required this.result});

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
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined, size: 15, color: NlColors.primary),
              const SizedBox(width: 6),
              const Text('推理结果', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              const Spacer(),
              Flexible(child: Pill(result.model)),
            ],
          ),
          const SizedBox(height: 10),
          for (final (i, s) in del.indexed) PopIn(delay: Duration(milliseconds: 30 * i), child: line(s, false)),
          for (final (i, s) in add.indexed) PopIn(delay: Duration(milliseconds: 30 * (del.length + i)), child: line(s, true)),
          if (del.isEmpty && add.isEmpty) Text('和现在的标注一样', style: TextStyle(fontSize: 12, color: NlColors.slate500)),
          const SizedBox(height: 6),
          Text('保留 ${old.length - del.length} 段 · 删 ${del.length} · 增 ${add.length}', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
          const SizedBox(height: 10),
          Row(
            children: [
              NlButton(label: '采纳', icon: Icons.check, tone: Tone.primary, onPressed: ws.acceptPending),
              const SizedBox(width: 6),
              NlButton(label: '驳回', tone: Tone.outline, onPressed: ws.rejectPending),
            ],
          ),
        ],
      ),
    );
  }
}
