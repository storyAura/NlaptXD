import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/dataset.dart';
import '../../../data/config_store.dart';
import '../local/local_store.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'caption_editor.dart';
import 'dataset_pane.dart';
import 'engines.dart';
import 'job_card.dart';
import 'preview_pane.dart';
import 'side_panel.dart';
import 'workspace.dart';

/// 选一个文件夹打开成数据集。
Future<void> pickDataset(BuildContext context, Workspace ws) async {
  final path = await getDirectoryPath(confirmButtonText: '打开');
  if (path == null) return;
  try {
    await ws.open(Directory(path));
  } on FileSystemException catch (e) {
    if (context.mounted) showToast(context, '打不开这个文件夹:${e.osError?.message ?? e.message}', warn: true);
  }
}

/// 标注台:数据集 | 预览 + 标注 | 推标侧栏;没打开数据集时是欢迎页。
class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key, required this.ws, required this.config, required this.local, required this.onGo});

  final Workspace ws;
  final ConfigStore config;
  final LocalStore local;

  /// 切到别的页(1 = 操作日志,2 = 模型)。
  final ValueChanged<int> onGo;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  Workspace get ws => widget.ws;
  double _editorH = 320;

  /// 输入框里的 Ctrl+Z 留给输入框自己。
  bool get _typing => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;

  Future<void> _save({bool all = false}) async {
    if (all) {
      final n = await ws.saveAll();
      if (mounted) showToast(context, n == 0 ? '没有未保存的修改' : '已保存 $n 个文件', warn: n == 0);
    } else if (ws.entry != null && ws.isDirty(ws.entry!)) {
      await ws.save();
      if (mounted) showToast(context, '已保存 ${ws.entry!.name}');
    }
  }

  /// 右键推标(用视觉模型):这一张先预览再采纳;一批的话,已有标注的先问一声,再打快照写盘。
  Future<void> _inferAt(int i, InferTarget target) async {
    final cfg = widget.config.config;
    final run = llmCaptioner(cfg, widget.local);
    // 「已选」不能改选择;其余范围按点的这张算文件夹。
    if (target != InferTarget.selected) ws.select(i);
    if (target == InferTarget.one) {
      final err = await ws.inferCurrent(run, modelLabel(cfg.vision, widget.local));
      if (err != null && mounted) showToast(context, err, warn: true);
      return;
    }
    if (run == null) return showToast(context, '还没有视觉模型 · 去「模型」页添加', warn: true);
    bool labeled(ImageEntry e) => ws.textOf(e).trim().isNotEmpty;
    final list = switch (target) {
      InferTarget.selected => ws.scopeEntries(Scope.selected),
      InferTarget.folderUnlabeled => [for (final e in ws.scopeEntries(Scope.folder)) if (!labeled(e)) e],
      InferTarget.all => ws.entries,
      _ => ws.scopeEntries(Scope.folder),
    };
    if (list.isEmpty) return showToast(context, '这里没有要推标的图', warn: true);
    final over = list.where(labeled).length;
    if (over > 0 &&
        !await confirmDialog(context, '覆盖 $over 张已有标注?', '共 ${list.length} 张。写盘前会打快照,可以在操作日志里整批回滚。', ok: '推标')) {
      return;
    }
    final err = await ws.startBatch(Scope.all, run, list: list, parallel: cfg.parallel);
    final j = ws.lastJob;
    if (!mounted) return;
    if (err != null) return showToast(context, err, warn: true);
    if (j != null) showToast(context, j.summary, warn: j.failed > 0);
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): () => _save(all: true),
      const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () => ws.step(1),
      const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () => ws.step(-1),
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
        if (!_typing && !ws.undo()) showToast(context, '没有可撤销的步骤', warn: true);
      },
      const SingleActivator(LogicalKeyboardKey.keyY, control: true): () {
        if (!_typing && !ws.redo()) showToast(context, '没有可重做的步骤', warn: true);
      },
    },
    child: Focus(
      autofocus: true,
      child: ListenableBuilder(
        listenable: Listenable.merge([ws, widget.config, widget.local]),
        builder: (context, _) => AnimatedSwitcher(
          duration: Motion.of(context, Motion.sheet),
          layoutBuilder: fillLayout,
          child: ws.root == null || ws.entries.isEmpty ? _welcome() : _desk(),
        ),
      ),
    ),
  );

  Widget _welcome() {
    final last = widget.config.config.lastRoot;
    final empty = ws.root != null;
    return Center(
      key: const ValueKey('welcome'),
      child: PopIn(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Wordmark(height: 64),
              const SizedBox(height: 10),
              Text(empty ? '这个文件夹里没有图片' : '图片 + 同名 txt 的标注台', style: TextStyle(color: NlColors.slate500)),
              const SizedBox(height: 24),
              NlButton(
                label: ws.loading ? '扫描中…' : '打开数据集文件夹',
                icon: Icons.folder_open_outlined,
                tone: Tone.primary,
                busy: ws.loading,
                onPressed: () => pickDataset(context, ws),
              ),
              if (last.isNotEmpty && !empty && Directory(last).existsSync()) ...[
                const SizedBox(height: 10),
                NlButton(label: last, icon: Icons.history, tone: Tone.ghost, onPressed: () => ws.open(Directory(last))),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _desk() => Stack(
    key: const ValueKey('desk'),
    children: [
      Row(
        children: [
          SizedBox(
            width: 272,
            child: DecoratedBox(
              decoration: BoxDecoration(border: Border(right: BorderSide(color: NlColors.border))),
              child: DatasetPane(ws: ws, onOpen: () => pickDataset(context, ws), onInfer: _inferAt),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final h = _editorH.clamp(170.0, (c.maxHeight - 200).clamp(170.0, 620.0));
                return Column(
                  children: [
                    Expanded(child: PreviewPane(ws: ws)),
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeRow,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (d) => setState(() => _editorH = (h - d.delta.dy)),
                        child: Container(
                          height: 8,
                          color: NlColors.stage,
                          alignment: Alignment.center,
                          child: Container(width: 44, height: 3, decoration: BoxDecoration(color: NlColors.slate400.withValues(alpha: .5), borderRadius: BorderRadius.circular(3))),
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: NlColors.border))),
                      child: SizedBox(height: h, child: CaptionEditor(ws: ws, config: widget.config)),
                    ),
                  ],
                );
              },
            ),
          ),
          SizedBox(
            width: 360,
            child: DecoratedBox(
              decoration: BoxDecoration(border: Border(left: BorderSide(color: NlColors.border))),
              child: SidePanel(ws: ws, config: widget.config, local: widget.local, onGoModels: () => widget.onGo(2), onGoLog: () => widget.onGo(1)),
            ),
          ),
        ],
      ),
      Positioned(right: 376, bottom: 16, child: JobCard(ws: ws)),
    ],
  );
}
