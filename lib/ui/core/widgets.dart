import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'motion.dart';
import 'theme.dart';

/// NLaptXD 字标。深色模式下字母左半的深紫会融进底色,所以在后面垫一层
/// 模糊的霓虹亮紫(Design/design.md 的 #9D4EDD)当微光。
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, required this.height});

  final double height;
  static const _glow = Color(0xCC9D4EDD);

  @override
  Widget build(BuildContext context) {
    final mark = Image.asset('assets/wordmark.png', height: height, filterQuality: FilterQuality.medium);
    if (!NlColors.isDark) return mark;
    final sigma = height * .2;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
          child: ColorFiltered(colorFilter: const ColorFilter.mode(_glow, BlendMode.srcIn), child: mark),
        ),
        mark,
      ],
    );
  }
}

/// 按下时缩一下、松手时轻轻弹回(同 Penna)。
class Bouncy extends StatefulWidget {
  const Bouncy({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<Bouncy> createState() => _BouncyState();
}

class _BouncyState extends State<Bouncy> {
  bool _down = false;

  void _set(bool down) {
    if (mounted && widget.enabled) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _set(true),
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _down ? 0.975 : 1,
      duration: Motion.of(context, _down ? Motion.fast : const Duration(milliseconds: 450)),
      curve: _down ? Curves.easeOut : Curves.easeOutBack,
      child: widget.child,
    ),
  );
}

/// 出现时从下方 12px 淡入(新块入场)。换了 [key] 会重新播放。
class PopIn extends StatelessWidget {
  const PopIn({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final total = Motion.sheet + delay;
    final start = total.inMicroseconds == 0 ? 0.0 : delay.inMicroseconds / total.inMicroseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.of(context, total),
      curve: Interval(start, 1, curve: Motion.enter),
      child: child,
      builder: (_, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
      ),
    );
  }
}

/// 鼠标悬停状态。
class Hover extends StatefulWidget {
  const Hover({super.key, required this.builder, this.cursor = SystemMouseCursors.basic});

  final Widget Function(bool hover) builder;
  final MouseCursor cursor;

  @override
  State<Hover> createState() => _HoverState();
}

class _HoverState extends State<Hover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.cursor,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: widget.builder(_hover),
  );
}

enum Tone { normal, outline, ghost, primary, danger }

/// 小号圆角按钮。[onPressed] 为 null 时禁用;[busy] 时显示转圈并防连点。
class NlButton extends StatelessWidget {
  const NlButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = Tone.normal,
    this.tooltip,
    this.busy = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Tone tone;
  final String? tooltip;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final button = Hover(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      builder: (hover) {
        final (bg, fg, border) = switch (tone) {
          _ when !enabled && tone != Tone.primary => (NlColors.slate100, NlColors.slate400, Colors.transparent),
          _ when !enabled => (NlColors.primary.withValues(alpha: .55), Colors.white, Colors.transparent),
          Tone.primary => (hover ? Color.lerp(NlColors.primary, Colors.white, .08)! : NlColors.primary, Colors.white, Colors.transparent),
          Tone.outline => (hover ? NlColors.slate100 : NlColors.card, NlColors.slate700, NlColors.border),
          Tone.ghost => (hover ? NlColors.slate100 : Colors.transparent, hover ? NlColors.text : NlColors.slate500, Colors.transparent),
          Tone.danger => (hover ? NlColors.diffDel : Colors.transparent, hover ? NlColors.diffDelText : NlColors.slate500, Colors.transparent),
          Tone.normal => (hover ? NlColors.slate100 : NlColors.card, NlColors.slate700, Colors.transparent),
        };
        return Bouncy(
          enabled: enabled,
          child: GestureDetector(
            onTap: enabled ? onPressed : null,
            child: AnimatedContainer(
              duration: Motion.base,
              curve: Motion.swift,
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: expand ? 10 : 7),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: border),
              ),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    SizedBox.square(dimension: 13, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                  else if (icon != null)
                    Icon(icon, size: 15, color: fg),
                  if ((busy || icon != null) && label.isNotEmpty) const SizedBox(width: 5),
                  if (label.isNotEmpty)
                    Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg, height: 1.2)),
                ],
              ),
            ),
          ),
        );
      },
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// 28×28 的图标按钮。
class NlIconButton extends StatelessWidget {
  const NlIconButton(this.icon, {super.key, required this.onPressed, this.tooltip, this.selected = false, this.size = 28});

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final w = Hover(
      cursor: onPressed == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      builder: (hover) => Bouncy(
        enabled: onPressed != null,
        child: GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: Motion.base,
            curve: Motion.swift,
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: selected ? NlColors.primaryBg : hover && onPressed != null ? NlColors.slate100 : Colors.transparent,
              borderRadius: BorderRadius.circular(size > 30 ? 8 : 6),
            ),
            child: Icon(
              icon,
              size: size * .62,
              color: onPressed == null
                  ? NlColors.slate400
                  : selected
                  ? NlColors.primary
                  : hover
                  ? NlColors.text
                  : NlColors.slate500,
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? w : Tooltip(message: tooltip, child: w);
  }
}

/// 可选中的小药丸(同 Penna 的 PennaChip),选中时带勾。
class NlChip extends StatelessWidget {
  const NlChip({super.key, required this.label, required this.selected, required this.onTap, this.count});

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = !enabled ? NlColors.slate400 : selected ? NlColors.primary : NlColors.slate700;
    return Hover(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      builder: (hover) => Bouncy(
        enabled: enabled,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.base,
            curve: Motion.swift,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? NlColors.primaryBg : NlColors.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? NlColors.primaryBorder : hover && enabled ? NlColors.slate400 : NlColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSize(
                  duration: Motion.base,
                  curve: Motion.expand,
                  child: selected
                      ? Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.check, size: 13, color: color))
                      : const SizedBox.shrink(),
                ),
                Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
                if (count != null)
                  Text(' $count', style: TextStyle(fontSize: 12, color: color.withValues(alpha: .7))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 分段切换。[expand] 时各段等宽,底下的白块滑过去。
class Seg<T> extends StatelessWidget {
  const Seg({super.key, required this.items, required this.value, required this.onChanged, this.expand = false});

  final List<(T, String, IconData?)> items;
  final T value;
  final ValueChanged<T>? onChanged;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final index = items.indexWhere((i) => i.$1 == value);
    Widget item((T, String, IconData?) it) {
      final on = it.$1 == value;
      final color = on ? NlColors.text : NlColors.slate500;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onChanged == null ? null : () => onChanged!(it.$1),
          child: AnimatedContainer(
            duration: Motion.snap,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: on && !expand ? NlColors.card : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              boxShadow: on && !expand ? [BoxShadow(color: NlColors.shadow, blurRadius: 2, offset: const Offset(0, 1))] : null,
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (it.$3 != null) Icon(it.$3, size: 15, color: color),
                if (it.$3 != null && it.$2.isNotEmpty) const SizedBox(width: 4),
                if (it.$2.isNotEmpty)
                  AnimatedDefaultTextStyle(
                    duration: Motion.snap,
                    style: uiFont.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                    child: Text(it.$2),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final box = BoxDecoration(color: NlColors.slate100, borderRadius: BorderRadius.circular(8));
    if (!expand) {
      return Container(padding: const EdgeInsets.all(2), decoration: box, child: Row(mainAxisSize: MainAxisSize.min, children: [for (final it in items) item(it)]));
    }
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: box,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              duration: Motion.of(context, Motion.base),
              curve: Motion.swift,
              alignment: Alignment(items.length == 1 ? 0 : -1 + 2 * index / (items.length - 1), 0),
              child: FractionallySizedBox(
                widthFactor: 1 / items.length,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: NlColors.card,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [BoxShadow(color: NlColors.shadow, blurRadius: 2, offset: const Offset(0, 1))],
                  ),
                ),
              ),
            ),
          ),
          Row(children: [for (final it in items) Expanded(child: item(it))]),
        ],
      ),
    );
  }
}

enum PillTone { mute, blue, ok, warn, bad }

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.tone = PillTone.mute, this.icon});

  final String text;
  final PillTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (tone) {
      PillTone.mute => (NlColors.slate100, NlColors.slate500, Colors.transparent),
      PillTone.blue => (NlColors.primaryBg, NlColors.primary, Colors.transparent),
      PillTone.ok => (NlColors.diffAdd, NlColors.diffAddText, Colors.transparent),
      PillTone.warn => (NlColors.lock, NlColors.lockText, NlColors.lockBorder),
      PillTone.bad => (NlColors.diffDel, NlColors.diffDelText, Colors.transparent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: Border.all(color: border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: fg), const SizedBox(width: 3)],
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg, height: 1.4)),
        ],
      ),
    );
  }
}

/// 未保存的琥珀色小圆点,出现时弹一下。
class UnsavedDot extends StatelessWidget {
  const UnsavedDot({super.key});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Motion.of(context, Motion.sheet),
    curve: Curves.easeOutBack,
    builder: (_, t, _) => Transform.scale(
      scale: t,
      child: Container(width: 7, height: 7, decoration: BoxDecoration(color: NlColors.amber, shape: BoxShape.circle)),
    ),
  );
}

const nlBarHeight = 48.0;

/// 面板顶栏。并排各栏都用它,底边才对得齐。
class NlBar extends StatelessWidget {
  const NlBar({super.key, required this.children, this.padding = 16});

  final List<Widget> children;
  final double padding;

  @override
  Widget build(BuildContext context) => Container(
    height: nlBarHeight,
    padding: EdgeInsets.symmetric(horizontal: padding),
    decoration: BoxDecoration(color: NlColors.slate50, border: Border(bottom: BorderSide(color: NlColors.border))),
    child: Row(children: children),
  );
}

class NlCard extends StatelessWidget {
  const NlCard({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.color, this.borderColor});

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: Motion.base,
    curve: Motion.swift,
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? NlColors.card,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: borderColor ?? NlColors.border),
    ),
    child: child,
  );
}

/// 15×15 的复选框(可三态:[partial])。
class NlCheck extends StatelessWidget {
  const NlCheck({super.key, required this.value, required this.onTap, this.partial = false});

  final bool value;
  final bool partial;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = value || partial;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.snap,
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            color: on ? NlColors.primary : NlColors.card,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: on ? NlColors.primary : NlColors.slate400, width: 1.5),
          ),
          child: AnimatedSwitcher(
            duration: Motion.snap,
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: on
                ? Icon(value ? Icons.check : Icons.remove, key: ValueKey(value), size: 11, color: Colors.white)
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// 小标题(分区名)。
class Label extends StatelessWidget {
  const Label(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Text(text, style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
        if (trailing != null) ...[const SizedBox(width: 6), Flexible(child: trailing!)],
      ],
    ),
  );
}

/// 底部提示。[action] 是一个可点的后续操作(如「撤销」「查看日志」)。
void showToast(BuildContext context, String message, {bool warn = false, (String, VoidCallback)? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        width: 420,
        behavior: SnackBarBehavior.floating,
        backgroundColor: NlColors.toast,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: Duration(milliseconds: action == null ? 2600 : 5000),
        content: Row(
          children: [
            Icon(warn ? Icons.info_outline : Icons.check_circle, size: 16, color: warn ? NlColors.amber : const Color(0xFF34D399)),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 12.5, color: Colors.white))),
          ],
        ),
        action: action == null
            ? null
            : SnackBarAction(label: action.$1, textColor: const Color(0xFF9DB8FF), onPressed: action.$2),
      ),
    );
}

/// 确认弹窗:点 [ok] 返回 true,取消或点外面返回 false。
Future<bool> confirmDialog(BuildContext context, String title, String body, {String ok = '继续'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(body, style: TextStyle(fontSize: 12.5, color: NlColors.slate500)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    NlButton(label: '取消', tone: Tone.ghost, onPressed: () => Navigator.pop(context, false)),
                    const SizedBox(width: 8),
                    NlButton(label: ok, tone: Tone.primary, onPressed: () => Navigator.pop(context, true)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ) ??
    false;

/// 输入框:无标签,圆角 6,聚焦时描边变主色。
InputDecoration fieldDecoration(String hint, {IconData? icon}) => InputDecoration(
  hintText: hint,
  hintStyle: TextStyle(fontSize: 12.5, color: NlColors.slate400),
  isDense: true,
  filled: true,
  fillColor: NlColors.card,
  prefixIcon: icon == null ? null : Icon(icon, size: 16, color: NlColors.slate500),
  prefixIconConstraints: const BoxConstraints(minWidth: 34),
  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: NlColors.border)),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: NlColors.primary, width: 1.5)),
);
