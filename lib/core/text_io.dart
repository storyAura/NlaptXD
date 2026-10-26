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

Future<void> writeBytesAtomic(String path, List<int> bytes) async {
  final tmp = File('$path.nlapt-tmp');
  await tmp.parent.create(recursive: true);
  await tmp.writeAsBytes(bytes, flush: true);
  // Dart 在 Windows 上的 rename 会覆盖已存在的目标。
  await tmp.rename(path);
}
