part of 'workspace.dart';

/// 单张推理的结果:先预览成红绿对比,采纳后才写进编辑区。
@immutable
class PendingResult {
  const PendingResult(this.key, this.text, this.model);

  final String key;
  final String text;
  final String model;
}

/// 正在跑的批量推标。
class InferJob {
  InferJob(this.title, this.list);

  final String title;
  final List<ImageEntry> list;
  final started = DateTime.now();
  final changes = <ImageEntry, String>{};

  /// 推标函数返回 null 的图(CHA:不属于任何角色卡),没写。
  final skipped = <ImageEntry>[];
  final failedEntries = <ImageEntry>[];
  int done = 0;
  int get failed => failedEntries.length;
  String? lastError;
  bool cancelled = false;
  bool hidden = false;

  double get progress => list.isEmpty ? 1 : done / list.length;

  double get perMinute {
    final s = DateTime.now().difference(started).inMilliseconds / 60000;
    return s <= 0 ? 0 : done / s;
  }

  Duration get remaining {
    if (done == 0) return Duration.zero;
    final each = DateTime.now().difference(started) ~/ done;
    return each * (list.length - done);
  }
}

extension WorkspaceInfer on Workspace {
  /// 用 [run] 推理当前图,结果放进 [pending] 等用户采纳。[run] 为 null(没配好模型)时返回 [missing]。
  Future<String?> inferCurrent(CaptionFn? run, String modelName, {String missing = '还没有视觉模型 · 去「模型」页添加'}) async {
    final e = entry;
    if (e == null) return null;
    if (run == null) return missing;
    busy = true;
    pending = null;
    changed();
    try {
      final text = await run(e);
      if (text == null) return '模型判定这张图不需要写';
      pending = PendingResult(e.key, text, modelName);
      return null;
    } on Object catch (err) {
      return '推理失败:$err';
    } finally {
      busy = false;
      changed();
    }
  }

  void acceptPending() {
    final p = pending;
    if (p == null) return;
    pending = null;
    if (entry?.key == p.key) setText(p.text, label: '推理 · ${p.model}');
  }

  void rejectPending() {
    pending = null;
    changed();
  }

  /// 批量推标:先打快照,逐张写盘(拒绝 / 出错的那张保留原文;[run] 返回 null 的跳过),
  /// 结束后记一条操作日志。[list] 给了就用它,否则按 [scope] 取。
  Future<String?> startBatch(
    Scope scope,
    CaptionFn? run, {
    String title = 'LLM 推标',
    List<ImageEntry>? list,
    String missing = '还没有视觉模型 · 去「模型」页添加',
  }) async {
    if (run == null) return missing;
    if (job != null || root == null) return null;
    final items = list ?? scopeEntries(scope);
    if (items.isEmpty) return '范围内没有图片';
    final j = job = InferJob(title, items);
    changed();
    final zip = await snapshotCaptions(root!, j.title);
    final before = {for (final e in items) e.key: _saved[e.key] ?? ''};
    for (final e in items) {
      if (j.cancelled) break;
      try {
        final text = await run(e);
        if (text == null) {
          j.skipped.add(e);
        } else {
          await writeAtomic(e.txtPath, text);
          j.changes[e] = text;
          _commitWritten(e, text, j.title);
        }
      } on Object catch (err) {
        j.failedEntries.add(e);
        j.lastError = '$err';
      }
      j.done++;
      changed();
    }
    if (j.changes.isNotEmpty) {
      await oplog!.add(
        OpRecord(
          id: oplog!.nextId,
          title: j.title,
          detail: [
            if (j.cancelled) '已取消 · 完成 ${j.done}/${items.length}' else '成功 ${j.changes.length} · 失败 ${j.failed}',
            if (j.skipped.isNotEmpty) '跳过 ${j.skipped.length}',
          ].join(' · '),
          time: DateTime.now(),
          backup: zip,
          status: j.cancelled ? OpStatus.partial : OpStatus.done,
          changes: [for (final e in j.changes.keys) OpChange(relPath(e), before[e.key]!)],
        ),
      );
    }
    job = null;
    lastJob = j;
    changed();
    return null;
  }

  void cancelJob() {
    job?.cancelled = true;
    changed();
  }

  void setJobHidden(bool hidden) {
    job?.hidden = hidden;
    changed();
  }
}
