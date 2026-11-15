import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/backups.dart';
import '../../../core/captions.dart';
import '../../../core/cha.dart';
import '../../../core/cha_store.dart';
import '../../../core/dataset.dart';
import '../../../core/dataset_store.dart';
import '../../../core/history.dart';
import '../../../core/llm/cleaning.dart';
import '../../../core/text_io.dart';
import '../../../core/text_ops.dart';

part 'workspace_batch.dart';
part 'workspace_infer.dart';

enum EditMode { chips, sentences, text, json }

enum ListFilter { all, unlabeled, unsaved }

enum Scope { current, folder, selected, unlabeled, all }

/// 看一张图、返回标注;返回 null 表示这张跳过不写(CHA 判定不属于任何角色卡)。
typedef CaptionFn = Future<String?> Function(ImageEntry entry);

/// 标注台的状态:打开的数据集、每张图的标注(内存里的 / 磁盘上的)、历史、选择、批量与推标。
/// 标注只在保存或批量操作时写盘;批量操作先打 zip 快照并记进操作日志。
class Workspace extends ChangeNotifier {
  Workspace({required this.dataHome, this.onRootChanged});

  /// 程序数据的根(「文档/NLaptXD」);每个数据集的快照、日志、角色卡在它的 datasets 下。
  final Directory dataHome;
  final void Function(String root)? onRootChanged;

  Directory? root;

  /// 当前数据集的程序数据目录(见 dataset_store.dart)。
  Directory? dataDir;
  bool loading = false;
  List<ImageEntry> entries = const [];
  final _text = <String, String>{};
  final _saved = <String, String>{};
  final _history = <String, CaptionHistory>{};
  final nonUtf8 = <String>{};
  OpLog? oplog;

  int current = 0;
  final selected = <int>{};
  int _anchor = 0;
  String query = '';
  ListFilter filter = ListFilter.all;
  EditMode mode = EditMode.chips;
  bool grid = false;

  /// JSON 视图里选中的框(编辑区的卡片和预览图上的框同步),-1 是没选。
  int box = -1;
  final collapsed = <String>{};

  // 推标(workspace_infer.dart)
  PendingResult? pending;
  bool busy = false;
  InferJob? job;
  InferJob? lastJob;

  /// 这个数据集做过的 CHA 标注(旧的在前),见 [recordChaRun]。
  List<ChaRun> chaRuns = const [];

  /// 给 part 里的扩展用:notifyListeners 是 protected 的。
  void changed() => notifyListeners();

  // ---- 打开数据集 ----

  Future<void> open(Directory dir) async {
    loading = true;
    notifyListeners();
    try {
      final found = await scanDataset(dir);
      final reads = await Future.wait(found.map((e) => readCaption(File(e.txtPath))));
      _text.clear();
      _saved.clear();
      _history.clear();
      nonUtf8.clear();
      selected.clear();
      for (var i = 0; i < found.length; i++) {
        _text[found[i].key] = _saved[found[i].key] = reads[i].text;
        if (!reads[i].utf8) nonUtf8.add(found[i].key);
      }
      root = dir;
      entries = List.unmodifiable(found);
      current = 0;
      _anchor = 0;
      pending = null;
      final data = dataDir = datasetDataDir(dataHome, dir);
      // 早先放在数据集里的 .nlapt / .backups 搬到文档里。
      final moved = await migrateLegacyData(dir, data);
      if (moved > 0) debugPrint('已把 $moved 个旧数据文件从数据集搬到 ${data.path}');
      oplog = OpLog(data);
      await oplog!.load();
      chaRuns = await loadChaRuns(data);
      onRootChanged?.call(dir.path);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 重新扫描;没保存的修改保留(文件还在的话)。
  Future<void> refresh() async {
    final dir = root;
    if (dir == null) return;
    final unsaved = {for (final e in entries) if (isDirty(e)) e.key: textOf(e)};
    final key = entry?.key;
    await open(dir);
    unsaved.forEach((k, v) {
      if (_text.containsKey(k)) _text[k] = v;
    });
    final i = entries.indexWhere((e) => e.key == key);
    if (i >= 0) current = i;
    notifyListeners();
  }

  // ---- 读 ----

  ImageEntry? get entry => entries.isEmpty ? null : entries[current.clamp(0, entries.length - 1)];
  String textOf(ImageEntry e) => _text[e.key] ?? '';
  bool isDirty(ImageEntry e) => _text[e.key] != _saved[e.key];
  int get dirtyCount => entries.where(isDirty).length;
  int get unlabeledCount => entries.where((e) => textOf(e).trim().isEmpty).length;
  List<String> get folders => [...{for (final e in entries) e.folder}];
  CaptionHistory? get history => entry == null ? null : _historyOf(entry!);

  /// txt 相对数据集根目录的路径(操作日志里这样记,数据集搬家也能回滚)。
  String relPath(ImageEntry e) => e.txtPath.substring(root!.absolute.path.length + 1);
  String relImage(ImageEntry e) => e.imagePath.substring(root!.absolute.path.length + 1);

  /// 已经写进 txt 的新标注:内存、磁盘副本和历史一起更新(历史要先于改动建立)。
  void _commitWritten(ImageEntry e, String text, String label) {
    final h = _historyOf(e);
    _text[e.key] = _saved[e.key] = text;
    h.push(label, text);
  }

  CaptionHistory _historyOf(ImageEntry e) => _history.putIfAbsent(e.key, () => CaptionHistory(textOf(e)));

  /// 过滤 + 搜索后可见的序号(文件名或标注里含关键字,不分大小写)。
  List<int> get visible {
    final q = query.trim().toLowerCase();
    return [
      for (var i = 0; i < entries.length; i++)
        if ((q.isEmpty || entries[i].name.toLowerCase().contains(q) || textOf(entries[i]).toLowerCase().contains(q)) &&
            switch (filter) {
              ListFilter.all => true,
              ListFilter.unlabeled => textOf(entries[i]).trim().isEmpty,
              ListFilter.unsaved => isDirty(entries[i]),
            })
          i,
    ];
  }

  List<ImageEntry> scopeEntries(Scope scope) {
    final e = entry;
    if (e == null) return const [];
    return switch (scope) {
      Scope.current => [e],
      Scope.folder => [for (final x in entries) if (x.folder == e.folder || x.folder.startsWith('${e.folder}${Platform.pathSeparator}')) x],
      Scope.selected => [for (final i in selected.toList()..sort()) entries[i]],
      Scope.unlabeled => [for (final x in entries) if (textOf(x).trim().isEmpty) x],
      Scope.all => entries,
    };
  }

  // ---- 选择与导航 ----

  void select(int i, {bool range = false, bool remove = false}) {
    if (i < 0 || i >= entries.length) return;
    if (range) {
      for (var k = _anchor < i ? _anchor : i; k <= (_anchor < i ? i : _anchor); k++) {
        selected.add(k);
      }
    } else if (remove) {
      selected.remove(i);
    } else {
      _anchor = i;
    }
    if (current != i) {
      pending = null;
      box = -1;
    }
    current = i;
    notifyListeners();
  }

  void toggleSelected(int i) {
    selected.contains(i) ? selected.remove(i) : selected.add(i);
    _anchor = i;
    notifyListeners();
  }

  void toggleFolder(String folder) {
    final ks = [for (var i = 0; i < entries.length; i++) if (entries[i].folder == folder) i];
    final all = ks.every(selected.contains);
    all ? selected.removeAll(ks) : selected.addAll(ks);
    notifyListeners();
  }

  void selectAll() {
    selected.length == entries.length ? selected.clear() : selected.addAll(List.generate(entries.length, (i) => i));
    notifyListeners();
  }

  void clearSelection() {
    selected.clear();
    notifyListeners();
  }

  /// 多选时只在选中的图之间切。
  void step(int delta) {
    if (entries.isEmpty) return;
    final keys = selected.length > 1 ? (selected.toList()..sort()) : List.generate(entries.length, (i) => i);
    final at = keys.indexOf(current);
    select(keys[((at < 0 ? 0 : at) + delta) % keys.length]);
  }

  void setView({ListFilter? filter, bool? grid, EditMode? mode, String? query}) {
    this.filter = filter ?? this.filter;
    this.grid = grid ?? this.grid;
    this.mode = mode ?? this.mode;
    this.query = query ?? this.query;
    notifyListeners();
  }

  void selectBox(int i) {
    box = i;
    notifyListeners();
  }

  void toggleCollapsed(String folder) {
    collapsed.contains(folder) ? collapsed.remove(folder) : collapsed.add(folder);
    notifyListeners();
  }

  // ---- 编辑 ----

  /// 改当前图的标注。[label] 为 null 时只改内存(打字过程中),失焦时再 [commitTyping]。
  void setText(String text, {String? label}) {
    final e = entry;
    if (e == null) return;
    final h = _historyOf(e); // 先建历史:它要记下改之前的样子
    _text[e.key] = text;
    if (label != null) h.push(label, text);
    notifyListeners();
  }

  void editSegments(void Function(List<String> segments) change, String label) {
    final e = entry;
    if (e == null) return;
    final segs = splitSegments(textOf(e));
    change(segs);
    setText(joinSegments(segs), label: label);
  }

  void commitTyping(String label) {
    final e = entry;
    if (e != null) _historyOf(e).push(label, textOf(e));
    notifyListeners();
  }

  bool undo() => _moveHistory((h) => h.canUndo ? h.undo() : null);
  bool redo() => _moveHistory((h) => h.canRedo ? h.redo() : null);
  void jumpHistory(int index) => _moveHistory((h) => h.jumpTo(index));

  void clearHistory() {
    history?.clear();
    notifyListeners();
  }

  bool _moveHistory(String? Function(CaptionHistory h) move) {
    final e = entry;
    if (e == null) return false;
    final text = move(_historyOf(e));
    if (text == null) return false;
    _text[e.key] = text;
    notifyListeners();
    return true;
  }

  // ---- 保存 ----

  Future<void> save() async {
    final e = entry;
    if (e != null && isDirty(e)) await _write([e]);
  }

  Future<int> saveAll() async {
    final dirty = entries.where(isDirty).toList();
    await _write(dirty);
    return dirty.length;
  }

  Future<void> _write(List<ImageEntry> list) async {
    for (final e in list) {
      final text = textOf(e);
      await writeAtomic(e.txtPath, text);
      _saved[e.key] = text;
      nonUtf8.remove(e.key);
    }
    notifyListeners();
  }
}
