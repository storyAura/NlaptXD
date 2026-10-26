import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../data/config_store.dart';
import 'motion.dart';
import 'theme.dart';

/// 深浅色切换从哪里扩散开:点开关时记下它的窗口坐标,没有就从窗口中间。
Offset? lookRevealOrigin;

/// 盯着设置里的深色模式(移植自 Penna):变了就换配色、整棵树重建,
/// 先拍下旧画面盖在上面,再从 [lookRevealOrigin] 起一圈圈露出新画面。
class LookSwitcher extends StatefulWidget {
  const LookSwitcher({super.key, required this.config, required this.child});

  final ConfigStore config;
  final Widget child;

  @override
  State<LookSwitcher> createState() => _LookSwitcherState();
}

class _LookSwitcherState extends State<LookSwitcher> with SingleTickerProviderStateMixin {
  final _shot = GlobalKey();
  late final _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 620));
  ui.Image? _old;
  Offset? _origin;

  @override
  void initState() {
    super.initState();
    widget.config.addListener(_onConfig);
  }

  @override
  void dispose() {
    widget.config.removeListener(_onConfig);
    _reveal.dispose();
    _old?.dispose();
    super.dispose();
  }

  void _onConfig() {
    final dark = widget.config.config.darkMode;
    if (dark == NlColors.isDark) return;
    _snapshot();
    NlColors.useDark(dark);
    // 颜色都是取值时才读,const 部件也要重建:走热重载那条路(正式版同样可用)。
    WidgetsBinding.instance.reassembleApplication();
  }

  void _snapshot() {
    final boundary = _shot.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || !boundary.hasSize || MediaQuery.maybeDisableAnimationsOf(context) == true) return;
    final ui.Image image;
    try {
      image = boundary.toImageSync(pixelRatio: MediaQuery.devicePixelRatioOf(context));
    } on Object {
      return; // 拍不下来就不放动画,直接换。
    }
    _old?.dispose();
    setState(() {
      _old = image;
      _origin = lookRevealOrigin == null ? null : boundary.globalToLocal(lookRevealOrigin!);
    });
    lookRevealOrigin = null;
    _reveal.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _old?.dispose();
        _old = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final old = _old;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        RepaintBoundary(key: _shot, child: widget.child),
        if (old != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RevealPainter(
                  image: old,
                  origin: _origin,
                  progress: CurvedAnimation(parent: _reveal, curve: Motion.expand),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 画旧画面,挖掉一个从 [origin] 起越来越大的圆,圆里透出新画面。
class _RevealPainter extends CustomPainter {
  _RevealPainter({required this.image, required this.origin, required this.progress}) : super(repaint: progress);

  final ui.Image image;
  final Offset? origin;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = origin ?? size.center(Offset.zero);
    final reach = [Offset.zero, Offset(size.width, 0), Offset(0, size.height), Offset(size.width, size.height)]
        .map((c) => (c - center).distance)
        .reduce(math.max);
    final hole = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: center, radius: reach * progress.value));
    canvas
      ..save()
      ..clipPath(hole)
      ..drawImageRect(
        image,
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_RevealPainter old) => old.image != image || old.origin != origin;
}
