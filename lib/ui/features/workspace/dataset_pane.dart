import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/captions.dart';
import '../../../core/dataset.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'workspace.dart';

String folderLabel(String folder) => folder.isEmpty ? '根目录' : folder;

/// 左栏:数据集名、搜索、筛选、按文件夹分组的图片列表。
class DatasetPane extends StatelessWidget {
  const DatasetPane({super.key, required this.ws, required this.onOpen, required this.onInfer});

  final Workspace ws;
  final VoidCallback onOpen;

  /// 右键推标:点的是第 [index] 张,推哪些看 [target]。
  final void Function(int index, InferTarget target) onInfer;

  @override
  Widget build(BuildContext context) {
    final root = ws.root!;
    final name = root.path.split(Platform.pathSeparator).where((s) => s.isNotEmpty).last;
    return Container(
      color: NlColors.sidebar,
      child: Column(
        children: [
          NlBar(
            padding: 12,
            children: [
              Icon(Icons.folder_open_outlined, size: 18, color: NlColors.slate700),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Tooltip(
                        message: root.path,
                        child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('${ws.entries.length} 张', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
                  ],
                ),
              ),
              NlIconButton(Icons.refresh, tooltip: '重新扫描', onPressed: ws.refresh),
              NlIconButton(Icons.create_new_folder_outlined, tooltip: '打开文件夹', onPressed: onOpen),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Column(
              children: [
                _Search(ws: ws),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // 计数位数多时整条缩小一点,不撑破 272 宽的栏
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Seg<ListFilter>(
                          value: ws.filter,
                          onChanged: (f) => ws.setView(filter: f),
                          items: [
                            (ListFilter.all, '全部 ${ws.entries.length}', null),
                            (ListFilter.unlabeled, '未标注 ${ws.unlabeledCount}', null),
                            (ListFilter.unsaved, '未保存 ${ws.dirtyCount}', null),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Seg<bool>(
                      value: ws.grid,
                      onChanged: (g) => ws.setView(grid: g),
                      items: const [(false, '', Icons.view_list_outlined), (true, '', Icons.grid_view_outlined)],
                    ),
                  ],
                ),
              ],
            ),
          ),
          _SelectRow(ws: ws),
          Expanded(child: _List(ws: ws, onInfer: onInfer)),
          _Footer(ws: ws),
        ],
      ),
    );
  }
}

class _Search extends StatefulWidget {
  const _Search({required this.ws});

  final Workspace ws;

  @override
  State<_Search> createState() => _SearchState();
}

class _SearchState extends State<_Search> {
  late final _c = TextEditingController(text: widget.ws.query);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 34,
    child: TextField(
      controller: _c,
      style: const TextStyle(fontSize: 12.5),
      onChanged: (q) => widget.ws.setView(query: q),
      decoration: fieldDecoration('搜索文件名 / 标签', icon: Icons.search).copyWith(
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: NlColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: NlColors.primary, width: 1.5)),
      ),
    ),
  );
}

class _SelectRow extends StatelessWidget {
  const _SelectRow({required this.ws});

  final Workspace ws;

  @override
  Widget build(BuildContext context) {
    final n = ws.selected.length;
    final style = TextStyle(fontSize: 11.5, color: NlColors.slate500);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
      child: Row(
        children: [
          NlCheck(value: n > 0 && n == ws.entries.length, partial: n > 0 && n < ws.entries.length, onTap: ws.selectAll),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: Motion.snap,
            child: Text(n == 0 ? '全选 · Shift 范围选' : '已选 $n', key: ValueKey(n == 0), style: style),
          ),
          const Spacer(),
          if (n > 0)
            GestureDetector(
              onTap: ws.clearSelection,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text('清除', style: style.copyWith(color: NlColors.primary)),
              ),
            ),
        ],
      ),
    );
  }
}

/// 一行要么是文件夹标题,要么是一张图(列表)/ 三张图(网格)。
typedef _Row = ({String? folder, List<int> items});

class _List extends StatelessWidget {
  const _List({required this.ws, required this.onInfer});

  final Workspace ws;
  final void Function(int index, InferTarget target) onInfer;

  List<_Row> _rows() {
    final vis = ws.visible;
    final rows = <_Row>[];
    for (final folder in ws.folders) {
      final items = [for (final i in vis) if (ws.entries[i].folder == folder) i];
      if (items.isEmpty) continue;
      rows.add((folder: folder, items: items));
      if (ws.collapsed.contains(folder)) continue;
      final per = ws.grid ? 3 : 1;
      for (var k = 0; k < items.length; k += per) {
        rows.add((folder: null, items: items.sublist(k, (k + per).clamp(0, items.length))));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    if (rows.isEmpty) {
      return Center(child: Text('没有匹配的文件', style: TextStyle(fontSize: 12, color: NlColors.slate500)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      itemCount: rows.length,
      itemBuilder: (context, r) {
        final row = rows[r];
        if (row.folder != null) return _FolderHeader(ws: ws, folder: row.folder!, shown: row.items.length);
        if (!ws.grid) return _Item(ws: ws, index: row.items.single, onInfer: onInfer);
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              for (var k = 0; k < 3; k++) ...[
                if (k > 0) const SizedBox(width: 6),
                Expanded(child: k < row.items.length ? _Tile(ws: ws, index: row.items[k], onInfer: onInfer) : const SizedBox()),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _FolderHeader extends StatelessWidget {
  const _FolderHeader({required this.ws, required this.folder, required this.shown});

  final Workspace ws;
  final String folder;
  final int shown;

  @override
  Widget build(BuildContext context) {
    final all = [for (var i = 0; i < ws.entries.length; i++) if (ws.entries[i].folder == folder) i];
    final nSel = all.where(ws.selected.contains).length;
    final closed = ws.collapsed.contains(folder);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
      child: Row(
        children: [
          NlCheck(value: nSel == all.length, partial: nSel > 0 && nSel < all.length, onTap: () => ws.toggleFolder(folder)),
          const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: () => ws.toggleCollapsed(folder),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: closed ? -0.25 : 0,
                      duration: Motion.base,
                      curve: Motion.expand,
                      child: Icon(Icons.expand_more, size: 16, color: NlColors.slate500),
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(folderLabel(folder), overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NlColors.slate500)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Text(shown == all.length ? '${all.length} 张' : '$shown/${all.length} 张',
              style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
        ],
      ),
    );
  }
}

void _pick(Workspace ws, int i) {
  final keys = HardwareKeyboard.instance;
  ws.select(i, range: keys.isShiftPressed, remove: keys.isAltPressed);
}

/// 右键推标的范围(同旧版 file_panel_infer.py)。
enum InferTarget { one, selected, folder, folderUnlabeled, all }

Future<void> _menu(BuildContext context, Offset at, Workspace ws, int i, void Function(int, InferTarget) onInfer) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final p = overlay.globalToLocal(at);
  final n = ws.selected.length;
  // 推标进行中只能取消,不能再开一批。
  final items = ws.job != null
      ? [('cancel', Icons.stop_circle_outlined, '取消推标')]
      : [
          ('one', Icons.auto_awesome_outlined, '推标这张图片'),
          if (n > 1 && ws.selected.contains(i)) ('selected', Icons.checklist, '推标已选的 $n 张'),
          ('folder', Icons.folder_outlined, '推标此文件夹'),
          ('folderUnlabeled', Icons.folder_open_outlined, '推标此文件夹里未标注的'),
          ('all', Icons.select_all, '推标全部'),
        ];
  final picked = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(p.dx, p.dy, p.dx, p.dy),
    items: [
      for (final (v, icon, label) in [...items, ('copy', Icons.content_copy_outlined, '复制标注')]) ...[
        if (v == 'copy') const PopupMenuDivider(height: 9),
        PopupMenuItem(
          value: v,
          height: 34,
          child: Row(children: [Icon(icon, size: 15, color: NlColors.slate500), const SizedBox(width: 10), Text(label, style: const TextStyle(fontSize: 13))]),
        ),
      ],
    ],
  );
  if (!context.mounted || picked == null) return;
  if (picked == 'cancel') return ws.cancelJob();
  if (InferTarget.values.asNameMap()[picked] case final target?) return onInfer(i, target);
  if (picked == 'copy') {
    await Clipboard.setData(ClipboardData(text: ws.textOf(ws.entries[i])));
    if (context.mounted) showToast(context, '已复制标注');
  }
}

Widget _thumb(ImageEntry e, double w, double h, double radius) => ClipRRect(
  borderRadius: BorderRadius.circular(radius),
  child: Image.file(
    File(e.imagePath),
    width: w,
    height: h,
    fit: BoxFit.cover,
    cacheWidth: 160,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => Container(width: w, height: h, color: NlColors.slate100, child: Icon(Icons.broken_image_outlined, size: 16, color: NlColors.slate400)),
  ),
);

class _Item extends StatelessWidget {
  const _Item({required this.ws, required this.index, required this.onInfer});

  final Workspace ws;
  final int index;
  final void Function(int index, InferTarget target) onInfer;

  @override
  Widget build(BuildContext context) {
    final e = ws.entries[index];
    final cur = index == ws.current;
    final sel = ws.selected.contains(index);
    final text = ws.textOf(e);
    return Hover(
      cursor: SystemMouseCursors.click,
      builder: (hover) => GestureDetector(
        onTap: () => _pick(ws, index),
        onSecondaryTapDown: (d) => _menu(context, d.globalPosition, ws, index, onInfer),
        child: AnimatedContainer(
          duration: Motion.base,
          curve: Motion.swift,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: sel ? NlColors.primaryBg : cur || hover ? NlColors.card : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cur ? NlColors.primaryBorder : Colors.transparent),
            boxShadow: cur ? [BoxShadow(color: NlColors.primaryBg, spreadRadius: 3)] : null,
          ),
          child: Row(
            children: [
              AnimatedOpacity(
                duration: Motion.snap,
                opacity: hover || sel || ws.selected.isNotEmpty ? 1 : 0,
                child: NlCheck(value: sel, onTap: () => ws.toggleSelected(index)),
              ),
              const SizedBox(width: 8),
              _thumb(e, 34, 44, 6),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    Text(text.isEmpty ? '—' : splitSegments(text).take(5).join(', '),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: NlColors.slate500)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (ws.isDirty(e))
                const UnsavedDot()
              else if (text.trim().isEmpty)
                const Pill('未标注')
              else
                Text('${splitSegments(text).length}段', style: TextStyle(fontSize: 11, color: NlColors.slate500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.ws, required this.index, required this.onInfer});

  final Workspace ws;
  final int index;
  final void Function(int index, InferTarget target) onInfer;

  @override
  Widget build(BuildContext context) {
    final e = ws.entries[index];
    final cur = index == ws.current;
    final sel = ws.selected.contains(index);
    return Hover(
      cursor: SystemMouseCursors.click,
      builder: (hover) => GestureDetector(
        onTap: () => _pick(ws, index),
        onSecondaryTapDown: (d) => _menu(context, d.globalPosition, ws, index, onInfer),
        child: AnimatedScale(
          scale: hover ? 1.03 : 1,
          duration: Motion.base,
          curve: Motion.swift,
          child: AnimatedContainer(
            duration: Motion.base,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: cur ? NlColors.primary : sel ? NlColors.primaryBorder : Colors.transparent, width: 2),
            ),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  LayoutBuilder(builder: (_, c) => _thumb(e, c.maxWidth, c.maxHeight, 7)),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(5, 12, 5, 3),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withValues(alpha: .65)]),
                      ),
                      child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.white)),
                    ),
                  ),
                  if (ws.isDirty(e)) const Positioned(top: 6, right: 6, child: UnsavedDot()),
                  if (hover || sel) Positioned(top: 5, left: 5, child: NlCheck(value: sel, onTap: () => ws.toggleSelected(index))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.ws});

  final Workspace ws;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(border: Border(top: BorderSide(color: NlColors.border))),
    child: Row(
      children: [
        Text('${ws.entries.length} 张 · 已选 ${ws.selected.length}', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
        const Spacer(),
        AnimatedSwitcher(
          duration: Motion.base,
          child: ws.dirtyCount > 0
              ? NlButton(
                  key: const ValueKey('save-all'),
                  label: '全部保存',
                  icon: Icons.save_outlined,
                  tone: Tone.ghost,
                  onPressed: () async {
                    final n = await ws.saveAll();
                    if (context.mounted) showToast(context, '已保存 $n 个文件');
                  },
                )
              : Row(
                  key: const ValueKey('saved'),
                  children: [
                    Icon(Icons.check_circle_outline, size: 13, color: NlColors.accent),
                    const SizedBox(width: 4),
                    Text('已全部保存', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
                  ],
                ),
        ),
      ],
    ),
  );
}
