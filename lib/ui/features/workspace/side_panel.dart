import 'package:flutter/material.dart';

import '../../../data/config_store.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../local/local_store.dart';
import 'batch_edit_tab.dart';
import 'history_tab.dart';
import 'infer_tab.dart';
import 'workspace.dart';

enum _Tab { infer, edit, history }

const scopeLabels = {
  Scope.current: '当前',
  Scope.folder: '文件夹',
  Scope.selected: '已选',
  Scope.unlabeled: '未标注',
  Scope.all: '全部',
};

/// 一排范围药丸;范围里没有图的禁用。
Widget scopeChips(Workspace ws, List<Scope> scopes, Scope value, ValueChanged<Scope> onChanged) => Wrap(
  spacing: 6,
  runSpacing: 6,
  children: [
    for (final s in scopes)
      NlChip(
        label: scopeLabels[s]!,
        count: s == Scope.current ? null : ws.scopeEntries(s).length,
        selected: s == value,
        onTap: ws.scopeEntries(s).isEmpty ? null : () => onChanged(s),
      ),
  ],
);

/// 右栏:推标 / 批量修改 / 历史。
class SidePanel extends StatefulWidget {
  const SidePanel({
    super.key,
    required this.ws,
    required this.config,
    required this.local,
    required this.onGoModels,
    required this.onGoLog,
  });

  final Workspace ws;
  final ConfigStore config;
  final LocalStore local;
  final VoidCallback onGoModels;
  final VoidCallback onGoLog;

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  _Tab _tab = _Tab.infer;

  @override
  Widget build(BuildContext context) => Container(
    color: NlColors.bg,
    child: Column(
      children: [
        NlBar(
          padding: 12,
          children: [
            Expanded(
              child: Seg<_Tab>(
                expand: true,
                value: _tab,
                onChanged: (t) => setState(() => _tab = t),
                items: const [(_Tab.infer, '推标', null), (_Tab.edit, '批量修改', null), (_Tab.history, '历史', null)],
              ),
            ),
          ],
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: Motion.of(context, Motion.base),
            switchInCurve: Motion.enter,
            layoutBuilder: fillLayout,
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: const Offset(0, .02), end: Offset.zero).animate(a), child: c),
            ),
            child: KeyedSubtree(
              key: ValueKey(_tab),
              child: switch (_tab) {
                _Tab.infer => InferTab(ws: widget.ws, config: widget.config, local: widget.local, onGoModels: widget.onGoModels),
                _Tab.edit => BatchEditTab(ws: widget.ws, config: widget.config, onGoLog: widget.onGoLog),
                _Tab.history => HistoryTab(ws: widget.ws, onGoLog: widget.onGoLog),
              },
            ),
          ),
        ),
      ],
    ),
  );
}
