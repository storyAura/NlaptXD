/// 从 Penna 搬来的文件里用的 `tr('原文 {0}', [参数])`。NLaptXD 只有中文,这里只做占位符替换,
/// 好让那些文件原样保留、以后能对着 Penna 同步。
String tr(String text, [List<Object?> args = const []]) {
  var out = text;
  for (final (i, a) in args.indexed) {
    out = out.replaceAll('{$i}', '$a');
  }
  return out;
}
