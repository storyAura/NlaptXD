import 'dart:io';

import 'package:flutter/foundation.dart';

export 'text_io.dart' show readCaption, CaptionRead;

const imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.bmp'};

/// 一张图和它的同名 txt。[folder] 是相对数据集根目录的文件夹(根目录下为空串)。
@immutable
class ImageEntry {
  const ImageEntry({required this.imagePath, required this.txtPath, required this.folder});

  final String imagePath;
  final String txtPath;
  final String folder;

  String get name => imagePath.substring(imagePath.lastIndexOf(Platform.pathSeparator) + 1);
  String get key => imagePath;
}

String _ext(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot).toLowerCase();
}

String _stem(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? name : name.substring(0, dot);
}

/// 递归找图片,按「同目录、同主文件名」配 txt(扩展名不分大小写)。
/// 以 `.` 开头的文件夹(.backups、.nlapt)跳过;只有 txt 没有图的不列出。
Future<List<ImageEntry>> scanDataset(Directory root) async {
  final sep = Platform.pathSeparator;
  final rootPath = root.absolute.path;
  final byDir = <String, List<File>>{};
  await for (final e in root.absolute.list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final rel = e.path.substring(rootPath.length + 1);
    if (rel.split(sep).any((part) => part.startsWith('.'))) continue;
    byDir.putIfAbsent(e.parent.path, () => []).add(e);
  }
  final entries = <ImageEntry>[];
  for (final MapEntry(key: dir, value: files) in byDir.entries) {
    final txts = {
      for (final f in files)
        if (_ext(f.path) == '.txt') _stem(_base(f.path)).toLowerCase(): f.path,
    };
    final folder = dir.length > rootPath.length ? dir.substring(rootPath.length + 1) : '';
    for (final f in files) {
      if (!imageExtensions.contains(_ext(f.path))) continue;
      final stem = _stem(_base(f.path));
      entries.add(
        ImageEntry(
          imagePath: f.path,
          txtPath: txts[stem.toLowerCase()] ?? '$dir$sep$stem.txt',
          folder: folder,
        ),
      );
    }
  }
  entries.sort((a, b) {
    final byFolder = naturalCompare(a.folder, b.folder);
    return byFolder != 0 ? byFolder : naturalCompare(a.name, b.name);
  });
  return entries;
}

String _base(String path) => path.substring(path.lastIndexOf(Platform.pathSeparator) + 1);

final _chunk = RegExp(r'\d+|\D+');

/// 自然排序:`img2` 排在 `img10` 前面,不分大小写。
int naturalCompare(String a, String b) {
  final xs = _chunk.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final ys = _chunk.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < xs.length && i < ys.length; i++) {
    final x = xs[i], y = ys[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = nx != null && ny != null ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return xs.length.compareTo(ys.length);
}
