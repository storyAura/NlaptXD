import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/llm/openai_client.dart';
import 'data/app_config.dart';
import 'data/config_store.dart';
import 'ui/core/theme.dart';
import 'ui/features/workspace/workspace.dart';

/// 推标用的视觉模型;没配好返回 null(界面上提示去「模型」页)。
// ponytail: 原图直接发送(base64),不先缩到长边 1024;大图多的数据集慢、费 token,要省时加缩图。
CaptionFn? visionCaptioner(AppConfig c) {
  final ref = c.vision;
  final profile = c.profileOf(ref);
  if (ref == null || profile == null) return null;
  final client = OpenAiClient(profile);
  return (entry) async => client.caption(
    model: ref.model,
    prompt: c.prompt,
    system: c.system,
    image: await File(entry.imagePath).readAsBytes(),
    mime: imageMime(entry.imagePath),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(size: Size(1440, 900), minimumSize: Size(1200, 720), center: true, titleBarStyle: TitleBarStyle.hidden),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  // 设置放在「文档\NLaptXD」;设了 NLAPTXD_HOME 就用它(试用时不碰真实设置)。
  final override = Platform.environment['NLAPTXD_HOME']?.trim() ?? '';
  final home = override.isNotEmpty
      ? Directory(override)
      : Directory('${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}NLaptXD');
  final config = ConfigStore(home);
  await config.load();
  NlColors.useDark(config.config.darkMode);
  final ws = Workspace(
    captioner: () => visionCaptioner(config.config),
    onRootChanged: (path) => config.update(config.config.copyWith(lastRoot: path)),
  );
  final last = config.config.lastRoot;
  if (last.isNotEmpty && Directory(last).existsSync()) {
    try {
      await ws.open(Directory(last));
    } on FileSystemException catch (e) {
      debugPrint('上次的数据集打不开:$e');
    }
  }
  runApp(NlaptApp(config: config, ws: ws));
}
