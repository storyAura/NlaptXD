import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import 'text_io.dart';

const backupDirName = '.backups';
const sessionDirName = '.nlapt';
const defaultKeep = 20;

String _two(int n) => '$n'.padLeft(2, '0');
final _unsafe = RegExp(r'[\\/:*?"<>|\s]+');

/// 批量操作前把数据集里全部 txt 打成 zip 放进 `.backups/`,只留最新 [keep] 份。
/// 返回 zip 的文件名(和旧版同名格式:`2026-10-26_1428_查找替换.zip`)。
Future<String> snapshotCaptions(Directory root, String operation, {DateTime? now, int keep = defaultKeep}) async {
  final t = now ?? DateTime.now();
  final rootPath = root.absolute.path;
  final archive = Archive();
  await for (final e in root.absolute.list(recursive: true, followLinks: false)) {
    if (e is! File || !e.path.toLowerCase().endsWith('.txt')) continue;
    final rel = e.path.substring(rootPath.length + 1).replaceAll(Platform.pathSeparator, '/');
    if (rel.split('/').any((p) => p == backupDirName || p == sessionDirName)) continue;
    final bytes = await e.readAsBytes();
    archive.addFile(ArchiveFile(rel, bytes.length, bytes));
  }
  final dir = Directory('$rootPath${Platform.pathSeparator}$backupDirName');
  await dir.create(recursive: true);
  final op = operation.trim().replaceAll(_unsafe, '_');
  final base = '${t.year}-${_two(t.month)}-${_two(t.day)}_${_two(t.hour)}${_two(t.minute)}_$op';
  var name = '$base.zip';
  for (var n = 2; File('${dir.path}${Platform.pathSeparator}$name').existsSync(); n++) {
    name = '${base}_$n.zip';
  }
  await writeBytesAtomic('${dir.path}${Platform.pathSeparator}$name', ZipEncoder().encode(archive));
  await _prune(dir, keep);
  return name;
}

Future<void> _prune(Directory dir, int keep) async {
  final zips = [
    for (final f in dir.listSync())
      if (f is File && f.path.endsWith('.zip')) f,
  ]..sort((a, b) => a.path.compareTo(b.path)); // 名字以时间开头,按名字排就是按时间
  if (zips.length <= keep) return;
  for (final old in zips.take(zips.length - keep)) {
    try {
      await old.delete();
    } on FileSystemException catch (e) {
      debugPrint('清理旧快照失败:${old.path} $e');
    }
  }
}

enum OpStatus { done, partial, rolledBack }

/// 一个文件改之前的样子([relPath] 相对数据集根目录)。
@immutable
class OpChange {
  const OpChange(this.relPath, this.before);

  final String relPath;
  final String before;
}

/// 操作日志里的一次批量操作。
@immutable
class OpRecord {
  const OpRecord({
    required this.id,
    required this.title,
    required this.detail,
    required this.time,
    required this.backup,
    required this.changes,
    this.status = OpStatus.done,
  });

  final int id;
  final String title;
  final String detail;
  final DateTime time;
  final String backup;
  final List<OpChange> changes;
  final OpStatus status;

  OpRecord withStatus(OpStatus s) =>
      OpRecord(id: id, title: title, detail: detail, time: time, backup: backup, changes: changes, status: s);

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'detail': detail,
    'time': time.toIso8601String(),
    'backup': backup,
    'status': status.name,
    'changes': [for (final c in changes) {'path': c.relPath, 'before': c.before}],
  };

  factory OpRecord.fromJson(Map<String, dynamic> j) => OpRecord(
    id: j['id'] as int,
    title: j['title'] as String,
    detail: j['detail'] as String? ?? '',
    time: DateTime.parse(j['time'] as String),
    backup: j['backup'] as String? ?? '',
    status: OpStatus.values.asNameMap()[j['status']] ?? OpStatus.done,
    changes: [
      for (final c in j['changes'] as List) OpChange(c['path'] as String, c['before'] as String),
    ],
  );
}

/// `.nlapt/oplog.json`:批量操作的记录,新的在前;整批回滚靠它。
class OpLog {
  OpLog(Directory root)
    : _file = File('${root.absolute.path}${Platform.pathSeparator}$sessionDirName${Platform.pathSeparator}oplog.json');

  final File _file;
  List<OpRecord> _records = const [];

  List<OpRecord> get records => _records;
  int get nextId => _records.fold(0, (m, r) => r.id > m ? r.id : m) + 1;

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final list = jsonDecode(await _file.readAsString()) as List;
      _records = List.unmodifiable([for (final j in list) OpRecord.fromJson(j as Map<String, dynamic>)]);
    } on Object catch (e) {
      // 日志坏了不挡打开数据集;备份 zip 还在 .backups 里。
      debugPrint('操作日志读取失败,按空的处理:$e');
      _records = const [];
    }
  }

  Future<void> add(OpRecord record) async {
    _records = List.unmodifiable([record, ..._records]);
    await _save();
  }

  Future<void> setStatus(int id, OpStatus status) async {
    _records = List.unmodifiable([for (final r in _records) r.id == id ? r.withStatus(status) : r]);
    await _save();
  }

  Future<void> _save() => writeAtomic(_file.path, jsonEncode([for (final r in _records) r.toJson()]));
}
