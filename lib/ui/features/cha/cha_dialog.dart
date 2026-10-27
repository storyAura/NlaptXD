import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/cha.dart';
import '../../../core/dataset.dart';
import '../../../data/app_config.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../local/local_store.dart';
import '../workspace/engines.dart';

export 'cha_summary.dart';

/// CHA 向导:角色卡 → 三套人物卡候选 → 确认。确认后返回锁定的人物卡,取消返回 null。
Future<List<ChaCard>?> showChaDialog(
  BuildContext context, {
  required AppConfig config,
  required LocalStore local,
  required List<ImageEntry> images,
}) => showDialog<List<ChaCard>>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ChaDialog(config: config, local: local, images: images),
);

enum _Status { idle, busy, done, error }

/// 一张角色卡的草稿。
class _Slot {
  final name = TextEditingController();
  final series = TextEditingController();
  int ref = 0;
  final extras = <({String path, TextEditingController label})>[];
  final cands = List.generate(3, (_) => TextEditingController());
  final status = List.filled(3, _Status.idle);
  final errors = List<String>.filled(3, '');
  int pick = -1;

  void dispose() {
    for (final c in [name, series, ...cands, for (final e in extras) e.label]) {
      c.dispose();
    }
  }
}

class _ChaDialog extends StatefulWidget {
  const _ChaDialog({required this.config, required this.local, required this.images});

  final AppConfig config;
  final LocalStore local;
  final List<ImageEntry> images;

  @override
  State<_ChaDialog> createState() => _ChaDialogState();
}

class _ChaDialogState extends State<_ChaDialog> {
  final _slots = [_Slot()];
  int _cur = 0;
  int _step = 1;

  _Slot get _slot => _slots[_cur];
  List<ImageEntry> get _refs => widget.images.take(40).toList();

  @override
  void dispose() {
    for (final s in _slots) {
      s.dispose();
    }
    super.dispose();
  }

  bool get _canGenerate => _slots.every((s) => s.name.text.trim().isNotEmpty);
  bool get _canConfirm => _slots.every((s) => s.pick >= 0 && s.cands[s.pick].text.trim().isNotEmpty);

  /// 三个候选并行生成;每个候选用自己的模型位(没设就用视觉模型)。
  void _generate(_Slot s, [int? only]) {
    final cfg = widget.config;
    for (final v in only == null ? [0, 1, 2] : [only]) {
      final ask = askerFor(cfg.chaCards[v] ?? cfg.vision, cfg, widget.local);
      if (ask == null) {
        s.status[v] = _Status.error;
        s.errors[v] = '模型不可用 · 去「模型」页设置';
        continue;
      }
      s.status[v] = _Status.busy;
      () async {
        try {
          final images = [
            await readImage(_refs[s.ref].imagePath),
            for (final e in s.extras) await readImage(e.path),
          ];
          final text = await ask(
            prompt: buildCardPrompt(s.name.text, s.series.text, variant: v, referenceLabels: [for (final e in s.extras) e.label.text]),
            images: images,
          );
          s.cands[v].text = text.trim();
          s.status[v] = _Status.done;
        } on Object catch (e) {
          s.status[v] = _Status.error;
          s.errors[v] = '$e';
        }
        if (mounted) setState(() {});
      }();
    }
    setState(() {});
  }

  Future<void> _addExtras() async {
    final files = await openFiles(acceptedTypeGroups: const [
      XTypeGroup(label: '图片', extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp']),
    ]);
    setState(() {
      for (final f in files) {
        _slot.extras.add((path: f.path, label: TextEditingController()));
      }
    });
  }

  void _next() {
    if (_step == 1) {
      for (final s in _slots) {
        if (s.status.every((x) => x == _Status.idle)) _generate(s);
      }
      setState(() => _step = 2);
    } else if (_step == 2) {
      setState(() => _step = 3);
    } else {
      Navigator.pop(context, [
        for (final s in _slots)
          ChaCard.fromText(s.name.text, s.series.text, s.cands[s.pick].text, [
            for (final e in s.extras) (path: e.path, label: e.label.text),
          ]),
      ]);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 980, maxHeight: 700),
      child: Column(
        children: [
          _header(),
          Divider(height: 1, color: NlColors.border),
          if (_step < 3) _slotTabs(),
          Expanded(
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.sheet),
              switchInCurve: Motion.enter,
              layoutBuilder: fillLayout,
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween(begin: const Offset(.03, 0), end: Offset.zero).animate(a), child: c),
              ),
              child: KeyedSubtree(
                key: ValueKey('$_step/$_cur'),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: switch (_step) {
                    1 => _stepRoles(),
                    2 => _stepCards(),
                    _ => _stepConfirm(),
                  },
                ),
              ),
            ),
          ),
          _footer(),
        ],
      ),
    ),
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
    child: Row(
      children: [
        const Text('CHA标注', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(width: 14),
        for (final (i, t) in ['角色卡', '人物卡', '确认'].indexed) ...[
          AnimatedContainer(
            duration: Motion.base,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: _step == i + 1 ? NlColors.primaryBg : NlColors.slate100,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_step > i + 1)
                Icon(Icons.check, size: 12, color: NlColors.accent)
              else
                Text('${i + 1}', style: TextStyle(fontSize: 11, color: _step == i + 1 ? NlColors.primary : NlColors.slate500)),
              const SizedBox(width: 4),
              Text(t, style: TextStyle(fontSize: 11.5, fontWeight: _step == i + 1 ? FontWeight.w600 : FontWeight.w400,
                  color: _step == i + 1 ? NlColors.primary : NlColors.slate500)),
            ]),
          ),
          const SizedBox(width: 6),
        ],
        const Spacer(),
        Text('将处理 ${widget.images.length} 张', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
        const SizedBox(width: 8),
        NlIconButton(Icons.close, tooltip: '关闭', onPressed: () => Navigator.pop(context)),
      ],
    ),
  );

  Widget _slotTabs() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
    child: Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (i, s) in _slots.indexed)
          NlChip(
            label: s.name.text.trim().isEmpty ? '卡 ${i + 1}' : '卡 ${i + 1} · ${s.name.text.trim()}',
            selected: i == _cur,
            onTap: () => setState(() => _cur = i),
          ),
        if (_step == 1 && _slots.length < maxCards)
          NlButton(label: '添加角色卡', icon: Icons.add, tone: Tone.ghost, onPressed: () => setState(() {
            _slots.add(_Slot());
            _cur = _slots.length - 1;
          })),
        if (_step == 1 && _slots.length > 1)
          NlButton(label: '删除此卡', icon: Icons.delete_outline, tone: Tone.danger, onPressed: () => setState(() {
            _slots.removeAt(_cur).dispose();
            _cur = (_cur - 1).clamp(0, _slots.length - 1);
          })),
      ],
    ),
  );

  Widget _stepRoles() {
    final s = _slot;
    Widget field(String label, TextEditingController c, String hint) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
        const SizedBox(height: 4),
        TextField(controller: c, style: const TextStyle(fontSize: 13), onChanged: (_) => setState(() {}), decoration: fieldDecoration(hint)),
      ],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            children: [
              field('角色名 · 必填', s.name, '如 Suzukaze Aoba'),
              const SizedBox(height: 10),
              field('作品名', s.series, '如 New Game!'),
              const SizedBox(height: 16),
              Label('多图参考', trailing: Text('背面、武器、发饰特写…', style: TextStyle(fontSize: 11, color: NlColors.slate400))),
              for (final (i, e) in s.extras.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(File(e.path), width: 36, height: 36, fit: BoxFit.cover, cacheWidth: 96),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: e.label, style: const TextStyle(fontSize: 12.5), decoration: fieldDecoration('部位名称'))),
                    NlIconButton(Icons.close, onPressed: () => setState(() => s.extras.removeAt(i).label.dispose())),
                  ]),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: NlButton(label: '添加参考图', icon: Icons.add_photo_alternate_outlined, tone: Tone.outline, onPressed: _addExtras),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Label('主参考图'),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 110, childAspectRatio: 3 / 4, mainAxisSpacing: 8, crossAxisSpacing: 8),
                  itemCount: _refs.length,
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => setState(() => s.ref = i),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: AnimatedContainer(
                        duration: Motion.base,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: s.ref == i ? NlColors.primary : Colors.transparent, width: 2),
                          boxShadow: s.ref == i ? [BoxShadow(color: NlColors.primaryBg, spreadRadius: 3)] : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(File(_refs[i].imagePath), fit: BoxFit.cover, cacheWidth: 220),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepCards() {
    final s = _slot;
    final cfg = widget.config;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var v = 0; v < 3; v++) ...[
          if (v > 0) const SizedBox(width: 12),
          Expanded(
            child: PopIn(
              delay: Duration(milliseconds: 50 * v),
              child: NlCard(
                borderColor: s.pick == v ? NlColors.primary : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Text('候选 ${v + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      Flexible(child: Pill(modelLabel(cfg.chaCards[v] ?? cfg.vision, widget.local))),
                      const Spacer(),
                      NlIconButton(Icons.refresh, tooltip: '重新生成', onPressed: s.status[v] == _Status.busy ? null : () => _generate(s, v)),
                    ]),
                    const SizedBox(height: 8),
                    Expanded(
                      child: switch (s.status[v]) {
                        _Status.busy || _Status.idle => Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: NlColors.primary)),
                            const SizedBox(height: 8),
                            Text('生成中…', style: TextStyle(fontSize: 12, color: NlColors.slate500)),
                          ]),
                        ),
                        _Status.error => Center(
                          child: Text(s.errors[v], textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: NlColors.diffDelText)),
                        ),
                        _Status.done => TextField(
                          controller: s.cands[v],
                          maxLines: null,
                          expands: true,
                          style: monoStyle.copyWith(fontSize: 12),
                          decoration: fieldDecoration('').copyWith(fillColor: NlColors.editorBg),
                          onChanged: (_) => setState(() {}),
                        ),
                      },
                    ),
                    const SizedBox(height: 8),
                    NlButton(
                      label: s.pick == v ? '已选定' : '选定这套',
                      icon: s.pick == v ? Icons.check : null,
                      tone: s.pick == v ? Tone.primary : Tone.outline,
                      onPressed: s.status[v] == _Status.done ? () => setState(() => s.pick = v) : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _stepConfirm() {
    final cfg = widget.config;
    final label = TextStyle(fontSize: 11.5, color: NlColors.slate500);
    return ListView(
      children: [
        for (final (i, s) in _slots.indexed) ...[
          Builder(builder: (_) {
            final parts = splitCard(s.cands[s.pick].text, s.name.text);
            return PopIn(
              delay: Duration(milliseconds: 40 * i),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: NlCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('卡 ${i + 1} · ${s.name.text.trim()}${s.series.text.trim().isEmpty ? '' : ' · ${s.series.text.trim()}'}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('固定外貌(每张图保留)', style: label),
                      Text(parts.appearance, style: monoStyle.copyWith(fontSize: 12)),
                      const SizedBox(height: 6),
                      Text('官方服装(按图核对,不同则改写)', style: label),
                      parts.outfit.isEmpty
                          ? Text('未识别到服装段:服装将不会按图改写', style: TextStyle(fontSize: 12, color: NlColors.lockText))
                          : Text(parts.outfit, style: monoStyle.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
        Text(
          '整批画面模型 ${modelLabel(cfg.chaScene ?? cfg.vision, widget.local)} · 写成「人物卡 + 空行 + 画面段」· '
          '不属于任何角色卡的图跳过 · 先自动备份',
          style: label,
        ),
      ],
    );
  }

  Widget _footer() {
    final ok = switch (_step) {
      1 => _canGenerate,
      2 => _canConfirm,
      _ => true,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      decoration: BoxDecoration(color: NlColors.slate50, border: Border(top: BorderSide(color: NlColors.border))),
      child: Row(
        children: [
          if (_step > 1) NlButton(label: '上一步', icon: Icons.arrow_back, tone: Tone.outline, onPressed: () => setState(() => _step--)),
          const Spacer(),
          if (!ok)
            Text(_step == 1 ? '先填写每张角色卡的角色名' : '为每张角色卡选定一套人物卡', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
          const SizedBox(width: 10),
          NlButton(
            label: switch (_step) {
              1 => '生成人物卡',
              2 => '下一步',
              _ => '开始CHA标注',
            },
            icon: _step == 3 ? Icons.play_arrow_rounded : null,
            tone: Tone.primary,
            onPressed: ok ? _next : null,
          ),
        ],
      ),
    );
  }
}
