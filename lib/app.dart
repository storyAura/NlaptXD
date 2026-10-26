import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'data/config_store.dart';
import 'ui/core/look_switcher.dart';
import 'ui/core/theme.dart';
import 'ui/core/widgets.dart';
import 'ui/features/workspace/workspace.dart';
import 'ui/shell.dart';

class NlaptApp extends StatelessWidget {
  const NlaptApp({super.key, required this.config, required this.ws, this.windowChrome = true});

  final ConfigStore config;
  final Workspace ws;

  /// 测试里没有原生窗口,不画自绘标题栏。
  final bool windowChrome;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NLapt',
    debugShowCheckedModeBanner: false,
    theme: nlTheme(),
    // 深浅色有自己的圆形扩散(LookSwitcher),主题不再渐变一遍。
    themeAnimationDuration: Duration.zero,
    // ponytail: 整个界面不出无障碍语义树。Flutter 3.47 的 Windows 无障碍桥有空指针崩溃
    // (flutter/flutter#175041),有读屏 / 输入法这类 UIA 程序在读窗口时切页会闪退(Penna 踩过)。
    // 代价是读屏软件读不到界面;引擎修好后去掉这层。
    builder: (context, child) => ExcludeSemantics(
      child: LookSwitcher(
        config: config,
        child: Column(
          children: [
            if (windowChrome)
              SizedBox(
                height: kWindowCaptionHeight,
                child: WindowCaption(
                  brightness: NlColors.isDark ? Brightness.dark : Brightness.light,
                  backgroundColor: NlColors.sidebar,
                  title: const Wordmark(height: 18),
                ),
              ),
            Expanded(child: child!),
          ],
        ),
      ),
    ),
    home: AppShell(ws: ws, config: config),
  );
}
