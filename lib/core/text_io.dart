import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

@immutable
class CaptionRead {
  const CaptionRead(this.text, {this.utf8 = true});

  final String text;

  /// false:原文不是 UTF-8(比如 GBK),按 UTF-8 尽量解出来,保存后转成 UTF-8。
  final bool utf8;
}

const _bom = [0xEF, 0xBB, 0xBF];

/// 读一个 txt;不存在时当成空标注(只有图、没有 txt 的「未标注」)。
Future<CaptionRead> readCaption(File file) async {
  if (!await file.exists()) return const CaptionRead('');
  var bytes = await file.readAsBytes();
  if (bytes.length >= 3 && bytes[0] == _bom[0] && bytes[1] == _bom[1] && bytes[2] == _bom[2]) {
    bytes = bytes.sublist(3);
  }
  try {
    return CaptionRead(utf8.decode(bytes));
  } on FormatException {
    return CaptionRead(utf8.decode(bytes, allowMalformed: true), utf8: false);
  }
}

/// 先写临时文件再改名替换:写到一半断电也不会留下半个文件。
Future<void> writeAtomic(String path, String text) => writeBytesAtomic(path, utf8.encode(text));

/// 每个路径上排着的最后一次写入。
final _queued = <String, Future<void>>{};

/// 同一个路径的写入按调用顺序一个接一个做:并发写会撞在同一个临时文件上
/// (Windows 报「另一个程序正在使用此文件」),后发的也可能先落盘、把新内容盖成旧的(踩过)。
Future<void> writeBytesAtomic(String path, List<int> bytes) {
  final next = (_queued[path] ?? Future<void>.value()).catchError((Object _) {}).then((_) => _write(path, bytes));
  _queued[path] = next;
  next.whenComplete(() {
    if (identical(_queued[path], next)) _queued.remove(path);
  }).ignore();
  return next;
}

Future<void> _write(String path, List<int> bytes) async {
  final tmp = File('$path.nlapt-tmp');
  await tmp.parent.create(recursive: true);
  await tmp.writeAsBytes(bytes, flush: true);
  // Dart 在 Windows 上的 rename 会覆盖已存在的目标。
  await tmp.rename(path);
}
