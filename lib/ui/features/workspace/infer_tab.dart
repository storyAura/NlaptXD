import 'package:flutter/material.dart';

import '../../../core/json_caption.dart';
import '../../../core/llm/api_profile.dart';
import '../../../core/local/florence.dart';
import '../../../data/config_store.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../cha/cha_dialog.dart';
import '../local/local_store.dart';
import 'diff_card.dart';
import 'engines.dart';
import 'side_panel.dart';
import 'workspace.dart';

enum Engine { llm, local, cha, json, compare }

/// 推标:先选引擎,再选范围。单张结果先预览(红绿对比),批量直接写盘并可整批回滚。
class InferTab extends StatefulWidget {
  const InferTab({super.key, required this.ws, required this.config, required this.local, required this.onGoModels});

  final Workspace ws;
  final ConfigStore config;
  final LocalStore local;
  final VoidCallback onGoModels;

  @override
  State<InferTab> createState() => _InferTabState();
}

class _InferTabState extends State<InferTab> {
  Workspace get ws => widget.ws;
  LocalStore get local => widget.local;
  Engine _engine = Engine.llm;
  Scope _scope = Scope.current;
  bool _confirm = false;
  JsonFormat _jsonFormat = JsonFormat.moss;

  static const _missingLocal = '先在「模型」页下载并选一个本地模型';

  void _say(String message, {bool warn = false}) {
    if (mounted) showToast(context, message, warn: warn);
  }

  Future<void> _run() async {
    final cfg = widget.config.config;
    if (_engine == Engine.cha) return _runCha();
    final local = _engine == Engine.local;
    final json = _engine == Engine.json;
    final ask = json ? askerFor(cfg.vision, cfg, widget.local) : null;
    final run = local
        ? widget.local.captioner(prompt: cfg.captionPrompt, system: cfg.system)
        : json
        ? (ask == null ? null : jsonCaptioner(_jsonFormat, ask))
        : llmCaptioner(cfg, widget.local);
    final missing = local ? _missingLocal : '还没有视觉模型 · 去「模型」页添加';
    if (_scope == Scope.current) {
      final err = await ws.inferCurrent(run, local ? widget.local.picked?.name ?? '本地' : modelLabel(cfg.vision, widget.local), missing: missing);
      if (err != null) _say(err, warn: true);
      return;
    }
    final over = ws.scopeEntries(_scope).where((e) => ws.textOf(e).trim().isNotEmpty).length;
    if (over > 0 && !_confirm) return setState(() => _confirm = true);
    setState(() => _confirm = false);
    // ponytail: 本地模型一次只推一张(Florence 只有一个会话,llama-server 没开多槽);要提速给 llama-server 加 --parallel。
    final title = local ? '本地推标' : json ? 'JSON标注 · ${_jsonFormat.label}' : 'LLM 推标';
    final one = local || cfg.vision?.profileId == localProfileId;
    final err = await ws.startBatch(_scope, run, title: title, missing: missing, parallel: one ? 1 : cfg.parallel);
    _report(err);
  }

  void _report(String? err) {
    final j = ws.lastJob;
    if (err != null) return _say(err, warn: true);
    if (j != null) _say(j.summary, warn: j.failed > 0);
  }

  Future<void> _runCha() async {
    final cfg = widget.config.config;
    final list = ws.scopeEntries(_scope);
    final plan = await showChaDialog(context, config: cfg, local: widget.local, images: list, root: ws.root, data: ws.dataDir);
    if (plan == null || !mounted) return;
    final scene = plan.scene;
    // 确认页换了整批画面模型就记进设置,下次默认用它。
    if (scene != (cfg.chaScene ?? cfg.vision)) await widget.config.update(cfg.copyWith(chaScene: (scene,)));
    final ask = askerFor(scene, cfg, widget.local);
    if (ask == null) return _say('整批画面模型不可用 · 去「模型」页设置', warn: true);
    final counts = <int, int>{};
    final err = await ws.startBatch(_scope, chaCaptioner(plan.roster, ask, counts),
        title: 'CHA标注', list: list, parallel: scene?.profileId == localProfileId ? 1 : cfg.parallel);
    if (err != null) return _say(err, warn: true);
    final j = ws.lastJob;
    if (j != null && mounted) {
      await showChaSummary(context, roster: plan.roster, counts: counts, job: j, model: modelLabel(scene, widget.local));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config.config;
    final n = ws.scopeEntries(_scope).length;
    final over = ws.scopeEntries(_scope).where((e) => ws.textOf(e).trim().isNotEmpty).length;
    final pending = ws.pending;
    final runLabel = switch (_engine) {
      _ when ws.busy => '推理中…',
      Engine.cha => 'CHA标注 · $n 张',
      Engine.json => _scope == Scope.current ? 'JSON标注当前图片' : 'JSON标注 $n 张',
      _ => _scope == Scope.current ? '推标当前图片' : '推标 $n 张',
    };
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const Label('引擎'),
        Seg<Engine>(
          expand: true,
          value: _engine,
          onChanged: (e) {
            setState(() {
              _engine = e;
              _confirm = false;
            });
            // 推出来的是 JSON,编辑区跟着切到 JSON 视图(预览图上画框)。
            if (e == Engine.json) ws.setView(mode: EditMode.json);
          },
          items: const [(Engine.llm, 'LLM', null), (Engine.local, '本地', null), (Engine.cha, 'CHA', null), (Engine.json, 'JSON', null), (Engine.compare, '多对比', null)],
        ),
        const SizedBox(height: 12),
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.expand,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.base),
            child: KeyedSubtree(
              key: ValueKey(_engine),
              child: switch (_engine) {
                Engine.llm => _llmPanel(cfg.vision),
                Engine.local => _LocalPanel(local: widget.local, prompt: cfg.captionRules, onGoModels: widget.onGoModels),
                Engine.cha => _chaPanel(),
                Engine.json => _jsonPanel(),
                Engine.compare => NlCard(
                  child: Row(children: [
                    Icon(Icons.schedule, size: 15, color: NlColors.slate500),
                    const SizedBox(width: 8),
                    Text('下一阶段接入', style: TextStyle(fontSize: 12.5, color: NlColors.slate500)),
                  ]),
                ),
              },
            ),
          ),
        ),
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
                        Row(children: [
                          NlButton(label: '开始推标', tone: Tone.primary, onPressed: _run),
                          const SizedBox(width: 6),
                          NlButton(label: '取消', tone: Tone.outline, onPressed: () => setState(() => _confirm = false)),
                        ]),
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
                      icon: switch (_engine) {
                        Engine.cha => Icons.groups_outlined,
                        Engine.json => Icons.data_object,
                        _ => Icons.play_arrow_rounded,
                      },
                      label: runLabel,
                      onPressed: _engine == Engine.compare || ws.job != null || n == 0 ? null : _run,
                    ),
                    if (_scope != Scope.current || _engine == Engine.cha)
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
          // 翻译结果在编辑器底部预览,这里只放推理结果。
          child: pending == null || pending.key != ws.entry?.key || pending.translated
              ? const SizedBox.shrink()
              : DiffCard(key: ValueKey(pending), ws: ws, result: pending),
        ),
      ],
    );
  }

  Widget _visionRow(ModelRef? vision) {
    final ready = askerFor(vision, widget.config.config, widget.local) != null;
    return Row(
      children: [
        Expanded(child: _ModelPill(label: modelLabel(vision, widget.local), onTap: _pickVision)),
        const SizedBox(width: 8),
        ready ? const Pill('就绪', tone: PillTone.ok) : const Pill('未配置', tone: PillTone.warn),
      ],
    );
  }

  /// 「JSON」引擎:当前视觉模型看图,回成所选格式的结构化 JSON。
  Widget _jsonPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _visionRow(widget.config.config.vision),
      const SizedBox(height: 10),
      const Label('格式'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final f in JsonFormat.values)
          NlChip(label: f.label, selected: _jsonFormat == f, onTap: () => setState(() => _jsonFormat = f)),
      ]),
      const SizedBox(height: 6),
      Text('布局 JSON · 区域框 + 英文描述', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
    ],
  );

  Widget _llmPanel(ModelRef? vision) {
    final cfg = widget.config.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _visionRow(vision),
        const SizedBox(height: 10),
        Label('提示词', trailing: Text('「模型」页可改', style: TextStyle(fontSize: 11, color: NlColors.slate400))),
        Text(cfg.captionRules, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: NlColors.slate700, height: 1.5)),
      ],
    );
  }

  Widget _chaPanel() {
    final cfg = widget.config.config;
    String label(ModelRef? r) => modelLabel(r ?? cfg.vision, widget.local);
    final style = TextStyle(fontSize: 11.5, color: NlColors.slate500);
    return NlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('人物卡 + 画面段 · 按图核对服装', style: TextStyle(fontSize: 12.5)),
          const SizedBox(height: 6),
          Text('候选:${cfg.chaCards.map(label).join(' / ')}', style: style, maxLines: 2, overflow: TextOverflow.ellipsis),
          Text('整批画面:${label(cfg.chaScene)}', style: style, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Future<void> _pickVision() async {
    final cfg = widget.config.config;
    if (cfg.pool.isEmpty) return widget.onGoModels();
    final names = {for (final p in cfg.profiles) p.id: p.name};
    final picked = await showModalBottomSheet<ModelRef>(
      context: context,
      backgroundColor: NlColors.card,
      builder: (_) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(12),
        children: [
          for (final r in cfg.pool)
            ListTile(
              dense: true,
              title: Text(r.model, style: const TextStyle(fontSize: 13)),
              subtitle: Text(names[r.profileId] ?? '', style: TextStyle(fontSize: 11, color: NlColors.slate500)),
              trailing: r == cfg.vision ? Icon(Icons.check, size: 16, color: NlColors.primary) : null,
              onTap: () => Navigator.pop(context, r),
            ),
        ],
      ),
    );
    if (picked != null) await widget.config.update(cfg.copyWith(vision: picked));
  }
}

class _ModelPill extends StatelessWidget {
  const _ModelPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Hover(
    cursor: SystemMouseCursors.click,
    builder: (hover) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.base,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: NlColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: hover ? NlColors.primaryBorder : NlColors.border),
        ),
        child: Row(children: [
          Icon(Icons.auto_awesome_outlined, size: 16, color: NlColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
          Icon(Icons.expand_more, size: 16, color: NlColors.slate500),
        ]),
      ),
    ),
  );
}

/// 「本地」引擎:选中的本地模型和它的状态;Florence-2 在这里选指令。
class _LocalPanel extends StatelessWidget {
  const _LocalPanel({required this.local, required this.prompt, required this.onGoModels});

  final LocalStore local;
  final String prompt;
  final VoidCallback onGoModels;

  @override
  Widget build(BuildContext context) {
    final m = local.picked;
    if (m == null) {
      return NlCard(
        child: Row(children: [
          Expanded(child: Text('还没选本地模型', style: TextStyle(fontSize: 12.5, color: NlColors.slate500))),
          NlButton(label: '去选模型', icon: Icons.memory_outlined, tone: Tone.outline, onPressed: onGoModels),
        ]),
      );
    }
    final ready = local.installed(m);
    final running = local.server.running && local.server.spec?.model.contains(m.id) == true;
    final (status, tone) = !ready
        ? ('未下载', PillTone.warn)
        : m.florence
        ? ('就绪', PillTone.ok)
        : local.starting
        ? ('启动中', PillTone.blue)
        : running
        ? ('运行中', PillTone.ok)
        : ('按需启动', PillTone.mute);
    return NlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.memory_outlined, size: 16, color: NlColors.slate700),
            const SizedBox(width: 8),
            Expanded(child: Text(m.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
            Pill(local.quantOf(m).label),
            const SizedBox(width: 6),
            Pill(status, tone: tone),
          ]),
          const SizedBox(height: 8),
          if (m.florence) ...[
            Text('指令模式', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in m.tasks)
                NlChip(
                  label: florenceTaskLabels[t] ?? t,
                  selected: local.florenceTaskOf(m) == t,
                  onTap: () => local.update(() => local.florenceTask = t),
                ),
            ]),
          ] else
            Text(
              ready ? 'llama-server 推理时自动启动 · 空闲 30 秒卸载' : '先到「模型」页下载',
              style: TextStyle(fontSize: 11.5, color: NlColors.slate500),
            ),
          if (!m.florence && ready) ...[
            const SizedBox(height: 6),
            Text(prompt, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: NlColors.slate700)),
          ],
        ],
      ),
    );
  }
}
