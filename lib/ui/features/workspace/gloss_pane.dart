import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/llm/openai_client.dart';
import '../../../core/llm/translate.dart';
import '../../core/theme.dart';

/// 停手 400ms 才翻译 [source];原文又变了,上一次的结果作废。底部译文和翻译对照的每一行共用。
/// 同样的文字只请求一次(翻译器按内容缓存)。
mixin DebouncedTranslation<T extends StatefulWidget> on State<T> {
  String get source;
  String get targetLang;
  Translator get translator;

  String? translated;
  String? error;

  /// [translated] / [error] 是哪段原文的结果。
  String? _for;
  Timer? _timer;

  bool get waiting => _for != source && source.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    if (_for == source) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 400), () async {
      final src = source;
      String? out, err;
      try {
        out = await translator.translate(src, targetLang);
      } on LlmError catch (e) {
        err = e.message;
      }
      if (!mounted || src != source) return;
      setState(() {
        translated = out;
        error = err;
        _for = src;
      });
    });
  }
}

/// 编辑器底部的中文译文:只对照,不改标注。
class GlossPane extends StatefulWidget {
  const GlossPane({super.key, required this.text, required this.translator});

  final String text;
  final Translator translator;

  @override
  State<GlossPane> createState() => _GlossPaneState();
}

class _GlossPaneState extends State<GlossPane> with DebouncedTranslation {
  @override
  String get source => widget.text;
  @override
  String get targetLang => 'zh';
  @override
  Translator get translator => widget.translator;

  @override
  Widget build(BuildContext context) {
    final caption = TextStyle(fontSize: 11, color: NlColors.slate500);
    return Container(
      constraints: const BoxConstraints(maxHeight: 130),
      decoration: BoxDecoration(color: NlColors.card, border: Border(top: BorderSide(color: NlColors.border))),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.subtitles_outlined, size: 13, color: NlColors.slate500),
            const SizedBox(width: 5),
            Text('译文 · 中文 · 只对照', style: caption),
            const Spacer(),
            if (waiting) Text('翻译中…', style: caption),
          ]),
          const SizedBox(height: 4),
          Flexible(
            child: SingleChildScrollView(
              child: AnimatedOpacity(
                opacity: waiting ? .5 : 1,
                duration: const Duration(milliseconds: 200),
                child: error != null
                    ? Text(error!, style: TextStyle(fontSize: 12, color: NlColors.amber))
                    : SelectableText(translated ?? '', style: monoStyle.copyWith(color: NlColors.slate700)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
