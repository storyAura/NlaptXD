import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion.dart';
import 'theme.dart';
import 'widgets.dart';

/// 下拉选择:字段 + 浮层菜单(替代 Material 的 DropdownButton)。
/// 展开时菜单从字段下方淡入、往下展开一点,收起时反着播完再消失;点菜单外或按 Esc 收起。
class NlSelect<T> extends StatefulWidget {
  const NlSelect({super.key, required this.value, required this.items, required this.onChanged, this.hint = '请选择'});

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  /// [value] 不在 [items] 里时显示。
  final String hint;

  @override
  State<NlSelect<T>> createState() => _NlSelectState<T>();
}

class _NlSelectState<T> extends State<NlSelect<T>> with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  late final _anim = AnimationController(vsync: this);
  double _width = 0;

  bool get _open => _anim.status == AnimationStatus.forward || _anim.status == AnimationStatus.completed;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _show() {
    if (widget.items.isEmpty) return;
    _width = context.size?.width ?? 0;
    _portal.show();
    _anim.duration = Motion.of(context, Motion.base);
    _anim.forward();
    setState(() {});
  }

  Future<void> _hide() async {
    if (!_open) return;
    setState(() {});
    await _anim.reverse();
    if (mounted && _anim.isDismissed) _portal.hide();
  }

  void _pick(T v) {
    _hide();
    if (v != widget.value) widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final label = [for (final (v, l) in widget.items) if (v == widget.value) l].firstOrNull;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (_) => _menu(),
      child: CompositedTransformTarget(
        link: _link,
        child: Hover(
          cursor: SystemMouseCursors.click,
          builder: (hover) => GestureDetector(
            onTap: () => _open ? _hide() : _show(),
            child: AnimatedContainer(
              duration: Motion.base,
              curve: Motion.swift,
              padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
              decoration: BoxDecoration(
                color: NlColors.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _open ? NlColors.primary : hover ? NlColors.slate400 : NlColors.border,
                  width: _open ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label ?? widget.hint,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: label == null ? NlColors.slate400 : NlColors.text),
                    ),
                  ),
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
        ),
      ),
    );
  }

  Widget _menu() {
    final curved = CurvedAnimation(parent: _anim, curve: Motion.swift, reverseCurve: Curves.easeInCubic);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _hide},
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            // 点菜单外收起;收起动画播放时不挡点击。
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_open,
                child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _hide),
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomLeft,
              offset: const Offset(0, 4),
              child: IgnorePointer(
                ignoring: !_open,
                child: FadeTransition(
                  opacity: curved,
                  child: SizeTransition(
                    sizeFactor: Tween(begin: .6, end: 1.0).animate(curved),
                    alignment: Alignment.topCenter,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, -.04), end: Offset.zero).animate(curved),
                      child: _list(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list() => Container(
    width: _width,
    constraints: const BoxConstraints(maxHeight: 280),
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: NlColors.card,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: NlColors.border),
      boxShadow: [BoxShadow(color: NlColors.shadow, blurRadius: 16, offset: const Offset(0, 6))],
    ),
    child: Material(
      type: MaterialType.transparency,
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (final (v, l) in widget.items)
            Hover(
              cursor: SystemMouseCursors.click,
              builder: (hover) {
                final on = v == widget.value;
                return GestureDetector(
                  onTap: () => _pick(v),
                  child: AnimatedContainer(
                    duration: Motion.snap,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      color: on ? NlColors.primaryBg : hover ? NlColors.slate100 : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: on ? NlColors.primary : NlColors.text),
                          ),
                        ),
                        if (on) Icon(Icons.check, size: 15, color: NlColors.primary),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    ),
  );
}
