import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/cha.dart';
import '../../../core/cha_store.dart';
import '../../../core/local/character_index.dart';
import '../../../core/dataset.dart';
import '../../../core/llm/api_profile.dart';
import '../../../data/app_config.dart';
import '../../core/select.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../local/local_store.dart';
import '../workspace/engines.dart';
import '../workspace/gloss_pane.dart';
import 'cha_drafts_dialog.dart';
import 'cha_preflight.dart';

export 'cha_summary.dart';

/// CHA 向导返回的:锁定的人物卡和整批画面用的模型。
typedef ChaPlan = ({List<ChaCard> roster, ModelRef? scene});

/// CHA 向导:角色卡 → 三套人物卡候选 → 确认(在这里定整批画面用哪个模型)。取消返回 null。
/// 给了 [root](数据集)和 [data](它的数据目录)时,确认的角色卡存进 [data],下次打开可以直接复用。
/// [reuse]:打开就套上上次确认的角色卡、停在确认页(重跑上一批没标上的图用)。
Future<ChaPlan?> showChaDialog(
  BuildContext context, {
  required AppConfig config,
  required LocalStore local,
  required List<ImageEntry> images,
  Directory? root,
  Directory? data,
  bool reuse = false,
}) => showDialog<ChaPlan>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ChaDialog(config: config, local: local, images: images, root: root, data: data, reuse: reuse),
);

enum _Status { idle, queued, busy, done, error }

/// 一张角色卡的草稿。
class _Slot {
  final name = TextEditingController();
  final series = TextEditingController();

  /// 主参考图的路径;空 = 网格里的第一张。
  String ref = '';

  /// 部件参考(背面、武器、发饰特写……):路径空 = 还没选图。
  final extras = <({String path, TextEditingController label})>[];
  final cands = List.generate(3, (_) => TextEditingController());
  final status = List.filled(3, _Status.idle);
  final errors = List<String>.filled(3, '');
  int pick = -1;

  /// 「识别角色」的结果;null = 还没识别过。
  List<CharacterCandidate>? found;

  /// 绑定的子文件夹;null = 不绑定(什么都不强制,和别的卡一起认人)。
  String? folder;
  bool solo = true;
  bool bindRefs = true;
  bool bindText = true;

  ChaBinding? get bind => folder == null ? null : (folder: folder!, solo: solo, refs: bindRefs, text: bindText);

  void dispose() {
    for (final c in [name, series, ...cands, for (final e in extras) e.label]) {
      c.dispose();
    }
  }
}

class _ChaDialog extends StatefulWidget {
  const _ChaDialog({required this.config, required this.local, required this.images, this.root, this.data, this.reuse = false});

  final AppConfig config;
  final LocalStore local;
  final List<ImageEntry> images;
  final Directory? root;
  final Directory? data;
  final bool reuse;

  @override
  State<_ChaDialog> createState() => _ChaDialogState();
}

class _ChaDialogState extends State<_ChaDialog> {
  final _slots = [_Slot()];
  int _cur = 0;
  int _step = 1;

  _Slot get _slot => _slots[_cur];

  /// 右边网格里能点的图:推标范围里的全部,按子文件夹分开看;复用上次的卡时,数据集外的图按它所在的文件夹补进来。
  late final List<({String path, String folder})> _grid = [for (final e in widget.images) (path: e.imagePath, folder: e.folder)];

  /// 网格当前看的子文件夹('' = 数据集根目录)。
  late String _folder = _grid.firstOrNull?.folder ?? '';

  List<String> get _folders => {for (final e in _grid) e.folder}.toList();

  String _folderOf(String path) => _grid.where((e) => e.path == path).firstOrNull?.folder ?? _folder;

  String _refOf(_Slot s) => s.ref.isNotEmpty ? s.ref : _grid.firstOrNull?.path ?? '';

  /// 正在为当前卡的第几个部件选图(点右边网格就填进去);null = 网格选的是主参考图。
  int? _picking;

  /// 这个数据集上次确认的角色卡(可以复用);null = 没有或已经关掉提示。
  ({DateTime time, List<SavedCard> cards})? _saved;

  bool _identifying = false;

  /// 整批画面用的模型:默认是设置里的(没设就是视觉模型),确认页可以换。
  late ModelRef? _scene = widget.config.chaScene ?? widget.config.vision;

  /// 这个数据集的草稿记录(旧的在前);这次编辑的是 [_draftId] 那份。
  List<ChaDraft> _drafts = const [];
  String _draftId = DateTime.now().toIso8601String();

  /// 上次没做完的草稿(突然关机、关了窗口);null = 没有或已经关掉提示。
  ChaDraft? _unfinished;

  Timer? _draftTimer;
  Future<void> _draftWrite = Future.value();

  /// 同时生成的人物卡候选不超过设置里的并发数,其余排队。
  final _queue = <(_Slot, int)>[];
  int _running = 0;

  @override
  void initState() {
    super.initState();
    final (root, data) = (widget.root, widget.data);
    if (root != null && data != null) {
      loadChaCards(data, root).then((saved) {
        if (!mounted) return;
        setState(() => _saved = saved);
        if (widget.reuse && saved != null) _reuse();
      });
      loadChaDrafts(data, root).then((drafts) {
        if (!mounted) return;
        _drafts = drafts;
        final last = drafts.lastOrNull;
        if (last != null && !last.done) setState(() => _unfinished = last);
      });
    }
  }

  /// 每次改动后过 0.8 秒存一次草稿。
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    final (root, data) = (widget.root, widget.data);
    if (root == null || data == null) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 800), _writeDraft);
  }

  /// 存草稿(一张卡都没填名字时不存)。写盘一个接一个,失败只记日志。
  void _writeDraft({bool done = false}) {
    _draftTimer?.cancel();
    final (root, data) = (widget.root, widget.data);
    if (root == null || data == null || _slots.every((s) => s.name.text.trim().isEmpty)) return;
    final draft = (
      id: _draftId,
      time: DateTime.now(),
      done: done,
      step: _step,
      cards: [
        for (final s in _slots)
          (
            name: s.name.text,
            series: s.series.text,
            ref: s.ref,
            references: [for (final e in s.extras) if (e.path.isNotEmpty) (path: e.path, label: e.label.text)],
            cands: [for (final c in s.cands) c.text],
            pick: s.pick,
            bind: s.bind,
          ),
      ],
    );
    _drafts = withDraft(_drafts, draft);
    final kept = _drafts;
    _draftWrite = _draftWrite
        .then((_) => saveChaDrafts(data, root, kept))
        .catchError((Object e) => debugPrint('cha_drafts.json 写入失败:$e'));
  }

  /// 把一份草稿填回向导。没写完的候选标成出错(点 ↻ 重新生成)。
  void _load(List<DraftCard> cards, int step) {
    for (final s in _slots) {
      s.dispose();
    }
    _queue.clear();
    _slots
      ..clear()
      ..addAll([
        for (final c in cards)
          () {
            final s = _Slot()
              ..name.text = c.name
              ..series.text = c.series
              ..ref = c.ref
              ..extras.addAll([for (final r in c.references) (path: r.path, label: TextEditingController(text: r.label))])
              ..pick = c.pick
              ..folder = c.bind?.folder
              ..solo = c.bind?.solo ?? true
              ..bindRefs = c.bind?.refs ?? true
              ..bindText = c.bind?.text ?? true;
            for (final (v, t) in c.cands.indexed) {
              s.cands[v].text = t;
              s.status[v] = t.trim().isNotEmpty ? _Status.done : step > 1 ? _Status.error : _Status.idle;
              s.errors[v] = '上次没生成完 · 点 ↻ 重新生成';
            }
            if (s.pick >= 0 && s.status[s.pick] != _Status.done) s.pick = -1;
            return s;
          }(),
      ]);
    if (_slots.isEmpty) _slots.add(_Slot());
    for (final p in {for (final c in cards) ...[c.ref, for (final r in c.references) r.path]}) {
      if (p.isNotEmpty && !_grid.any((e) => e.path == p)) _grid.insert(0, (path: p, folder: File(p).parent.path));
    }
    _folder = _folderOf(_refOf(_slots.first));
    _cur = 0;
    _picking = null;
    _saved = null;
    _unfinished = null;
    _step = step;
  }

  /// 复用上次确认的角色卡:填回角色名、作品名、参考图、部件、绑定和锁定的人物卡,直接到确认页。
  void _reuse() => setState(() => _load([
    for (final c in _saved!.cards)
      (name: c.name, series: c.series, ref: c.ref, references: c.references, cands: [c.text, '', ''], pick: 0, bind: c.bind),
  ], 3));

  /// 接着改上次没做完的草稿:还写进同一份。
  void _resume(ChaDraft d) => setState(() {
    _draftId = d.id;
    _load(d.cards, d.step);
  });

  /// 从草稿记录里打开一份:没做完的接着写进它,做完的另存一份新的(旧记录不动)。
  Future<void> _openDrafts() async {
    final d = await showChaDrafts(context, _drafts);
    if (d == null || !mounted) return;
    if (d.done) {
      setState(() {
        _draftId = DateTime.now().toIso8601String();
        _load(d.cards, 1);
      });
    } else {
      _resume(d);
    }
  }

  /// 确认时存档(失败只记日志:CHA 照常进行)。
  void _save() {
    final (root, data) = (widget.root, widget.data);
    if (root == null || data == null) return;
    saveChaCards(data, root, [
      for (final s in _slots)
        (
          name: s.name.text.trim(),
          series: s.series.text.trim(),
          text: s.cands[s.pick].text.trim(),
          ref: _refOf(s),
          references: [for (final e in s.extras) if (e.path.isNotEmpty) (path: e.path, label: e.label.text.trim())],
          bind: s.bind,
        ),
    ]).catchError((Object e) => debugPrint('cha_cards.json 写入失败:$e'));
  }

  @override
  void dispose() {
    // 关窗时还没存的改动马上存(卡还没释放)。
    if (_draftTimer?.isActive ?? false) _writeDraft();
    _queue.clear();
    for (final s in _slots) {
      s.dispose();
    }
    // CL Tagger 占 2 GB 内存,弹窗关了就放掉。
    widget.local.releaseTagger();
    super.dispose();
  }

  /// 用这张卡的主参考图识别角色(CL Tagger),结果连同父 / 子 / 同级标签列在角色名下面。
  Future<void> _identify(_Slot s) async {
    setState(() => _identifying = true);
    try {
      s.found = await widget.local.identify(_refOf(s));
    } on Object catch (e) {
      if (mounted) showToast(context, '识别失败:$e', warn: true);
    }
    if (mounted) setState(() => _identifying = false);
  }

  void _fill(_Slot s, CharacterCandidate c) => setState(() {
    s.name.text = c.name;
    if (c.series.isNotEmpty) s.series.text = c.series;
  });

  Widget _identifyBox(_Slot s) {
    final ready = widget.local.taggerReady;
    final found = s.found;
    final caption = TextStyle(fontSize: 11, color: NlColors.slate400);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NlButton(
          label: _identifying ? '识别中…' : '识别角色',
          icon: Icons.face_retouching_natural_outlined,
          tone: Tone.outline,
          busy: _identifying,
          onPressed: ready && !_identifying ? () => _identify(s) : null,
        ),
        if (!ready) Padding(padding: const EdgeInsets.only(top: 4), child: Text('在「本地模型」页下载 CL Tagger 后可用', style: caption)),
        if (found != null && found.isEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('未识别出已知角色', style: caption)),
        if (found != null && found.isNotEmpty)
          PopIn(
            key: ValueKey(found),
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(border: Border.all(color: NlColors.border), borderRadius: BorderRadius.circular(8)),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(4),
                children: [for (final c in found) _candidate(s, c)],
              ),
            ),
          ),
      ],
    );
  }

  Widget _candidate(_Slot s, CharacterCandidate c) {
    final on = s.name.text == c.name;
    final detail = [
      c.relation == CharacterRelation.detected ? '${(c.prob * 100).round()}%' : c.relation.label,
      if (c.series.isNotEmpty) c.series,
    ].join(' · ');
    return Hover(
      cursor: SystemMouseCursors.click,
      builder: (hover) => GestureDetector(
        onTap: () => _fill(s, c),
        child: AnimatedContainer(
          duration: Motion.snap,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: on ? NlColors.primaryBg : hover ? NlColors.slate100 : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.name, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: on ? NlColors.primary : NlColors.text)),
              Text(detail, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: NlColors.slate500)),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canGenerate => _slots.every((s) => s.name.text.trim().isNotEmpty);
  bool get _canConfirm => _slots.every((s) => s.pick >= 0 && s.cands[s.pick].text.trim().isNotEmpty);

  /// 三个候选排进队列;每个候选用自己的模型位(没设就用视觉模型)。
  void _generate(_Slot s, [int? only]) {
    for (final v in only == null ? [0, 1, 2] : [only]) {
      if (s.status[v] == _Status.queued || s.status[v] == _Status.busy) continue;
      s.status[v] = _Status.queued;
      _queue.add((s, v));
    }
    setState(_pump);
  }

  /// 空出位置就从队头取下一个(一次最多 [AppConfig.parallel] 个,免得一下发几十个请求被接口断开)。
  void _pump() {
    while (_running < widget.config.parallel && _queue.isNotEmpty) {
      final (s, v) = _queue.removeAt(0);
      _running++;
      _runCandidate(s, v).whenComplete(() {
        _running--;
        if (mounted) setState(_pump);
      });
    }
  }

  Future<void> _runCandidate(_Slot s, int v) async {
    final cfg = widget.config;
    final ask = askerFor(cfg.chaCards[v] ?? cfg.vision, cfg, widget.local);
    if (ask == null) {
      s.status[v] = _Status.error;
      s.errors[v] = '模型不可用 · 去「模型」页设置';
      return;
    }
    s.status[v] = _Status.busy;
    if (mounted) setState(() {});
    try {
      final parts = [for (final e in s.extras) if (e.path.isNotEmpty) e];
      final images = [
        await readImage(_refOf(s)),
        for (final e in parts) await readImage(e.path),
      ];
      final text = await ask(
        prompt: buildCardPrompt(s.name.text, s.series.text, variant: v, referenceLabels: [for (final e in parts) e.label.text]),
        images: images,
      );
      // 窗口关了或这张卡删了:卡已经释放,不再写。
      if (!mounted || !_slots.contains(s)) return;
      s.cands[v].text = text.trim();
      s.status[v] = _Status.done;
    } on Object catch (e) {
      if (!mounted || !_slots.contains(s)) return;
      s.status[v] = _Status.error;
      s.errors[v] = '$e';
    }
  }

  /// 「添加部件」:加一行,接着在右边网格点一张图给它。
  void _addPart() => setState(() {
    _slot.extras.add((path: '', label: TextEditingController()));
    _picking = _slot.extras.length - 1;
  });

  void _setPart(int i, String path) => setState(() {
    final s = _slot;
    s.extras[i] = (path: path, label: s.extras[i].label);
    _picking = null;
  });

  /// 不在数据集里的图(官方设定图之类)从文件选。
  Future<void> _partFromFile(int i) async {
    final f = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: '图片', extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp']),
    ]);
    if (f != null && mounted) _setPart(i, f.path);
  }

  void _removePart(int i) => setState(() {
    _slot.extras.removeAt(i).label.dispose();
    _picking = null;
  });

  void _next() {
    if (_step == 1) {
      for (final s in _slots) {
        if (s.status.every((x) => x == _Status.idle)) _generate(s);
      }
      setState(() => _step = 2);
    } else if (_step == 2) {
      setState(() => _step = 3);
    } else {
      _save();
      _writeDraft(done: true);
      Navigator.pop(context, (roster: _roster(), scene: _scene));
    }
  }

  List<ChaCard> _roster() => [
    for (final s in _slots)
      ChaCard.fromText(s.name.text, s.series.text, s.cands[s.pick].text, [
        for (final e in s.extras)
          if (e.path.isNotEmpty) (path: e.path, label: e.label.text),
      ], _refOf(s), s.bind),
  ];

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 980, maxHeight: 700),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
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
    padding: const EdgeInsets.fromLTRB(22, 14, 12, 14),
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
        if (widget.data != null)
          NlIconButton(Icons.history, tooltip: '角色卡草稿', onPressed: _drafts.isEmpty ? null : _openDrafts),
        NlIconButton(Icons.close, tooltip: '关闭', onPressed: () => Navigator.pop(context)),
      ],
    ),
  );

  Widget _slotTabs() => Padding(
    padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (i, s) in _slots.indexed)
          NlChip(
            label: s.name.text.trim().isEmpty ? '卡 ${i + 1}' : '卡 ${i + 1} · ${s.name.text.trim()}',
            selected: i == _cur,
            onTap: () => setState(() {
              _cur = i;
              _picking = null;
            }),
          ),
        if (_step == 1 && _slots.length < maxCards)
          NlButton(label: '添加角色卡', icon: Icons.add, tone: Tone.ghost, onPressed: () => setState(() {
            _slots.add(_Slot());
            _cur = _slots.length - 1;
            _picking = null;
          })),
        if (_step == 1 && _slots.length > 1)
          NlButton(label: '删除此卡', icon: Icons.delete_outline, tone: Tone.danger, onPressed: () => setState(() {
            final gone = _slots.removeAt(_cur);
            _queue.removeWhere((q) => q.$1 == gone);
            gone.dispose();
            _cur = (_cur - 1).clamp(0, _slots.length - 1);
            _picking = null;
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
        SizedBox(
          width: 260,
          child: ListView(
            children: [
              field('角色名 · 必填', s.name, '如 Suzukaze Aoba'),
              const SizedBox(height: 8),
              _identifyBox(s),
              const SizedBox(height: 14),
              field('作品名', s.series, '如 New Game!'),
              const SizedBox(height: 22),
              _bindBox(s),
              const SizedBox(height: 22),
              Text('部件参考', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
              const SizedBox(height: 2),
              Text('背面、武器、发饰特写… 加一个部件,在右边点图', style: TextStyle(fontSize: 11, color: NlColors.slate400)),
              const SizedBox(height: 8),
              for (final (i, e) in s.extras.indexed) _partRow(i, e),
              Align(
                alignment: Alignment.centerLeft,
                child: NlButton(label: '添加部件', icon: Icons.add, tone: Tone.outline, onPressed: _addPart),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_unfinished case final d?)
                _banner(
                  '没做完的角色卡 · ${d.cards.map((c) => c.name.trim()).where((n) => n.isNotEmpty).join('、')} · ${_when(d.time)}',
                  ('继续编辑', Icons.edit_outlined, () => _resume(d)),
                  () => setState(() => _unfinished = null),
                )
              else if (_saved case final saved?)
                _banner(
                  '上次的角色卡 · ${saved.cards.map((c) => c.name).join('、')} · ${_when(saved.time)}',
                  ('复用', Icons.replay, _reuse),
                  () => setState(() => _saved = null),
                ),
              Row(children: [Expanded(child: _gridHeader()), _folderSelect()]),
              Expanded(child: _refGrid(s)),
            ],
          ),
        ),
      ],
    );
  }

  String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  /// 网格上方的提示条:没做完的草稿(继续编辑)或上次确认的卡(复用就不用再生成)。
  Widget _banner(String text, (String, IconData, VoidCallback) action, VoidCallback close) {
    return PopIn(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(
          color: NlColors.primaryBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: NlColors.primaryBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.history, size: 16, color: NlColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: NlColors.primary)),
            ),
            NlButton(label: action.$1, icon: action.$2, tone: Tone.primary, onPressed: action.$3),
            NlIconButton(Icons.close, tooltip: '这次不用', onPressed: close),
          ],
        ),
      ),
    );
  }

  Widget _gridHeader() {
    final p = _picking;
    if (p == null || p >= _slot.extras.length) {
      return Label('主参考图', trailing: Text('点一张代表这个角色', style: TextStyle(fontSize: 11, color: NlColors.slate400)));
    }
    final label = _slot.extras[p].label.text.trim();
    return Label(
      '为部件 ${p + 1}${label.isEmpty ? '' : '「$label」'}选一张图',
      trailing: Align(
        alignment: Alignment.centerRight,
        child: NlButton(label: '取消', tone: Tone.ghost, onPressed: () => setState(() => _picking = null)),
      ),
    );
  }

  String _folderName(String f) => f.isEmpty ? '根目录' : f;

  /// 绑定子文件夹:那里的图跳过认人,直接用这张卡;两个勾选决定随图发不发参考图 / 人物卡文字。
  Widget _bindBox(_Slot s) {
    final folders = [...{for (final e in widget.images) e.folder}];
    Widget check(String label, bool v, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Row(children: [
            NlCheck(value: v, onTap: onTap),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, color: NlColors.slate700)),
          ]),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('绑定子文件夹 · 可选', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
        const SizedBox(height: 2),
        Text(
          s.folder == null ? '不绑定:和其他卡一起逐张认人' : '这个文件夹的每张图都有这个角色',
          style: TextStyle(fontSize: 11, color: NlColors.slate400),
        ),
        const SizedBox(height: 6),
        NlSelect<String?>(
          value: s.folder,
          items: [(null, '不绑定'), for (final f in folders) (f, _folderName(f))],
          onChanged: (f) => setState(() {
            s.folder = f;
            if (f != null && _folders.contains(f)) _folder = f;
          }),
        ),
        if (s.folder != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            NlChip(label: '单人', selected: s.solo, onTap: () => setState(() => s.solo = true)),
            const SizedBox(width: 6),
            NlChip(label: '多人', selected: !s.solo, onTap: () => setState(() => s.solo = false)),
          ]),
          const SizedBox(height: 4),
          Text(
            s.solo ? '只有她:跳过认人,直接用这张卡' : '一定有她:其他人照常用全部卡认',
            style: TextStyle(fontSize: 11, color: NlColors.slate400),
          ),
          check('随图发参考图', s.bindRefs, () => setState(() => s.bindRefs = !s.bindRefs)),
          check('随图发人物卡文字 · 核对服装', s.bindText, () => setState(() => s.bindText = !s.bindText)),
        ],
      ],
    );
  }

  /// 只有一个文件夹时不显示。
  Widget _folderSelect() {
    final folders = _folders;
    if (folders.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        width: 240,
        child: NlSelect<String>(
          value: _folder,
          items: [
            for (final f in folders) (f, '${_folderName(f)} · ${_grid.where((e) => e.folder == f).length}'),
          ],
          onChanged: (f) => setState(() => _folder = f),
        ),
      ),
    );
  }

  /// 点图:在给部件选图时填给那个部件,否则设成主参考图。主参考图描蓝边,部件用到的图标上序号。
  Widget _refGrid(_Slot s) {
    final picking = _picking != null && _picking! < s.extras.length;
    final main = _refOf(s);
    final shown = [for (final e in _grid) if (e.folder == _folder) e.path];
    return GridView.builder(
      key: ValueKey(_folder),
      // 留边:选中图外圈的光晕不被网格边缘切掉。
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 124, childAspectRatio: 3 / 4, mainAxisSpacing: 12, crossAxisSpacing: 12),
      itemCount: shown.length,
      itemBuilder: (_, i) {
        final path = shown[i];
        final isMain = path == main;
        final parts = [for (final (k, e) in s.extras.indexed) if (e.path == path) k + 1];
        return GestureDetector(
          onTap: () => picking ? _setPart(_picking!, path) : setState(() => s.ref = path),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: Motion.base,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isMain ? NlColors.primary : parts.isNotEmpty ? NlColors.accent : Colors.transparent, width: 2),
                boxShadow: isMain ? [BoxShadow(color: NlColors.primaryBg, spreadRadius: 3)] : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(path), fit: BoxFit.cover, cacheWidth: 220),
                    // 给部件选图时,图上淡淡蒙一层主色,提示「现在点是给部件的」。
                    AnimatedOpacity(
                      opacity: picking ? .12 : 0,
                      duration: Motion.base,
                      child: ColoredBox(color: NlColors.primary),
                    ),
                    if (isMain || parts.isNotEmpty)
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: Wrap(spacing: 3, children: [
                          if (isMain) _badge('主', NlColors.primary),
                          for (final n in parts) _badge('部件 $n', NlColors.accent),
                        ]),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
    child: Text(text, style: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w600)),
  );

  /// 一个部件:缩略图(点它重新在右边选)、这张拍的是什么、从文件选、删掉。
  Widget _partRow(int i, ({String path, TextEditingController label}) e) {
    final active = _picking == i;
    return AnimatedContainer(
      duration: Motion.base,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: active ? NlColors.primaryBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? NlColors.primaryBorder : Colors.transparent),
      ),
      child: Row(children: [
        Tooltip(
          message: '在右边点一张图',
          child: GestureDetector(
            onTap: () => setState(() => _picking = active ? null : i),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: e.path.isEmpty
                    ? Container(
                        width: 40,
                        height: 40,
                        color: NlColors.slate100,
                        child: Icon(Icons.touch_app_outlined, size: 18, color: active ? NlColors.primary : NlColors.slate400),
                      )
                    : Image.file(File(e.path), width: 40, height: 40, fit: BoxFit.cover, cacheWidth: 96),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: e.label,
            style: const TextStyle(fontSize: 12.5),
            onChanged: (_) => setState(() {}),
            decoration: fieldDecoration('拍的是什么,如 背面 / 武器'),
          ),
        ),
        NlIconButton(Icons.folder_open_outlined, tooltip: '从文件选', onPressed: () => _partFromFile(i)),
        NlIconButton(Icons.close, tooltip: '删掉这个部件', onPressed: () => _removePart(i)),
      ]),
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
                      // 模型名长时截断(悬停看全名),不压到右边的按钮。
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Tooltip(
                            message: modelLabel(cfg.chaCards[v] ?? cfg.vision, widget.local),
                            child: Pill(modelLabel(cfg.chaCards[v] ?? cfg.vision, widget.local)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      NlIconButton(Icons.refresh, tooltip: '重新生成', onPressed: s.status[v] == _Status.busy ? null : () => _generate(s, v)),
                    ]),
                    const SizedBox(height: 8),
                    Expanded(
                      child: switch (s.status[v]) {
                        _Status.busy || _Status.idle || _Status.queued => Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: NlColors.primary)),
                            const SizedBox(height: 8),
                            Text(s.status[v] == _Status.queued ? '排队中…' : '生成中…', style: TextStyle(fontSize: 12, color: NlColors.slate500)),
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
                    // 中文只对照(同旧版):英文才是写进标注的。
                    if (s.status[v] == _Status.done)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: GlossPane(text: s.cands[v].text, translator: translatorFor(cfg)),
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
                      if (s.bind case final b?)
                        Text(
                          [
                            '绑定 ${_folderName(b.folder)}',
                            b.solo ? '单人' : '多人',
                            if (b.refs) '发参考图',
                            if (b.text) '发人物卡文字',
                          ].join(' · '),
                          style: TextStyle(fontSize: 11.5, color: NlColors.primary),
                        ),
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
        NlCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Text('整批画面', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(child: Text('每张图:判定属于哪张卡 · 核对服装 · 删掉看不见的细节 · 写画面段', style: label)),
              ]),
              const SizedBox(height: 8),
              NlSelect<ModelRef?>(
                value: _sceneOptions.contains(_scene) ? _scene : null,
                hint: '选整批画面用的模型',
                items: [for (final r in _sceneOptions) (r, _modelName(r))],
                onChanged: (r) => setState(() => _scene = r),
              ),
              const SizedBox(height: 6),
              Text(
                '同时 ${_scene?.profileId == localProfileId ? 1 : cfg.parallel} 张 · 失败自动重试一次 · 写成「人物卡 + 空行 + 画面段」· '
                '不属于任何角色卡的图跳过 · 先自动备份',
                style: label,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        NlCard(
          child: ChaPreflight(
            images: widget.images,
            roster: _roster,
            ask: _sceneOptions.contains(_scene) ? askerFor(_scene, cfg, widget.local) : null,
          ),
        ),
      ],
    );
  }

  /// 整批画面能选的:模型池里的,加上已下载的本地 GGUF 模型(Florence-2 不行:它不吃自定义提示词)。
  List<ModelRef> get _sceneOptions {
    final local = widget.local.picked;
    return [
      ...widget.config.pool,
      if (local != null && !local.florence && widget.local.installed(local)) const ModelRef(localProfileId, ''),
    ];
  }

  String _modelName(ModelRef r) {
    final p = widget.config.profiles.where((p) => p.id == r.profileId).firstOrNull;
    return r.profileId == localProfileId ? modelLabel(r, widget.local) : '${p?.name ?? ''} · ${r.model}';
  }

  Widget _footer() {
    final ok = switch (_step) {
      1 => _canGenerate,
      2 => _canConfirm,
      _ => _sceneOptions.contains(_scene),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
      decoration: BoxDecoration(color: NlColors.slate50, border: Border(top: BorderSide(color: NlColors.border))),
      child: Row(
        children: [
          if (_step > 1) NlButton(label: '上一步', icon: Icons.arrow_back, tone: Tone.outline, onPressed: () => setState(() => _step--)),
          const Spacer(),
          if (!ok)
            Text(
              switch (_step) {
                1 => '先填写每张角色卡的角色名',
                2 => '为每张角色卡选定一套人物卡',
                _ => ok ? '确认后开始' : '先选整批画面用的模型',
              },
              style: TextStyle(fontSize: 11.5, color: NlColors.slate500),
            ),
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
