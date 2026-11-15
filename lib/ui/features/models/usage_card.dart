import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/llm/api_profile.dart';
import '../../../core/llm/llm_client.dart';
import '../../../core/system_prompts.dart';
import '../../../data/app_config.dart';
import '../../../data/config_store.dart';
import '../../core/select.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../local/local_store.dart';
import '../workspace/engines.dart';

/// 「模型」页右边的「用途」:推标用哪个模型、提示词与系统提示词方案、CHA 各模型位。
class UsageCard extends StatefulWidget {
  const UsageCard({super.key, required this.config, required this.local});

  final ConfigStore config;
  final LocalStore local;

  @override
  State<UsageCard> createState() => _UsageCardState();
}

class _UsageCardState extends State<UsageCard> {
  final _system = TextEditingController();
  final _name = TextEditingController();
  late final _parallel = TextEditingController(text: '${widget.config.config.parallel}');

  /// 输入框正在显示哪套方案;设置里换了方案(或别处改了)就重新填。
  String? _shown;

  AppConfig get cfg => widget.config.config;
  bool get _custom => cfg.systemName.isNotEmpty && !builtinSystemPrompts.containsKey(cfg.systemName);

  @override
  void dispose() {
    _system.dispose();
    _name.dispose();
    _parallel.dispose();
    super.dispose();
  }

  /// 同时发送数:超出范围按边界算,框里的字跟着改。
  void _setParallel(int n) {
    final v = n.clamp(1, maxParallel);
    _showParallel(v);
    if (v != cfg.parallel) widget.config.update(cfg.copyWith(parallel: v));
  }

  void _showParallel(int v) {
    final text = '$v';
    if (_parallel.text != text) _parallel.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  void _sync() {
    if (_shown == cfg.systemName) return;
    _shown = cfg.systemName;
    _system.text = cfg.system;
    _name.text = cfg.systemName;
  }

  bool get _dirty => _system.text != cfg.system || (_custom && _name.text.trim() != cfg.systemName);

  void _select(String name) => widget.config.update(cfg.copyWith(systemName: name));

  void _create() {
    var n = cfg.systemPrompts.length + 1;
    while (cfg.systemNames.contains('方案 $n')) {
      n++;
    }
    widget.config.update(cfg.copyWith(systemPrompts: {...cfg.systemPrompts, '方案 $n': ''}, systemName: '方案 $n'));
  }

  void _delete() {
    final rest = {...cfg.systemPrompts}..remove(cfg.systemName);
    widget.config.update(cfg.copyWith(systemPrompts: rest, systemName: ''));
  }

  /// 内置方案改过的话,删掉用户那份就回到内置原文。
  void _restoreBuiltin() {
    final rest = {...cfg.systemPrompts}..remove(cfg.systemName);
    _shown = null;
    widget.config.update(cfg.copyWith(systemPrompts: rest));
  }

  Future<void> _save() async {
    final old = cfg.systemName;
    final name = _custom ? _name.text.trim() : old;
    if (name != old && (name.isEmpty || cfg.systemNames.contains(name))) {
      showToast(context, name.isEmpty ? '方案名不能为空' : '已有同名方案', warn: true);
      return;
    }
    // 改名时保持原来的顺序。
    final prompts = {for (final MapEntry(:key, :value) in cfg.systemPrompts.entries) (key == old ? name : key): value};
    if (old.isNotEmpty) {
      if (builtinSystemPrompts[old] == _system.text) {
        prompts.remove(old);
      } else {
        prompts[name] = _system.text;
      }
    }
    _shown = name;
    await widget.config.update(cfg.copyWith(systemPrompts: prompts, systemName: name));
    if (mounted) {
      showToast(context, '已保存');
      setState(() {});
    }
  }

  String _refLabel(ModelRef r, Map<String, String> names) =>
      r.profileId == localProfileId ? modelLabel(r, widget.local) : '${names[r.profileId]} · ${r.model}';

  @override
  Widget build(BuildContext context) {
    _sync();
    final names = {for (final p in cfg.profiles) p.id: p.name};
    final caption = TextStyle(fontSize: 11.5, color: NlColors.slate500);
    final builtinEdited = builtinSystemPrompts.containsKey(cfg.systemName) && cfg.systemPrompts.containsKey(cfg.systemName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Label('用途'),
        NlCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('视觉 · 推标', style: caption),
              const SizedBox(height: 6),
              NlSelect<ModelRef?>(
                value: cfg.pool.contains(cfg.vision) ? cfg.vision : null,
                hint: cfg.pool.isEmpty ? '先在左边添加接口并勾选模型' : '选择模型',
                items: [for (final r in cfg.pool) (r, _refLabel(r, names))],
                onChanged: (r) => widget.config.update(cfg.copyWith(vision: r)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text('批量同时发送 1–$maxParallel 张 · 接口限流就调小', style: caption)),
                  NlIconButton(Icons.remove, tooltip: '减一张', onPressed: cfg.parallel > 1 ? () => _setParallel(cfg.parallel - 1) : null),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 56,
                    // 清空后点别处:框里回到当前值。
                    child: Focus(
                      onFocusChange: (on) {
                        if (!on) _showParallel(cfg.parallel);
                      },
                      child: TextField(
                        controller: _parallel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12.5),
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                        onChanged: (s) {
                          final n = int.tryParse(s);
                          if (n != null) _setParallel(n);
                        },
                        decoration: fieldDecoration(''),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  NlIconButton(Icons.add, tooltip: '加一张', onPressed: cfg.parallel < maxParallel ? () => _setParallel(cfg.parallel + 1) : null),
                ],
              ),
              const SizedBox(height: 14),
              Text('系统提示词 · 推标照它写', style: caption),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  NlChip(label: '默认', selected: cfg.systemName.isEmpty, onTap: () => _select('')),
                  for (final n in cfg.systemNames) NlChip(label: n, selected: cfg.systemName == n, onTap: () => _select(n)),
                  NlButton(label: '新建', icon: Icons.add, tone: Tone.ghost, onPressed: _create),
                ],
              ),
              if (_custom) ...[
                const SizedBox(height: 8),
                TextField(controller: _name, style: const TextStyle(fontSize: 12.5), onChanged: (_) => setState(() {}), decoration: fieldDecoration('方案名')),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _system,
                enabled: cfg.systemName.isNotEmpty,
                maxLines: 8,
                minLines: 3,
                style: monoStyle,
                onChanged: (_) => setState(() {}),
                decoration: fieldDecoration(cfg.systemName.isEmpty ? defaultVisionPrompt : '').copyWith(hintMaxLines: 8),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (builtinEdited) NlButton(label: '恢复内置方案', tone: Tone.ghost, onPressed: _restoreBuiltin),
                  if (_custom) NlButton(label: '删除方案', tone: Tone.ghost, onPressed: _delete),
                  const Spacer(),
                  NlButton(label: '保存', tone: Tone.primary, onPressed: _dirty ? _save : null),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        NlCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('CHA标注 · 留空沿用视觉模型', style: caption),
              for (var i = 0; i < 3; i++)
                _slot('候选 ${i + 1}', cfg.chaCards[i], names, (r) {
                  final cards = [...cfg.chaCards]..[i] = r;
                  widget.config.update(cfg.copyWith(chaCards: cards));
                }),
              _slot('整批画面', cfg.chaScene, names, (r) => widget.config.update(cfg.copyWith(chaScene: (r,)))),
            ],
          ),
        ),
      ],
    );
  }

  /// 一个 CHA 模型位:沿用视觉模型 / 模型池里任一个 / 本地 GGUF 模型。
  Widget _slot(String label, ModelRef? value, Map<String, String> names, ValueChanged<ModelRef?> onChanged) {
    final local = widget.local.picked;
    final options = <ModelRef?>[
      null,
      ...cfg.pool,
      if (local != null && !local.florence && widget.local.installed(local)) const ModelRef(localProfileId, ''),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(label, style: TextStyle(fontSize: 12, color: NlColors.slate500))),
          Expanded(
            child: NlSelect<ModelRef?>(
              value: options.contains(value) ? value : null,
              items: [for (final r in options) (r, r == null ? '沿用视觉模型' : _refLabel(r, names))],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
