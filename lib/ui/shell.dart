import 'package:flutter/material.dart';

import '../data/config_store.dart';
import 'core/look_switcher.dart';
import 'core/motion.dart';
import 'core/theme.dart';
import 'core/widgets.dart';
import 'features/local/local_page.dart';
import 'features/local/local_store.dart';
import 'features/log/log_page.dart';
import 'features/models/models_page.dart';
import 'features/settings/settings_page.dart';
import 'features/workspace/workspace.dart';
import 'features/workspace/workspace_page.dart';

/// 左侧 48px 导航轨 + 五页。各页常驻(切页不丢输入),切换时淡入并轻轻上移。
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.ws, required this.config, required this.local});

  final Workspace ws;
  final ConfigStore config;
  final LocalStore local;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _page = 0;

  static const _nav = [
    (Icons.space_dashboard_outlined, '标注台'),
    (Icons.history, '操作日志'),
    (Icons.hub_outlined, '模型'),
    (Icons.download_for_offline_outlined, '本地模型'),
    (Icons.settings_outlined, '设置'),
  ];

  void _go(int i) => setState(() => _page = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      WorkspacePage(ws: widget.ws, config: widget.config, local: widget.local, onGo: _go),
      LogPage(ws: widget.ws),
      ModelsPage(config: widget.config, local: widget.local),
      LocalPage(local: widget.local, config: widget.config),
      SettingsPage(config: widget.config),
    ];
    return Scaffold(
      backgroundColor: NlColors.bg,
      body: Row(
        children: [
          Container(
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: NlColors.sidebar, border: Border(right: BorderSide(color: NlColors.border))),
            child: Column(
              children: [
                for (final (i, (icon, label)) in _nav.indexed) ...[
                  NlIconButton(icon, size: 32, tooltip: label, selected: _page == i, onPressed: () => _go(i)),
                  const SizedBox(height: 4),
                ],
                const Spacer(),
                Listener(
                  onPointerDown: (e) => lookRevealOrigin = e.position,
                  child: NlIconButton(
                    NlColors.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                    size: 32,
                    tooltip: NlColors.isDark ? '浅色' : '深色',
                    onPressed: () => widget.config.update(widget.config.config.copyWith(darkMode: !NlColors.isDark)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                for (final (i, page) in pages.indexed)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: i != _page,
                      // 淡出 / 上移放在 TickerMode 外面:包在里面的话,离开的那页一被暂停,
                      // 淡出就卡在不透明,底下的页会透出来(踩过)。
                      child: AnimatedOpacity(
                        opacity: i == _page ? 1 : 0,
                        duration: Motion.of(context, Motion.base),
                        curve: Motion.swift,
                        child: AnimatedSlide(
                          offset: i == _page ? Offset.zero : const Offset(0, .015),
                          duration: Motion.of(context, Motion.sheet),
                          curve: Motion.enter,
                          child: TickerMode(
                            enabled: i == _page,
                            child: ExcludeFocus(excluding: i != _page, child: page),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
