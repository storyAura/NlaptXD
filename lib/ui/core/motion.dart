import 'package:flutter/widgets.dart';

/// 动效令牌(同 Penna):时长四档、曲线三种,都是快起慢收。各处动画只用这里的。
abstract final class Motion {
  /// 按下、焦点环。
  static const fast = Duration(milliseconds: 60);

  /// 分段按钮、标签切换、小的颜色变化。
  static const snap = Duration(milliseconds: 120);

  /// 悬停、菜单、折叠展开、卡片变化。
  static const base = Duration(milliseconds: 200);

  /// 侧栏、面板、新出现的块、换页。
  static const sheet = Duration(milliseconds: 300);

  static const swift = Cubic(0.16, 1, 0.3, 1);
  static const expand = Cubic(0.19, 1, 0.22, 1);
  static const enter = Cubic(0.22, 1, 0.36, 1);

  /// 系统设了「减少动画」时直接跳到结尾。
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : d;
}

/// AnimatedSwitcher 的布局:新旧两页都铺满、左上对齐(默认是居中、按内容大小)。
Widget fillLayout(Widget? current, List<Widget> previous) => Stack(
  fit: StackFit.expand,
  alignment: Alignment.topLeft,
  children: [...previous, ?current],
);
