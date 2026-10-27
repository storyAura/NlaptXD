import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/dataset.dart';
import '../../../core/json_caption.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'json_editor.dart';
import 'workspace.dart';

/// 宽、高、字节数。只读文件头(ImageDescriptor),不整张解码。
final _metaCache = <String, Future<(int, int, int)>>{};

Future<(int, int, int)> _meta(String path) => _metaCache.putIfAbsent(path, () async {
  final buffer = await ui.ImmutableBuffer.fromFilePath(path);
  final d = await ui.ImageDescriptor.encoded(buffer);
  final size = (d.width, d.height, buffer.length);
  d.dispose();
  buffer.dispose();
  return size;
});

String _bytes(int n) => n >= 1 << 20 ? '${(n / (1 << 20)).toStringAsFixed(2)} MB' : '${(n / 1024).toStringAsFixed(0)} KB';

/// 中栏上半:文件信息栏 + 看图区(单张可缩放,多选时最多四张对比)。
class PreviewPane extends StatelessWidget {
  const PreviewPane({super.key, required this.ws});

  final Workspace ws;

  /// JSON 视图时,标注是 MOSS 布局就在图上画框(原图宽高读文件头)。
  Widget? _boxes(ImageEntry e) {
    final layout = ws.mode == EditMode.json ? readMossLayout(ws.textOf(e)) : null;
    if (layout == null) return null;
    return FutureBuilder(
      future: _meta(e.imagePath),
      builder: (_, s) => s.data == null
          ? const SizedBox.shrink()
          : JsonBoxOverlay(layout: layout, width: s.data!.$1, height: s.data!.$2, selected: ws.box, onTap: ws.selectBox),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = ws.entry!;
    final dirty = ws.isDirty(e);
    final multi = ws.selected.length > 1 && ws.selected.contains(ws.current);
    final ext = e.name.contains('.') ? e.name.split('.').last.toUpperCase() : '';
    return Column(
      children: [
        NlBar(
          children: [
            Flexible(child: Text(e.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
            const SizedBox(width: 8),
            Pill(ext),
            const SizedBox(width: 8),
            FutureBuilder(
              future: _meta(e.imagePath),
              builder: (_, s) => AnimatedOpacity(
                duration: Motion.base,
                opacity: s.hasData ? 1 : 0,
                child: Text(
                  s.data == null ? '' : '${s.data!.$1}×${s.data!.$2} · ${_bytes(s.data!.$3)}',
                  style: TextStyle(fontSize: 11.5, color: NlColors.slate500),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: Motion.base,
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
              child: dirty ? const Pill('未保存', tone: PillTone.warn, key: ValueKey('dirty')) : const SizedBox.shrink(),
            ),
            if (ws.nonUtf8.contains(e.key)) ...[
              const SizedBox(width: 6),
              const Tooltip(message: '原文不是 UTF-8,保存后转成 UTF-8', child: Pill('编码', tone: PillTone.bad)),
            ],
            if (multi) ...[const SizedBox(width: 6), Pill('对比 · 已选 ${ws.selected.length}', tone: PillTone.blue)],
            const Spacer(),
            NlIconButton(Icons.chevron_left, tooltip: '上一张 Alt+↑', onPressed: () => ws.step(-1)),
            Text('${ws.current + 1} / ${ws.entries.length}', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
            NlIconButton(Icons.chevron_right, tooltip: '下一张 Alt+↓', onPressed: () => ws.step(1)),
            const SizedBox(width: 8),
            NlButton(
              label: '保存',
              icon: Icons.save_outlined,
              tone: dirty ? Tone.primary : Tone.outline,
              tooltip: 'Ctrl+S',
              onPressed: dirty ? ws.save : null,
            ),
          ],
        ),
        Expanded(
          child: ColoredBox(
            color: NlColors.stage,
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.sheet),
              switchInCurve: Motion.enter,
              layoutBuilder: fillLayout,
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(scale: Tween(begin: .985, end: 1.0).animate(a), child: c),
              ),
              child: multi
                  ? _Compare(key: const ValueKey('compare'), ws: ws)
                  : _Viewer(key: ValueKey(e.imagePath), entry: e, overlay: _boxes(e)),
            ),
          ),
        ),
      ],
    );
  }
}

class _Viewer extends StatefulWidget {
  const _Viewer({super.key, required this.entry, this.overlay});

  final ImageEntry entry;

  /// 叠在图上、和图一样大(JSON 视图的框)。
  final Widget? overlay;

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> with SingleTickerProviderStateMixin {
  final _t = TransformationController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: Motion.sheet)
    ..addListener(() => _t.value = _tween.evaluate(_curve));
  late final CurvedAnimation _curve = CurvedAnimation(parent: _anim, curve: Motion.swift);
  Matrix4Tween _tween = Matrix4Tween();
  Size _box = Size.zero;

  @override
  void dispose() {
    _anim.dispose();
    _t.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target) {
    _tween = Matrix4Tween(begin: _t.value, end: target);
    _anim.forward(from: 0);
  }

  /// 以看图区中心为原点缩放到 [scale] 倍(1 = 适应)。
  void _zoom(double scale) {
    final s = scale.clamp(.4, 4.0);
    final c = _box.center(Offset.zero);
    _animateTo(Matrix4.identity()
      ..translateByDouble(c.dx * (1 - s), c.dy * (1 - s), 0, 1)
      ..scaleByDouble(s, s, 1, 1));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      _box = c.biggest;
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: () => _zoom(_t.value.getMaxScaleOnAxis() > 1.01 ? 1 : 2),
              child: InteractiveViewer(
                transformationController: _t,
                minScale: .4,
                maxScale: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(boxShadow: [BoxShadow(color: NlColors.shadow, blurRadius: 24, offset: const Offset(0, 12))]),
                      child: Stack(
                        children: [
                          Image.file(
                            File(widget.entry.imagePath),
                            fit: BoxFit.contain,
                            cacheWidth: 2048,
                            errorBuilder: (_, _, _) => Text('无法读取图片', style: TextStyle(color: NlColors.slate500)),
                          ),
                          if (widget.overlay != null) Positioned.fill(child: widget.overlay!),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: NlColors.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: NlColors.border),
              ),
              child: ValueListenableBuilder(
                valueListenable: _t,
                builder: (_, m, _) {
                  final s = m.getMaxScaleOnAxis();
                  return Row(
                    children: [
                      NlIconButton(Icons.remove, size: 24, onPressed: () => _zoom(s - .2)),
                      GestureDetector(
                        onTap: () => _zoom(1),
                        child: SizedBox(
                          width: 46,
                          child: Text((s - 1).abs() < .01 ? '适应' : '${(s * 100).round()}%',
                              textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5)),
                        ),
                      ),
                      NlIconButton(Icons.add, size: 24, onPressed: () => _zoom(s + .2)),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _Compare extends StatelessWidget {
  const _Compare({super.key, required this.ws});

  final Workspace ws;

  @override
  Widget build(BuildContext context) {
    final keys = (ws.selected.toList()..sort()).take(4).toList();
    Widget cell(int i) {
      final e = ws.entries[i];
      final cur = i == ws.current;
      return GestureDetector(
        onTap: () => ws.select(i),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: Motion.base,
            curve: Motion.swift,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: NlColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cur ? NlColors.primary : NlColors.border, width: cur ? 2 : 1),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(File(e.imagePath), fit: BoxFit.contain, cacheWidth: 1024),
                Positioned(left: 0, top: 0, child: Pill(cur ? '编辑中' : e.name, tone: cur ? PillTone.blue : PillTone.mute)),
              ],
            ),
          ),
        ),
      );
    }

    final rows = [keys.take(2).toList(), if (keys.length > 2) keys.skip(2).toList()];
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          for (final (r, row) in rows.indexed) ...[
            if (r > 0) const SizedBox(height: 10),
            Expanded(
              child: Row(
                children: [
                  for (final (k, i) in row.indexed) ...[
                    if (k > 0) const SizedBox(width: 10),
                    Expanded(child: PopIn(delay: Duration(milliseconds: 40 * (r * 2 + k)), child: cell(i))),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
