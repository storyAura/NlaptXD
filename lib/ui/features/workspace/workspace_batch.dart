part of 'workspace.dart';

/// 批量改字与整批回滚:先快照、再写盘、最后记操作日志。
extension WorkspaceBatch on Workspace {
  /// 把 [next] 里的新标注写进 txt 并记一条操作日志;返回改了几个文件。
  Future<int> applyBatch(String title, String detail, Map<ImageEntry, String> next) async {
    final todo = {
      for (final MapEntry(:key, :value) in next.entries)
        if (value != textOf(key) || isDirty(key)) key: value,
    };
    if (todo.isEmpty || root == null) return 0;
    final zip = await snapshotCaptions(root!, title);
    final changes = [for (final e in todo.keys) OpChange(relPath(e), _saved[e.key] ?? '')];
    for (final MapEntry(key: e, value: text) in todo.entries) {
      await writeAtomic(e.txtPath, text);
      _commitWritten(e, text, title);
    }
    await oplog!.add(
      OpRecord(id: oplog!.nextId, title: title, detail: detail, time: DateTime.now(), backup: zip, changes: changes),
    );
    changed();
    return todo.length;
  }

  Future<int> findReplace(Scope scope, FindSpec spec, String replacement) {
    final next = {
      for (final e in scopeEntries(scope))
        if (spec.count(textOf(e)) > 0) e: replaceIn(textOf(e), spec, replacement),
    };
    return applyBatch('查找替换', '「${spec.query}」→「${replacement.isEmpty ? '删除' : replacement}」', next);
  }

  Future<int> addAffixTo(Scope scope, String affix, {required bool atStart, required bool asTag}) {
    final next = {
      for (final e in scopeEntries(scope)) e: addAffix(textOf(e), affix, atStart: atStart, asTag: asTag),
    };
    return applyBatch(atStart ? '前缀' : '后缀', '「${affix.trim()}」${asTag ? ' · 独立标签' : ''}', next);
  }

  /// 「中文全部转为英文」:范围内含中文的文件逐个翻译([perSegment] 时只译含中文的段),
  /// 全译完再一起写盘(打快照、记日志)。翻译出错的文件不改,算进 failed。
  Future<({int written, int failed})> translateChineseToEnglish(
    Scope scope, {
    required bool perSegment,
    required Future<String> Function(String text) toEnglish,
  }) async {
    final next = <ImageEntry, String>{};
    var failed = 0;
    for (final e in scopeEntries(scope)) {
      final text = textOf(e);
      if (!hasCjk(text)) continue;
      try {
        next[e] = perSegment
            ? joinSegments([for (final s in splitSegments(text)) hasCjk(s) ? await toEnglish(s) : s])
            : await toEnglish(text);
      } on Object {
        failed++;
      }
    }
    final written = await applyBatch('中文转英文', perSegment ? '分段翻译' : '整段翻译', next);
    return (written: written, failed: failed);
  }

  /// 把一次批量操作改过的文件恢复成操作前的样子(之后对它们的修改也会被覆盖)。
  Future<int> rollback(int id) async {
    final log = oplog;
    final dir = root;
    if (log == null || dir == null) return 0;
    final op = log.records.firstWhere((r) => r.id == id);
    final byRel = {for (final e in entries) relPath(e): e};
    var n = 0;
    for (final c in op.changes) {
      final path = '${dir.absolute.path}${Platform.pathSeparator}${c.relPath}';
      await writeAtomic(path, c.before);
      final e = byRel[c.relPath];
      if (e != null) _commitWritten(e, c.before, '整批回滚');
      n++;
    }
    await log.setStatus(id, OpStatus.rolledBack);
    changed();
    return n;
  }
}
