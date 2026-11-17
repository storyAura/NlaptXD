import 'package:flutter/material.dart';

import '../../../core/cha.dart';
import '../../../core/dataset.dart';
import '../../core/select.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../workspace/engines.dart';

/// 「试跑一张」:开始整批前,用全部角色卡按整批的方式推一张图,看接口收不收这么多卡和参考图、
/// 要多久、回答能不能读出来。结果只显示,不写盘。
class ChaPreflight extends StatefulWidget {
  const ChaPreflight({super.key, required this.images, required this.roster, required this.ask});

  final List<ImageEntry> images;

  /// 点按钮时才取:确认页上的改动都算进去。
  final List<ChaCard> Function() roster;

  /// 整批画面用的模型;null = 不可用。
  final VisionAsk? ask;

  @override
  State<ChaPreflight> createState() => _ChaPreflightState();
}

typedef _Result = ({String image, Duration took, int sent, int chars, String? matched, String? caption, String? error});

class _ChaPreflightState extends State<ChaPreflight> {
  late final List<String> _folders = [...{for (final e in widget.images) e.folder}];

  /// 默认挑没绑定的文件夹:那里要用全部卡认人,最吃力。
  late String _folder = () {
    final bound = {for (final c in widget.roster()) ?c.bind?.folder};
    return _folders.where((f) => !bound.contains(f)).firstOrNull ?? _folders.firstOrNull ?? '';
  }();

  /// 每点一次换下一张。
  int _turn = 0;
  bool _busy = false;
  _Result? _result;

  String _folderName(String f) => f.isEmpty ? '根目录' : f;

  Future<void> _run() async {
    final ask = widget.ask;
    final pool = [for (final e in widget.images) if (e.folder == _folder) e];
    if (ask == null || pool.isEmpty) return;
    final image = pool[_turn++ % pool.length];
    final roster = widget.roster();
    var (sent, chars) = (0, 0);
    final hits = <int, List<ImageEntry>>{};
    setState(() => _busy = true);
    final watch = Stopwatch()..start();
    _Result result;
    try {
      final caption = await chaCaptioner(roster, ({required prompt, system = '', required images}) {
        (sent, chars) = (images.length, prompt.length);
        return ask(prompt: prompt, system: system, images: images);
      }, hits)(image);
      result = (
        image: image.name,
        took: watch.elapsed,
        sent: sent,
        chars: chars,
        matched: [for (final i in hits.keys.toList()..sort()) '卡 ${i + 1} ${roster[i].name}'].join('、'),
        caption: caption,
        error: null,
      );
    } on Object catch (e) {
      result = (image: image.name, took: watch.elapsed, sent: sent, chars: chars, matched: null, caption: null, error: '$e');
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _result = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final label = TextStyle(fontSize: 11.5, color: NlColors.slate500);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const Text('试跑一张', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(child: Text('先看接口吃不吃得下这么多卡和参考图 · 不写盘', style: label, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          if (_folders.length > 1) ...[
            SizedBox(
              width: 220,
              child: NlSelect<String>(
                value: _folder,
                items: [for (final f in _folders) (f, _folderName(f))],
                onChanged: (f) => setState(() {
                  _folder = f;
                  _turn = 0;
                }),
              ),
            ),
            const SizedBox(width: 8),
          ],
          NlButton(
            label: _busy ? '试跑中…' : r == null ? '试跑一张' : '再试一张',
            icon: Icons.science_outlined,
            tone: Tone.outline,
            busy: _busy,
            onPressed: widget.ask != null && !_busy ? _run : null,
          ),
        ]),
        if (r != null) ...[
          const SizedBox(height: 8),
          Text(
            [
              r.image,
              '${(r.took.inMilliseconds / 1000).toStringAsFixed(1)} 秒',
              '发了 ${r.sent} 张图',
              '提示词 ${r.chars} 字符',
            ].join(' · '),
            style: label,
          ),
          const SizedBox(height: 4),
          if (r.error != null)
            Text('失败:${r.error}', style: TextStyle(fontSize: 12, color: NlColors.diffDelText))
          else if (r.caption == null)
            Text('没认出任何角色卡:整批时这张会跳过', style: TextStyle(fontSize: 12, color: NlColors.lockText))
          else ...[
            Text('认出:${r.matched}', style: TextStyle(fontSize: 12, color: NlColors.accent, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: SelectableText(r.caption!, style: monoStyle.copyWith(fontSize: 12)),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
