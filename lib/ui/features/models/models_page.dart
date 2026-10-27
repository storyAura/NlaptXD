import 'package:flutter/material.dart';

import '../../../core/llm/api_profile.dart';
import '../../../core/llm/openai_client.dart';
import '../../../data/config_store.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../local/local_store.dart';
import '../workspace/engines.dart';

/// 模型:左边接口卡片,右边「用途」(推标、CHA 各用哪个模型,提示词)。
class ModelsPage extends StatelessWidget {
  const ModelsPage({super.key, required this.config, required this.local});

  final ConfigStore config;
  final LocalStore local;

  void _add() {
    final cfg = config.config;
    final id = 'p${DateTime.now().microsecondsSinceEpoch}';
    config.update(cfg.copyWith(profiles: [
      ...cfg.profiles,
      ApiProfile(id: id, name: '接口 ${cfg.profiles.length + 1}', baseUrl: 'https://openrouter.ai/api/v1', apiKey: ''),
    ]));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([config, local]),
    builder: (context, _) {
      final cfg = config.config;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NlBar(
            children: [
              const Text('模型', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              Text('接口 · 用途', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Label('API 接口 · OpenAI 兼容', trailing: Align(
                          alignment: Alignment.centerRight,
                          child: NlButton(label: '添加接口', icon: Icons.add, tone: Tone.outline, onPressed: _add),
                        )),
                        if (cfg.profiles.isEmpty)
                          NlCard(child: Text('还没有接口。OpenRouter、DeepSeek、硅基流动、本机 llama-server 都可以。', style: TextStyle(color: NlColors.slate500))),
                        for (final (i, p) in cfg.profiles.indexed)
                          PopIn(
                            key: ValueKey(p.id),
                            delay: Duration(milliseconds: 40 * i),
                            child: Padding(padding: const EdgeInsets.only(bottom: 12), child: _ProfileCard(config: config, profile: p)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(child: _Usage(config: config, local: local)),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// 一张接口卡片。名称、地址、Key 先改草稿,点「保存」才写进设置(同 Penna)。
class _ProfileCard extends StatefulWidget {
  const _ProfileCard({required this.config, required this.profile});

  final ConfigStore config;
  final ApiProfile profile;

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  late final _name = TextEditingController(text: widget.profile.name);
  late final _url = TextEditingController(text: widget.profile.baseUrl);
  late final _key = TextEditingController(text: widget.profile.apiKey);
  final _model = TextEditingController();
  List<String> _fetched = const [];
  bool _showKey = false, _busy = false;

  ApiProfile get _draft => widget.profile.copyWith(name: _name.text.trim(), baseUrl: _url.text.trim(), apiKey: _key.text.trim());
  bool get _dirty => _draft.name != widget.profile.name || _draft.baseUrl != widget.profile.baseUrl || _draft.apiKey != widget.profile.apiKey;

  @override
  void dispose() {
    for (final c in [_name, _url, _key, _model]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _replace(ApiProfile? next) {
    final cfg = widget.config.config;
    final list = [
      for (final p in cfg.profiles)
        if (p.id != widget.profile.id) p else ?next,
    ];
    final next0 = cfg.copyWith(profiles: list);
    return widget.config.update(next0.profileOf(next0.vision) == null ? next0.copyWith(clearVision: true) : next0);
  }

  void _toggleModel(String m) {
    final models = [...widget.profile.models];
    models.contains(m) ? models.remove(m) : models.add(m);
    _replace(widget.profile.copyWith(models: models));
  }

  void _say(String message, {bool warn = false}) {
    if (mounted) showToast(context, message, warn: warn);
  }

  Future<void> _guard(Future<void> Function() run) async {
    setState(() => _busy = true);
    try {
      await run();
    } on LlmError catch (e) {
      _say(e.message, warn: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    Widget field(String label, TextEditingController c, {bool secret = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
        const SizedBox(height: 4),
        TextField(
          controller: c,
          obscureText: secret && !_showKey,
          style: const TextStyle(fontSize: 12.5),
          onChanged: (_) => setState(() {}),
          decoration: fieldDecoration('').copyWith(
            suffixIcon: secret ? NlIconButton(_showKey ? Icons.visibility_off_outlined : Icons.visibility_outlined, onPressed: () => setState(() => _showKey = !_showKey)) : null,
          ),
        ),
      ],
    );
    final known = {...p.models, ..._fetched}.toList()..sort();
    return NlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600))),
              Switch(value: p.enabled, onChanged: (v) => _replace(p.copyWith(enabled: v))),
              NlIconButton(Icons.delete_outline, tooltip: '删除接口', onPressed: () => _replace(null)),
            ],
          ),
          const SizedBox(height: 8),
          field('名称', _name),
          const SizedBox(height: 8),
          field('地址', _url),
          const SizedBox(height: 8),
          field('API Key', _key, secret: true),
          const SizedBox(height: 10),
          Text('模型 · 勾选的进入模型池', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
          const SizedBox(height: 6),
          AnimatedSize(
            duration: Motion.base,
            curve: Motion.expand,
            alignment: Alignment.topCenter,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in known) NlChip(label: m, selected: p.models.contains(m), onTap: () => _toggleModel(m)),
                SizedBox(
                  width: 180,
                  height: 32,
                  child: TextField(
                    controller: _model,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: fieldDecoration('手动添加模型 ID').copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                    onSubmitted: (m) {
                      if (m.trim().isEmpty) return;
                      _model.clear();
                      if (!p.models.contains(m.trim())) _toggleModel(m.trim());
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              NlButton(
                label: '拉取模型',
                icon: Icons.download_outlined,
                tone: Tone.outline,
                busy: _busy,
                onPressed: () => _guard(() async {
                  final list = await OpenAiClient(_draft).listModels();
                  if (!mounted) return;
                  setState(() => _fetched = list);
                  _say('拉到 ${list.length} 个模型 · 勾选后可用');
                }),
              ),
              const SizedBox(width: 6),
              NlButton(
                label: '测试连接',
                icon: Icons.bolt_outlined,
                tone: Tone.outline,
                busy: _busy,
                onPressed: p.models.isEmpty
                    ? null
                    : () => _guard(() async {
                        final t = await OpenAiClient(_draft).ping(p.models.first);
                        _say('连接成功(${(t.inMilliseconds / 1000).toStringAsFixed(1)} 秒)');
                      }),
              ),
              const Spacer(),
              AnimatedOpacity(
                duration: Motion.base,
                opacity: _dirty ? 1 : 0,
                child: NlButton(
                  label: '保存',
                  tone: Tone.primary,
                  onPressed: _dirty
                      ? () async {
                          await _replace(_draft);
                          _say('已保存');
                        }
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Usage extends StatefulWidget {
  const _Usage({required this.config, required this.local});

  final ConfigStore config;
  final LocalStore local;

  @override
  State<_Usage> createState() => _UsageState();
}

class _UsageState extends State<_Usage> {
  late final _prompt = TextEditingController(text: widget.config.config.prompt);
  late final _system = TextEditingController(text: widget.config.config.system);

  @override
  void dispose() {
    _prompt.dispose();
    _system.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config.config;
    final names = {for (final p in cfg.profiles) p.id: p.name};
    final dirty = _prompt.text != cfg.prompt || _system.text != cfg.system;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Label('用途'),
        NlCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('视觉 · 推标', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
              const SizedBox(height: 6),
              DropdownButtonFormField<ModelRef>(
                // 换了 key 才会按新值重建(FormField 只在创建时读 initialValue)。
                key: ValueKey('vision/${cfg.vision?.profileId}/${cfg.vision?.model}'),
                initialValue: cfg.pool.contains(cfg.vision) ? cfg.vision : null,
                isExpanded: true,
                hint: Text(cfg.pool.isEmpty ? '先在左边添加接口并勾选模型' : '选择模型', style: const TextStyle(fontSize: 12.5)),
                decoration: fieldDecoration(''),
                style: uiFont.copyWith(fontSize: 12.5, color: NlColors.text),
                items: [
                  for (final r in cfg.pool)
                    DropdownMenuItem(value: r, child: Text('${names[r.profileId]} · ${r.model}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (r) => widget.config.update(cfg.copyWith(vision: r)),
              ),
              const SizedBox(height: 14),
              Text('推标提示词', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
              const SizedBox(height: 6),
              TextField(controller: _prompt, maxLines: 5, minLines: 3, style: monoStyle, onChanged: (_) => setState(() {}), decoration: fieldDecoration('')),
              const SizedBox(height: 10),
              Text('系统提示词 · 可留空', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
              const SizedBox(height: 6),
              TextField(controller: _system, maxLines: 4, minLines: 2, style: monoStyle, onChanged: (_) => setState(() {}), decoration: fieldDecoration('')),
              const SizedBox(height: 10),
              Row(
                children: [
                  NlButton(
                    label: '恢复默认',
                    tone: Tone.ghost,
                    onPressed: () => setState(() => _prompt.text = defaultVisionPrompt),
                  ),
                  const Spacer(),
                  NlButton(
                    label: '保存',
                    tone: Tone.primary,
                    onPressed: dirty
                        ? () async {
                            await widget.config.update(cfg.copyWith(prompt: _prompt.text, system: _system.text));
                            if (context.mounted) showToast(context, '已保存');
                            setState(() {});
                          }
                        : null,
                  ),
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
              Text('CHA标注 · 留空沿用视觉模型', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
              for (var i = 0; i < 3; i++)
                _slot('候选 ${i + 1}', cfg.chaCards[i], (r) {
                  final cards = [...cfg.chaCards]..[i] = r;
                  widget.config.update(cfg.copyWith(chaCards: cards));
                }),
              _slot('整批画面', cfg.chaScene, (r) => widget.config.update(cfg.copyWith(chaScene: (r,)))),
            ],
          ),
        ),
      ],
    );
  }

  /// 一个 CHA 模型位:沿用视觉模型 / 模型池里任一个 / 本地 GGUF 模型。
  Widget _slot(String label, ModelRef? value, ValueChanged<ModelRef?> onChanged) {
    final cfg = widget.config.config;
    final names = {for (final p in cfg.profiles) p.id: p.name};
    final local = widget.local.picked;
    final options = <ModelRef?>[
      null,
      ...cfg.pool,
      if (local != null && !local.florence && widget.local.installed(local)) const ModelRef(localProfileId, ''),
    ];
    final current = options.contains(value) ? value : null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(label, style: TextStyle(fontSize: 12, color: NlColors.slate500))),
          Expanded(
            child: DropdownButtonFormField<ModelRef?>(
              key: ValueKey('$label/${current?.profileId}/${current?.model}'),
              initialValue: current,
              isExpanded: true,
              decoration: fieldDecoration(''),
              style: uiFont.copyWith(fontSize: 12.5, color: NlColors.text),
              items: [
                for (final r in options)
                  DropdownMenuItem(
                    value: r,
                    child: Text(
                      r == null
                          ? '沿用视觉模型'
                          : r.profileId == localProfileId
                          ? modelLabel(r, widget.local)
                          : '${names[r.profileId]} · ${r.model}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
