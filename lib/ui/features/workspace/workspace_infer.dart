part of 'workspace.dart';

/// 单张推理的结果:先预览成红绿对比,采纳后才写进编辑区。
@immutable
class PendingResult {
  const PendingResult(this.key, this.text, this.model, {this.translated = false});

  final String key;
  final String text;

  /// 推理时是模型名;翻译时是「翻译为中文」这类,采纳后直接当历史标签。
  final String model;
  final bool translated;
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

  /// 结束时给用户看的一句话。
  String get summary => [
    cancelled ? '已取消 · 写入 ${changes.length} 张' : '推标完成:写入 ${changes.length} 张',
    if (skipped.isNotEmpty) '跳过 ${skipped.length}',
    if (failed > 0) '失败 $failed',
  ].join(' · ');

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
      final raw = await run(e);
      if (raw == null) return '模型判定这张图不需要写';
      pending = PendingResult(e.key, cleanCaption(raw), modelName);
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
    if (entry?.key == p.key) setText(p.text, label: p.translated ? p.model : '推理 · ${p.model}');
  }

  /// 翻译结果先放进 [pending] 预览(当前这张图)。
  void proposeTranslation(String text, String label) {
    final e = entry;
    if (e == null) return;
    pending = PendingResult(e.key, text, label, translated: true);
    changed();
  }

  void rejectPending() {
    pending = null;
    changed();
  }

  /// 批量推标:先打快照,同时发 [parallel] 张,每张推完就写盘(拒绝 / 出错的那张保留原文;
  /// [run] 返回 null 的跳过),结束后记一条操作日志。[list] 给了就用它,否则按 [scope] 取。
  Future<String?> startBatch(
    Scope scope,
    CaptionFn? run, {
    String title = 'LLM 推标',
    List<ImageEntry>? list,
    String missing = '还没有视觉模型 · 去「模型」页添加',
    int parallel = 1,
  }) async {
    if (run == null) return missing;
    if (job != null || root == null) return null;
    final items = list ?? scopeEntries(scope);
    if (items.isEmpty) return '范围内没有图片';
    final j = job = InferJob(title, items);
    changed();
    final zip = await snapshotCaptions(root!, j.title);
    final before = {for (final e in items) e.key: _saved[e.key] ?? ''};
    var next = 0;
    // 几个「工人」轮流从队列里取下一张;取消后各自做完手上这张就停。
    Future<void> worker() async {
      while (!j.cancelled && next < items.length) {
        final e = items[next++];
        try {
          final raw = await run(e);
          if (raw == null) {
            j.skipped.add(e);
          } else {
            final text = cleanCaption(raw);
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
    }

    await Future.wait([for (var i = 0; i < math.max(1, math.min(parallel, items.length)); i++) worker()]);
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
