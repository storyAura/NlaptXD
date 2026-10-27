import 'package:flutter/material.dart';

import '../../../core/llm/api_profile.dart';
import '../../../core/llm/openai_client.dart';
import '../../../core/llm/translate.dart';
import '../../../data/app_config.dart';
import '../../../data/config_store.dart';
import '../../core/select.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../workspace/engines.dart';

/// 「模型」页的翻译设置:当前文本模型、翻译服务和各家的密钥、备选顺序、测试翻译。
/// 供标注台的翻译 / 译文、批量的翻译对照、CHA 人物卡中文对照使用。
class TranslateCard extends StatefulWidget {
  const TranslateCard({super.key, required this.config});

  final ConfigStore config;

  @override
  State<TranslateCard> createState() => _TranslateCardState();
}

class _TranslateCardState extends State<TranslateCard> {
  AppConfig get cfg => widget.config.config;
  TranslateSettings get t => cfg.translate;

  /// 各个输入框的控制器,按字段名;切换服务时不丢已填的内容。
  final _fields = <String, TextEditingController>{};
  bool _testing = false;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(TranslateSettings next) => widget.config.update(cfg.copyWith(translate: next));

  Widget _field(String key, String hint, String value, TranslateSettings Function(String v) apply, {bool secret = false}) {
    final c = _fields[key] ??= TextEditingController(text: value);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: c,
        obscureText: secret,
        style: const TextStyle(fontSize: 12.5),
        decoration: fieldDecoration(hint, icon: secret ? Icons.key_outlined : null),
        onChanged: (v) => _set(apply(v.trim())),
      ),
    );
  }

  List<Widget> _credentials() => switch (t.service) {
    TranslateService.baidu => [
      _field('baiduAppid', '百度 APPID(fanyi-api.baidu.com)', t.baiduAppid, (v) => t.copyWith(baiduAppid: v)),
      _field('baiduKey', '百度密钥', t.baiduKey, (v) => t.copyWith(baiduKey: v), secret: true),
    ],
    TranslateService.deepl => [_field('deeplKey', 'DeepL API Key(deepl.com/pro-api)', t.deeplKey, (v) => t.copyWith(deeplKey: v), secret: true)],
    TranslateService.deeplx => [
      _field('deeplxUrl', 'DeepLX 实例地址(自建或 deeplx.owo.network 的免费实例)', t.deeplxUrl, (v) => t.copyWith(deeplxUrl: v)),
      _field('deeplxToken', '访问令牌 · 可留空', t.deeplxToken, (v) => t.copyWith(deeplxToken: v), secret: true),
    ],
    TranslateService.custom => [
      _field('customBaseUrl', 'Base URL(如 https://api.deepseek.com/v1)', t.customBaseUrl, (v) => t.copyWith(customBaseUrl: v)),
      _field('customKey', 'API Key', t.customKey, (v) => t.copyWith(customKey: v), secret: true),
      _field('customModel', '模型', t.customModel, (v) => t.copyWith(customModel: v)),
    ],
    _ => const [],
  };

  void _toggleFallback(TranslateService s) {
    final list = [...t.fallbacks];
    list.contains(s) ? list.remove(s) : list.add(s);
    _set(t.copyWith(fallbacks: list));
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      final out = await translatorFor(cfg).translateWith(t.service, '你好世界', 'en');
      if (mounted) showToast(context, '${t.service.label}:$out');
    } on LlmError catch (e) {
      if (mounted) showToast(context, e.message, warn: true);
    }
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final caption = TextStyle(fontSize: 11.5, color: NlColors.slate500);
    final names = {for (final p in cfg.profiles) p.id: p.name};
    final others = TranslateService.values.where((s) => s != t.service);
    return NlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('翻译 · 标注台译文、翻译对照、CHA 中文对照', style: caption),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: NlSelect<TranslateService>(
                  value: t.service,
                  items: [for (final s in TranslateService.values) (s, s.label)],
                  onChanged: (s) => _set(t.copyWith(service: s, fallbacks: t.fallbacks.where((f) => f != s).toList())),
                ),
              ),
              const SizedBox(width: 8),
              NlButton(label: _testing ? '测试中…' : '测试翻译', tone: Tone.outline, busy: _testing, onPressed: _testing ? null : _test),
            ],
          ),
          if (t.service == TranslateService.llm) ...[
            const SizedBox(height: 8),
            NlSelect<ModelRef?>(
              value: cfg.pool.contains(cfg.textModel) ? cfg.textModel : null,
              hint: cfg.pool.isEmpty ? '先在左边添加接口并勾选模型' : '选当前文本模型',
              items: [for (final r in cfg.pool) (r, '${names[r.profileId]} · ${r.model}')],
              onChanged: (r) => widget.config.update(cfg.copyWith(textModel: (r,))),
            ),
          ],
          ..._credentials(),
          const SizedBox(height: 12),
          Text(
            t.fallbacks.isEmpty ? '备选 · 首选失败时依次换用' : '备选 · ${t.fallbacks.map((s) => s.label).join(' → ')}',
            style: caption,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final s in others) NlChip(label: s.label, selected: t.fallbacks.contains(s), onTap: () => _toggleFallback(s))],
          ),
        ],
      ),
    );
  }
}
