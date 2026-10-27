import 'package:flutter/material.dart';

import '../../../core/json_caption.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'workspace.dart';

/// 框的颜色,编辑区的卡片和预览图上的框用同一个(同 Penna 的 layoutBoxColor)。
const _boxColors = [
  Color(0xFF3B82F6),
  Color(0xFF10B981),
  Color(0xFF8B5CF6),
  Color(0xFFF43F5E),
  Color(0xFF06B6D4),
  Color(0xFFF59E0B),
  Color(0xFFD946EF),
];

Color jsonBoxColor(int i) => _boxColors[i % _boxColors.length];

const _labelNames = {'character': '人物', 'text': '文字', 'object': '物体'};

/// 编辑区的「JSON」视图:整体描述一张卡,每个框一张卡(颜色和预览图上的框对应)。
class JsonEditor extends StatefulWidget {
  const JsonEditor({super.key, required this.ws});

  final Workspace ws;

  @override
  State<JsonEditor> createState() => _JsonEditorState();
}

class _JsonEditorState extends State<JsonEditor> {
  Workspace get ws => widget.ws;
  final _cards = <int, GlobalKey>{};
  int _shown = -1;

  /// 每次现读最新的标注再改:失焦交出的那一下和紧接着的点击不会互相盖掉。
  void _edit(MossLayout Function(MossLayout l) change, String label) {
    final l = readMossLayout(ws.textOf(ws.entry!));
    if (l != null) ws.setText(change(l).toJson(), label: label);
  }

  @override
  Widget build(BuildContext context) {
    final e = ws.entry!;
    final text = ws.textOf(e);
    final l = readMossLayout(text);
    if (l == null) {
      return Center(
        child: Text(
          text.trim().isEmpty ? '暂无 JSON · 在右侧用「JSON」引擎推标' : '不是 MOSS 布局 JSON · 切到「文本」查看',
          style: TextStyle(fontSize: 12, color: NlColors.slate500),
        ),
      );
    }
    // 在预览图上点了框:滚到它的卡片。
    if (ws.box != _shown) {
      _shown = ws.box;
      final key = _cards[ws.box];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = key?.currentContext;
        if (c != null && c.mounted) Scrollable.ensureVisible(c, duration: Motion.base, curve: Motion.swift, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      });
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        NlCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Field(key: ValueKey('${e.key}/caption'), label: '整体描述', value: l.caption, onCommit: (v) => _edit((l) => l.copyWith(caption: v), '改整体描述')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _Field(
                      key: ValueKey('${e.key}/meta'),
                      label: '类型',
                      value: l.meta.join(', '),
                      hint: 'illustration, poster',
                      onCommit: (v) => _edit((l) => l.copyWith(meta: [for (final m in v.split(',')) if (m.trim().isNotEmpty) m.trim()]), '改类型'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  for (final c in mossCanvases) ...[
                    NlChip(label: c, selected: l.canvas == c, onTap: () => _edit((l) => l.copyWith(canvas: c), '改画布')),
                    const SizedBox(width: 4),
                  ],
                ],
              ),
            ],
          ),
        ),
        for (final (i, it) in l.items.indexed)
          Padding(
            key: _cards.putIfAbsent(i, GlobalKey.new),
            padding: const EdgeInsets.only(top: 8),
            child: _ItemCard(
              entryKey: e.key,
              index: i,
              item: it,
              selected: ws.box == i,
              onTap: () => ws.selectBox(i),
              onChange: (change, label) => _edit((l) => l.copyWith(items: [...l.items]..[i] = change(l.items[i])), label),
              onDelete: () {
                ws.selectBox(-1);
                _edit((l) => l.copyWith(items: [...l.items]..removeAt(i)), '删除框');
              },
            ),
          ),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.entryKey,
    required this.index,
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onChange,
    required this.onDelete,
  });

  final String entryKey;
  final int index;
  final MossItem item;
  final bool selected;
  final VoidCallback onTap;
  final void Function(MossItem Function(MossItem it) change, String label) onChange;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = jsonBoxColor(index);
    final key = '$entryKey/$index';
    return GestureDetector(
      onTap: onTap,
      child: NlCard(
        borderColor: selected ? color : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                  child: Text('${index + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                for (final l in mossLabels) ...[
                  NlChip(label: _labelNames[l]!, selected: item.label == l, onTap: () => onChange((it) => it.copyWith(label: l), '改类别')),
                  const SizedBox(width: 4),
                ],
                const Spacer(),
                Text('[${item.bbox.join(', ')}]', style: TextStyle(fontSize: 11, color: NlColors.slate400)),
                const SizedBox(width: 4),
                NlIconButton(Icons.close, size: 22, onPressed: onDelete),
              ],
            ),
            if (item.label == 'text') ...[
              const SizedBox(height: 8),
              _Field(key: ValueKey('$key/text'), label: '文字内容', value: item.text, onCommit: (v) => onChange((it) => it.copyWith(text: v), '改文字')),
            ],
            const SizedBox(height: 8),
            _Field(key: ValueKey('$key/caption'), label: '这一块的描述', value: item.caption, onCommit: (v) => onChange((it) => it.copyWith(caption: v), '改框描述')),
          ],
        ),
      ),
    );
  }
}

/// 带小标题的多行输入框;失焦时内容变了才交出去(记一步历史)。
class _Field extends StatefulWidget {
  const _Field({super.key, required this.label, required this.value, required this.onCommit, this.hint = ''});

  final String label;
  final String value;
  final String hint;
  final ValueChanged<String> onCommit;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final _c = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _c.text.trim() != widget.value) widget.onCommit(_c.text.trim());
      if (mounted) setState(() {});
    });
  }

  /// 撤销、重做这类从外面改的,没在打字时跟上。
  @override
  void didUpdateWidget(_Field old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _c.text != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Label(widget.label),
      AnimatedContainer(
        duration: Motion.base,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: NlColors.editorBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _focus.hasFocus ? NlColors.primary : NlColors.border),
        ),
        child: TextField(
          controller: _c,
          focusNode: _focus,
          maxLines: null,
          style: monoStyle,
          decoration: InputDecoration.collapsed(hintText: widget.hint, hintStyle: TextStyle(color: NlColors.slate400)),
        ),
      ),
    ],
  );
}

/// 预览图上的框:按原图 [width]×[height] 把官方坐标(中心原点、yxyx)换回画面比例。
/// 前面的块画在最上面,点框选中它。
class JsonBoxOverlay extends StatelessWidget {
  const JsonBoxOverlay({super.key, required this.layout, required this.width, required this.height, required this.selected, required this.onTap});

  final MossLayout layout;
  final int width;
  final int height;
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final sx = c.maxWidth / width, sy = c.maxHeight / height;
      final w2 = width ~/ 2, h2 = height ~/ 2;
      return Stack(
        children: [
          for (final (i, it) in layout.items.indexed.toList().reversed)
            Positioned(
              left: (it.bbox[1] + w2) * sx,
              top: (it.bbox[0] + h2) * sy,
              width: (it.bbox[3] - it.bbox[1]) * sx,
              height: (it.bbox[2] - it.bbox[0]) * sy,
              child: _Box(index: i, label: _labelNames[it.label]!, selected: i == selected, onTap: () => onTap(i == selected ? -1 : i)),
            ),
        ],
      );
    },
  );
}

class _Box extends StatelessWidget {
  const _Box({required this.index, required this.label, required this.selected, required this.onTap});

  final int index;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = jsonBoxColor(index);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.base,
          alignment: Alignment.topLeft,
          decoration: BoxDecoration(
            color: color.withValues(alpha: selected ? .18 : .04),
            border: Border.all(color: color, width: selected ? 3 : 1.5),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            color: color,
            child: Text('${index + 1} $label', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ),
      ),
    );
  }
}
