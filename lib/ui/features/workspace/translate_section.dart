import 'package:flutter/material.dart';

import '../../../core/captions.dart';
import '../../../core/llm/translate.dart';
import '../../../data/config_store.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'engines.dart';
import 'gloss_pane.dart';
import 'workspace.dart';

/// 批量修改里的「翻译对照」(默认收起):当前这张的原文 / 译文并排,⇄ 把这一段换成译文;
/// 「中文全部转为英文」把范围内含中文的文件译好写回。同旧版 widgets/sections/translate.py。
class TranslateSection extends StatefulWidget {
  const TranslateSection({super.key, required this.ws, required this.config, required this.scope, required this.onWritten});

  final Workspace ws;
  final ConfigStore config;
  final Scope scope;

  /// 写盘后:改了几个、失败几个(给上层弹提示、整批撤销)。
  final void Function(int written, int failed) onWritten;

  @override
  State<TranslateSection> createState() => _TranslateSectionState();
}

class _TranslateSectionState extends State<TranslateSection> {
  Workspace get ws => widget.ws;
  bool _open = false;
  bool _perSegment = true;
  bool _running = false;

  Translator get _translator => translatorFor(widget.config.config);

  Future<void> _toEnglish() async {
    setState(() => _running = true);
    try {
      final r = await ws.translateChineseToEnglish(
        widget.scope,
        perSegment: _perSegment,
        toEnglish: (t) => _translator.translate(t, 'en'),
      );
      widget.onWritten(r.written, r.failed);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// ⇄:把第 [i] 段(整段时 i = -1)换成译文。
  void _swap(int i, String translated) {
    if (i < 0) {
      ws.setText(translated, label: '翻译替换');
    } else {
      ws.editSegments((s) => s[i] = translated, '翻译替换');
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = ws.entry;
    final text = e == null ? '' : ws.textOf(e);
    final rows = _perSegment ? splitSegments(text) : [if (text.trim().isNotEmpty) text];
    final withCjk = ws.scopeEntries(widget.scope).where((x) => hasCjk(ws.textOf(x))).length;
    return NlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Hover(
            cursor: SystemMouseCursors.click,
            builder: (_) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = !_open),
              child: Row(
                children: [
                  Icon(Icons.translate, size: 16, color: NlColors.slate700),
                  const SizedBox(width: 6),
                  const Expanded(child: Text('翻译对照', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                  AnimatedRotation(
                    turns: _open ? .5 : 0,
                    duration: Motion.base,
                    curve: Motion.swift,
                    child: Icon(Icons.expand_more, size: 18, color: NlColors.slate500),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: Motion.of(context, Motion.base),
            curve: Motion.expand,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 10),
                      Seg<bool>(
                        value: _perSegment,
                        onChanged: _running ? (_) {} : (v) => setState(() => _perSegment = v),
                        items: const [(true, '分段', null), (false, '整段', null)],
                      ),
                      const SizedBox(height: 8),
                      if (rows.isEmpty) Text('这张还没有标注', style: TextStyle(fontSize: 12, color: NlColors.slate500)),
                      for (final (i, src) in rows.indexed)
                        _PairRow(
                          key: ValueKey('${e?.key}/$_perSegment/$i'),
                          source: src,
                          translator: _translator,
                          onSwap: (t) => _swap(_perSegment ? i : -1, t),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              withCjk == 0 ? '范围内没有中文' : '范围内 $withCjk 个文件含中文',
                              style: TextStyle(fontSize: 11.5, color: NlColors.slate500),
                            ),
                          ),
                          NlButton(
                            label: _running ? '翻译中…' : '中文全部转为英文',
                            tone: Tone.primary,
                            busy: _running,
                            onPressed: withCjk == 0 || _running ? null : _toEnglish,
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// 一行对照:原文、译文(停手 400ms 才请求)、⇄。中文译成英文,其余译成中文。
class _PairRow extends StatefulWidget {
  const _PairRow({super.key, required this.source, required this.translator, required this.onSwap});

  final String source;
  final Translator translator;
  final ValueChanged<String> onSwap;

  @override
  State<_PairRow> createState() => _PairRowState();
}

class _PairRowState extends State<_PairRow> with DebouncedTranslation {
  @override
  String get source => widget.source;
  @override
  String get targetLang => autoTarget(widget.source);
  @override
  Translator get translator => widget.translator;

  @override
  Widget build(BuildContext context) {
    final ready = !waiting && translated != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(9, 6, 4, 6),
      decoration: BoxDecoration(color: NlColors.slate50, borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.source, style: monoStyle.copyWith(height: 1.35)),
                const SizedBox(height: 2),
                Text(
                  error ?? (ready ? translated! : '翻译中…'),
                  style: TextStyle(fontSize: 12, height: 1.35, color: error != null ? NlColors.amber : NlColors.slate500),
                ),
              ],
            ),
          ),
          NlIconButton(Icons.swap_horiz, tooltip: '换成译文', onPressed: ready ? () => widget.onSwap(translated!) : null),
        ],
      ),
    );
  }
}
