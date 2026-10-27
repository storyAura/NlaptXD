import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'llm_client.dart';

/// 发给视觉模型的图,长边不超过这么多(同旧版 nlapt/llm/vision.py 的 DEFAULT_MAX_EDGE)。
const maxImageEdge = 1024;
const jpegQuality = 85;

/// 发送前缩图:长边缩到 [maxImageEdge] 以内,透明处混成白底,存成 JPEG,省上传时间和 token。
/// 本来就是够小的 JPEG 原样发;解不开的格式也原样发,交给接口自己处理。
Future<ImagePart> prepareImage(Uint8List bytes, String mime) => Isolate.run(() => prepareImageSync(bytes, mime));

ImagePart prepareImageSync(Uint8List bytes, String mime) {
  img.Image? src;
  try {
    src = img.decodeImage(bytes);
  } on Object {
    src = null;
  }
  if (src == null) return (bytes: bytes, mime: mime);
  final long = math.max(src.width, src.height);
  if (long <= maxImageEdge && mime == 'image/jpeg') return (bytes: bytes, mime: mime);
  final scale = math.min(1.0, maxImageEdge / long);
  final fit = scale < 1
      ? img.copyResize(
          src,
          width: math.max(1, (src.width * scale).round()),
          height: math.max(1, (src.height * scale).round()),
          interpolation: img.Interpolation.cubic,
        )
      : src;
  final flat = img.Image(width: fit.width, height: fit.height);
  img.fill(flat, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(flat, fit);
  return (bytes: img.encodeJpg(flat, quality: jpegQuality), mime: 'image/jpeg');
}
