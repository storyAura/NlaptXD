import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'backups.dart';

/// 程序给数据集记的东西(批量前的快照 zip、操作日志、CHA 角色卡)不放进数据集文件夹,
/// 放在「文档/NLaptXD/datasets/<文件夹名>-<路径指纹>」:训练集里只有图和 txt,拷走就能用。
/// 指纹按完整路径算(不分大小写),两个同名数据集不会混在一起。
Directory datasetDataDir(Directory home, Directory root) {
  final abs = root.absolute.path.replaceAll(RegExp(r'[\\/]+$'), '');
  final name = abs.split(RegExp(r'[\\/]')).last.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final print = sha1.convert(utf8.encode(abs.toLowerCase())).toString().substring(0, 8);
  final sep = Platform.pathSeparator;
  return Directory('${home.absolute.path}${sep}datasets$sep$name-$print');
}

/// 快照 zip 放在数据目录的 backups 里。
Directory backupsDir(Directory data) => Directory('${data.path}${Platform.pathSeparator}backups');

/// 把早先放在数据集里的 `.nlapt/*`(操作日志、角色卡)搬到 [data],`.backups/*.zip` 搬到 [data]/backups;
/// 搬完删掉空了的旧目录。新位置已有同名文件的不覆盖(留在原处)。返回搬了几个文件。
Future<int> migrateLegacyData(Directory root, Directory data) async {
  final sep = Platform.pathSeparator;
  var moved = 0;
  for (final (from, to) in [
    (Directory('${root.path}$sep$sessionDirName'), data),
    (Directory('${root.path}$sep$backupDirName'), backupsDir(data)),
  ]) {
    if (!await from.exists()) continue;
    await to.create(recursive: true);
    await for (final f in from.list()) {
      if (f is! File) continue;
      final dest = File('${to.path}$sep${f.path.split(sep).last}');
      if (await dest.exists()) continue;
      try {
        // 跨盘(D: → C: 文档)rename 会失败,先复制再删。
        await f.copy(dest.path);
        await f.delete();
        moved++;
      } on FileSystemException catch (e) {
        debugPrint('搬旧数据失败:${f.path} $e');
      }
    }
    try {
      if (await from.list().isEmpty) await from.delete();
    } on FileSystemException catch (e) {
      debugPrint('删旧目录失败:${from.path} $e');
    }
  }
  return moved;
}
