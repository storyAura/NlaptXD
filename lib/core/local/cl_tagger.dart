import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// CL Tagger v2.01a:给 CHA 角色卡识别角色名 / 作品名用。移植自旧版 NLapt 的
/// nlapt/local/tagger.py(预处理照 Penna 的 tagger.dart:透明处混成白底)。
/// 受限仓库,要 HuggingFace Token;许可证禁止再分发,所以只能让用户自己下。
const clTaggerRepo = 'cella110n/cl_tagger_v2';
const clTaggerFolder = 'cl-tagger-v2';
const clTaggerFiles = ['v2_01a/model.onnx', 'v2_01a/model.onnx.data', 'v2_01a/model_vocabulary.json'];

/// 角色对照表(公开的数据集仓库,不用 Token):character_tag,other_names,copyright,parent_tag,post_count。
const characterCsvPath = 'datasets/StoryAura/Danbooru-Dataset-csv/resolve/main/danbooru_character_tags.csv';
const characterCsvFile = 'danbooru_character_tags.csv';

/// 页面上显示用的大小(官方会同名覆盖,不校验)。
const clTaggerSize = 2211645300 + 791773 + 14594140 + 15131660;

const clImageSize = 384;

/// 识别时所有类别都用这个阈值(旧版 tagger_bridge.py 的 CHARACTER_MIN_PROB)。
const clCharacterThreshold = 0.35;

/// 最多取几个角色标签(旧版 MAX_DETECTED)。
const clMaxDetected = 8;

/// 标签表:下标 → (标签名,类别小写,如 character / copyright / general)。
typedef ClVocabulary = List<({String name, String category})>;

const _categoryOrder = ['general', 'character', 'copyright', 'meta', 'rating', 'quality'];

/// 解析 model_vocabulary.json:idx_to_tag + tag_to_category(类别名,或类别的下标)。
ClVocabulary parseClVocabulary(String json) {
  final root = jsonDecode(json) as Map<String, dynamic>;
  final names = root['categories'] is Map
      ? [for (final k in (root['categories'] as Map).keys) '$k'.toLowerCase()]
      : _categoryOrder;
  final byTag = <String, String>{};
  if (root['tag_to_category'] case final Map map) {
    for (final MapEntry(:key, :value) in map.entries) {
      byTag['$key'] = value is String
          ? value.toLowerCase()
          : value is int && value >= 0 && value < names.length
          ? names[value]
          : 'general';
    }
  }
  final byIndex = {
    for (final MapEntry(:key, :value) in (root['idx_to_tag'] as Map).entries) ?int.tryParse('$key'): '$value',
  };
  final size = byIndex.keys.fold(-1, math.max) + 1;
  return [
    for (var i = 0; i < size; i++) (name: byIndex[i] ?? '', category: byTag[byIndex[i]] ?? 'general'),
  ];
}

/// 384×384 的 RGBA 变成模型的输入 [1, 3, 384, 384]:透明处混成白底,RGB,值是 (x/255 - 0.5) / 0.5。
Float32List clPixels(Uint8List rgba) {
  const plane = clImageSize * clImageSize;
  final out = Float32List(plane * 3);
  for (var p = 0; p < plane; p++) {
    final a = rgba[p * 4 + 3] / 255;
    for (var c = 0; c < 3; c++) {
      final v = rgba[p * 4 + c] * a + 255 * (1 - a);
      out[c * plane + p] = (v / 255 - .5) / .5;
    }
  }
  return out;
}

typedef ScoredTag = ({String tag, double prob});

/// 模型输出(未过 sigmoid 的 logits)里超过阈值的角色和作品标签,各按概率从高到低。
({List<ScoredTag> characters, List<ScoredTag> copyrights}) decodeClTags(
  List<double> logits,
  ClVocabulary vocab, {
  double threshold = clCharacterThreshold,
}) {
  final characters = <ScoredTag>[], copyrights = <ScoredTag>[];
  for (var i = 0; i < logits.length && i < vocab.length; i++) {
    final prob = 1 / (1 + math.exp(-logits[i]));
    if (prob < threshold) continue;
    final v = vocab[i];
    if (v.category == 'character') characters.add((tag: v.name, prob: prob));
    if (v.category == 'copyright') copyrights.add((tag: v.name, prob: prob));
  }
  int byProb(ScoredTag a, ScoredTag b) => b.prob.compareTo(a.prob);
  return (characters: characters..sort(byProb), copyrights: copyrights..sort(byProb));
}
