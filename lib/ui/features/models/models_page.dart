import 'package:flutter/material.dart';

import '../../../core/llm/api_profile.dart';
import '../../../core/llm/llm_client.dart';
import '../../../data/config_store.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../local/local_store.dart';
import 'translate_card.dart';
import 'usage_card.dart';

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
              Text('接口 · 用途 · 翻译', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
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
                        Label('API 接口 · OpenAI / Anthropic / Google', trailing: Align(
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        UsageCard(config: config, local: local),
                        const SizedBox(height: 12),
                        TranslateCard(config: config),
                      ],
                    ),
                  ),
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
  late ApiProtocol _protocol = widget.profile.protocol;

  ApiProfile get _draft =>
      widget.profile.copyWith(name: _name.text.trim(), baseUrl: _url.text.trim(), apiKey: _key.text.trim(), protocol: _protocol);
  bool get _dirty =>
      _draft.name != widget.profile.name ||
      _draft.baseUrl != widget.profile.baseUrl ||
      _draft.apiKey != widget.profile.apiKey ||
      _draft.protocol != widget.profile.protocol;

  /// 换格式:地址还是空的或别家的默认地址时,换成这家的默认地址。
  void _setProtocol(ApiProtocol next) => setState(() {
    final url = _url.text.trim();
    if (url.isEmpty || ApiProtocol.values.any((x) => x.defaultUrl == url)) _url.text = next.defaultUrl;
    _protocol = next;
  });

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
          Text('格式', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
          const SizedBox(height: 4),
          Seg<ApiProtocol>(
            value: _protocol,
            onChanged: _setProtocol,
            items: [for (final x in ApiProtocol.values) (x, x.label, null)],
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
                  final list = await LlmClient(_draft).listModels();
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
                        final t = await LlmClient(_draft).ping(p.models.first);
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
