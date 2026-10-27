import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/captions.dart';
import '../../../core/dataset.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'workspace.dart';

/// kohya 文件夹 `10_aoba` 的触发词 `aoba`;正则集 `1_reg` 没有。
String triggerOf(ImageEntry e) {
  final leaf = e.folder.split(Platform.pathSeparator).last;
  final parts = leaf.split('_');
  if (parts.length < 2 || int.tryParse(parts.first) == null || parts[1] == 'reg') return '';
  return parts[1];
}

/// 中栏下半:胶囊 / 分句 / 文本三种看法,改的是同一份标注。
class CaptionEditor extends StatefulWidget {
  const CaptionEditor({super.key, required this.ws});

  final Workspace ws;

  @override
  State<CaptionEditor> createState() => _CaptionEditorState();
}

class _CaptionEditorState extends State<CaptionEditor> {
  Workspace get ws => widget.ws;
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _bodyKey = GlobalKey();
  final _chipKey = GlobalKey();

  /// 选中的胶囊离编辑区顶边太近(放上面会盖住标题栏)时,工具条翻到下方。
  bool _chipNearTop() {
    final chip = _chipKey.currentContext?.findRenderObject() as RenderBox?;
    final body = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (chip == null || body == null || !chip.attached || !body.attached) return true;
    return chip.localToGlobal(Offset.zero).dy - body.localToGlobal(Offset.zero).dy < 46;
  }
  final _text = TextEditingController();
  final _textFocus = FocusNode();
  int _sel = -1;
  int _editing = -1;
  String? _key;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _portal.show());
    _textFocus.addListener(() {
      if (!_textFocus.hasFocus) ws.commitTyping('自由编辑');
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  void _select(int i) => setState(() {
    if (_sel == i) {
      _editing = i;
    } else {
      _sel = i;
      _editing = -1;
    }
  });

  void _commitChip(int i, String value) {
    final count = splitSegments(ws.textOf(ws.entry!)).length;
    setState(() => _editing = -1);
    final parts = splitSegments(value);
    if (i >= count) {
      if (parts.isNotEmpty) ws.editSegments((s) => s.addAll(parts), '添加标签');
      _sel = -1;
      return;
    }
    ws.editSegments((s) => s.replaceRange(i, i + 1, parts), parts.isEmpty ? '删除片段' : '编辑标签');
    if (parts.isEmpty) _sel = -1;
  }

  void _delete(int i) {
    ws.editSegments((s) => s.removeAt(i), '删除片段');
    setState(() => _sel = -1);
  }

  void _move(int from, int to) {
    if (from == to) return;
    ws.editSegments((s) => s.insert(to, s.removeAt(from)), '拖动排序');
    setState(() => _sel = to);
  }

  @override
  Widget build(BuildContext context) {
    final e = ws.entry!;
    final text = ws.textOf(e);
    if (_key != e.key) {
      _key = e.key;
      _sel = _editing = -1;
    }
    if (!_textFocus.hasFocus && _text.text != text) _text.text = text;
    final segs = splitSegments(text);
    if (_sel >= segs.length) _sel = -1;
    // 工具条画在最上层的 Overlay 里,不跟着页面淡出:标注台不是当前页时(TickerMode 关着)不画。
    final pageActive = TickerMode.valuesOf(context).enabled;

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (_) {
        if (!pageActive || _sel < 0 || _editing >= 0 || ws.mode != EditMode.chips) return const SizedBox.shrink();
        final below = _chipNearTop();
        return Align(
          alignment: Alignment.topLeft,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: below ? Alignment.bottomLeft : Alignment.topLeft,
            followerAnchor: below ? Alignment.topLeft : Alignment.bottomLeft,
            offset: Offset(0, below ? 6 : -6),
            child: PopIn(key: ValueKey('$_key/$_sel/$below'), child: _toolbar(segs.length)),
          ),
        );
      },
      child: Container(
        color: NlColors.card,
        child: Column(
          children: [
            _header(text, segs.length),
            Expanded(
              child: Container(
                key: _bodyKey,
                color: NlColors.editorBg,
                child: AnimatedSwitcher(
                  duration: Motion.of(context, Motion.base),
                  layoutBuilder: fillLayout,
                  child: KeyedSubtree(
                    key: ValueKey(ws.mode),
                    child: switch (ws.mode) {
                      EditMode.chips => _chips(e, segs),
                      EditMode.sentences => _sentences(segs),
                      EditMode.text => _freeText(),
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String text, int n) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: NlColors.border))),
    child: Row(
      children: [
        Seg<EditMode>(
          value: ws.mode,
          onChanged: (m) {
            setState(() => _sel = _editing = -1);
            ws.setView(mode: m);
          },
          items: const [(EditMode.chips, '胶囊', null), (EditMode.sentences, '分句', null), (EditMode.text, '文本', null)],
        ),
        const SizedBox(width: 10),
        Text('${text.length} 字符 · $n 段', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
        const Spacer(),
        NlButton(
          label: '复制',
          icon: Icons.content_copy_outlined,
          tone: Tone.ghost,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (mounted) showToast(context, '已复制标注');
          },
        ),
        NlButton(
          label: '清空',
          icon: Icons.delete_outline,
          tone: Tone.danger,
          onPressed: text.isEmpty
              ? null
              : () {
                  ws.setText('', label: '清空');
                  showToast(context, '已清空标注', action: ('撤销', ws.undo));
                },
        ),
      ],
    ),
  );

  Widget _toolbar(int count) {
    Widget b(IconData icon, String label, VoidCallback? run, {bool danger = false}) =>
        NlButton(label: label, icon: icon, tone: danger ? Tone.danger : Tone.ghost, onPressed: run);
    final i = _sel;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: NlColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NlColors.border),
        boxShadow: [BoxShadow(color: NlColors.shadow, blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          b(Icons.add, '插入', () {
            ws.editSegments((s) => s.insert(i + 1, 'new tag'), '插入片段');
            setState(() => _sel = _editing = i + 1);
          }),
          b(Icons.edit_outlined, '编辑', () => setState(() => _editing = i)),
          b(Icons.west, '', i > 0 ? () => _move(i, i - 1) : null),
          b(Icons.east, '', i < count - 1 ? () => _move(i, i + 1) : null),
          b(Icons.delete_outline, '删除', () => _delete(i), danger: true),
        ],
      ),
    );
  }

  Widget _chips(ImageEntry e, List<String> segs) {
    final trigger = triggerOf(e);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      child: AnimatedSize(
        duration: Motion.base,
        curve: Motion.expand,
        alignment: Alignment.topLeft,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (i, s) in segs.indexed)
              if (i == _editing)
                _ChipInput(initial: s, onDone: (v) => _commitChip(i, v), onCancel: () => setState(() => _editing = -1))
              else
                _Tag(
                  key: ValueKey('$i:$s'),
                  text: s,
                  index: i,
                  selected: i == _sel,
                  lock: i == 0 && s == trigger,
                  link: i == _sel ? _link : null,
                  anchorKey: i == _sel ? _chipKey : null,
                  onTap: () => _select(i),
                  onDelete: () => _delete(i),
                  // 往右拖落在目标之后,往左拖落在目标之前:两种都是插到 i
                  onDrop: (from) => _move(from, i),
                ),
            if (_editing == segs.length)
              PopIn(child: _ChipInput(initial: '', onDone: (v) => _commitChip(segs.length, v), onCancel: () => setState(() => _editing = -1)))
            else
              _AddChip(onTap: () => setState(() {
                _sel = -1;
                _editing = segs.length;
              })),
            if (segs.isEmpty && _editing < 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('暂无内容 · 点「+ 标签」添加,或在右侧推标', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sentences(List<String> segs) => Column(
    children: [
      Expanded(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          buildDefaultDragHandles: false,
          itemCount: segs.length,
          onReorderItem: _move,
          proxyDecorator: (child, _, a) => Material(
            color: Colors.transparent,
            child: ScaleTransition(scale: Tween(begin: 1.0, end: 1.02).animate(a), child: child),
          ),
          itemBuilder: (_, i) => _SentenceRow(
            key: ValueKey('${segs[i]}#$i'),
            index: i,
            text: segs[i],
            onCommit: (v) => _commitChip(i, v),
            onDelete: () => _delete(i),
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: NlButton(
            label: '添加分段',
            icon: Icons.add,
            tone: Tone.ghost,
            onPressed: () => ws.editSegments((s) => s.add('new segment'), '添加分段'),
          ),
        ),
      ),
    ],
  );

  Widget _freeText() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    child: TextField(
      controller: _text,
      focusNode: _textFocus,
      expands: true,
      maxLines: null,
      style: monoStyle.copyWith(height: 1.7),
      decoration: InputDecoration.collapsed(hintText: '在此输入标注文本…', hintStyle: TextStyle(color: NlColors.slate400)),
      onChanged: ws.setText,
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag({
    super.key,
    required this.text,
    required this.index,
    required this.selected,
    required this.lock,
    required this.link,
    required this.anchorKey,
    required this.onTap,
    required this.onDelete,
    required this.onDrop,
  });

  final String text;
  final int index;
  final bool selected;
  final bool lock;
  final LayerLink? link;

  /// 选中时挂上,用来量胶囊离编辑区顶边多远。
  final GlobalKey? anchorKey;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<int> onDrop;

  Widget _face(bool hover, {bool dropping = false}) {
    final sentence = isSentence(text);
    final (bg, border, fg) = lock
        ? (NlColors.lock, NlColors.lockBorder, NlColors.lockText)
        : selected
        ? (NlColors.primaryBg, NlColors.primary, NlColors.primary)
        : sentence
        ? (NlColors.slate50, NlColors.primaryBorder, NlColors.slate700)
        : (NlColors.card, hover ? NlColors.primaryBorder : NlColors.border, NlColors.slate700);
    return AnimatedContainer(
      duration: Motion.base,
      curve: Motion.swift,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: dropping ? NlColors.primaryBg : bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: dropping ? NlColors.primary : border, width: dropping ? 1.5 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (lock) ...[Icon(Icons.lock_outline, size: 12, color: fg), const SizedBox(width: 4)],
          if (sentence) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(color: NlColors.primaryBg, borderRadius: BorderRadius.circular(4)),
              child: Text('句', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: NlColors.primary)),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(child: Text(text, style: monoStyle.copyWith(color: fg, height: 1.4))),
          AnimatedSize(
            duration: Motion.snap,
            child: hover || selected
                ? GestureDetector(
                    onTap: onDelete,
                    child: Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.close, size: 13, color: fg.withValues(alpha: .7))),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget chip = Hover(
      cursor: SystemMouseCursors.click,
      builder: (hover) => DragTarget<int>(
        onWillAcceptWithDetails: (d) => d.data != index,
        onAcceptWithDetails: (d) => onDrop(d.data),
        builder: (_, candidates, _) => Draggable<int>(
          data: index,
          feedback: Material(color: Colors.transparent, child: Opacity(opacity: .85, child: _face(false))),
          childWhenDragging: Opacity(opacity: .4, child: _face(false)),
          child: Bouncy(child: GestureDetector(onTap: onTap, child: _face(hover, dropping: candidates.isNotEmpty))),
        ),
      ),
    );
    if (link != null) chip = KeyedSubtree(key: anchorKey, child: CompositedTransformTarget(link: link!, child: chip));
    return isSentence(text) ? SizedBox(width: double.infinity, child: Align(alignment: Alignment.centerLeft, child: chip)) : chip;
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Hover(
    cursor: SystemMouseCursors.click,
    builder: (hover) => Bouncy(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.base,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: hover ? NlColors.primary : NlColors.slate400, width: 1, strokeAlign: BorderSide.strokeAlignInside),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 13, color: hover ? NlColors.primary : NlColors.slate500),
              Text('标签', style: TextStyle(fontSize: 12.5, color: hover ? NlColors.primary : NlColors.slate500)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 胶囊里的行内输入:回车或失焦提交,Esc 放弃。输入逗号会拆成几枚。
class _ChipInput extends StatefulWidget {
  const _ChipInput({required this.initial, required this.onDone, required this.onCancel});

  final String initial;
  final ValueChanged<String> onDone;
  final VoidCallback onCancel;

  @override
  State<_ChipInput> createState() => _ChipInputState();
}

class _ChipInputState extends State<_ChipInput> {
  late final _c = TextEditingController(text: widget.initial)..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);
  final _focus = FocusNode();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _finish();
    });
  }

  void _finish({bool cancel = false}) {
    if (_done) return;
    _done = true;
    cancel ? widget.onCancel() : widget.onDone(_c.text);
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => _finish(cancel: true)},
    child: IntrinsicWidth(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 90),
        child: TextField(
          controller: _c,
          focusNode: _focus,
          autofocus: true,
          style: monoStyle.copyWith(height: 1.4),
          onSubmitted: (_) => _finish(),
          decoration: fieldDecoration('').copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7)),
        ),
      ),
    ),
  );
}

class _SentenceRow extends StatefulWidget {
  const _SentenceRow({super.key, required this.index, required this.text, required this.onCommit, required this.onDelete});

  final int index;
  final String text;
  final ValueChanged<String> onCommit;
  final VoidCallback onDelete;

  @override
  State<_SentenceRow> createState() => _SentenceRowState();
}

class _SentenceRowState extends State<_SentenceRow> {
  late final _c = TextEditingController(text: widget.text);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _c.text.trim() != widget.text) widget.onCommit(_c.text);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Hover(
    builder: (hover) => AnimatedContainer(
      duration: Motion.base,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _focus.hasFocus ? NlColors.card : hover ? NlColors.slate50 : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _focus.hasFocus ? NlColors.primary : hover ? NlColors.border : Colors.transparent),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReorderableDragStartListener(
            index: widget.index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Padding(padding: const EdgeInsets.only(top: 3), child: Icon(Icons.drag_indicator, size: 16, color: NlColors.slate400)),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            margin: const EdgeInsets.only(top: 3),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: NlColors.primaryBg, borderRadius: BorderRadius.circular(5)),
            child: Text('${widget.index + 1}'.padLeft(2, '0'), style: TextStyle(fontSize: 11, color: NlColors.primary)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _c,
              focusNode: _focus,
              maxLines: null,
              style: monoStyle,
              onSubmitted: (_) => _focus.unfocus(),
              decoration: const InputDecoration.collapsed(hintText: ''),
            ),
          ),
          AnimatedOpacity(
            duration: Motion.snap,
            opacity: hover ? 1 : 0,
            child: NlIconButton(Icons.close, size: 22, onPressed: widget.onDelete),
          ),
        ],
      ),
    ),
  );
}
