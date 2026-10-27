import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'data/config_store.dart';
import 'data/legacy_import.dart';
import 'ui/core/theme.dart';
import 'ui/features/local/local_store.dart';
import 'ui/features/workspace/workspace.dart';

/// 关窗前先停 llama-server:Windows 不会替我们关掉子进程(同 Penna)。
class _CloseHook with WindowListener {
  _CloseHook(this.local);

  final LocalStore local;

  @override
  Future<void> onWindowClose() async {
    try {
      await local.stopServer();
    } finally {
      await windowManager.destroy();
    }
  }
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
  // 设置、模型、运行时都放在「文档\NLaptXD」;设了 NLAPTXD_HOME 就用它(试用时不碰真实数据)。
  final override = Platform.environment['NLAPTXD_HOME']?.trim() ?? '';
  final documents = (await getApplicationDocumentsDirectory()).path;
  final home = override.isNotEmpty ? Directory(override) : Directory('$documents${Platform.pathSeparator}NLaptXD');
  final config = ConfigStore(home);
  await config.load();
  // 第一次启动时把旧版 NLapt 的接口、提示词并进来;试用(NLAPTXD_HOME)时不导,免得把真实密钥带进临时目录。
  final appData = Platform.environment['APPDATA'] ?? '';
  if (override.isEmpty && config.config.legacyImport < legacyImportVersion && appData.isNotEmpty) {
    await config.update(await importLegacyFiles(config.config, documents: documents, appData: appData));
  }
  NlColors.useDark(config.config.darkMode);
  final local = LocalStore(home);
  await local.load();
  await windowManager.setPreventClose(true);
  windowManager.addListener(_CloseHook(local));
  final ws = Workspace(dataHome: home, onRootChanged: (path) => config.update(config.config.copyWith(lastRoot: path)));
  final last = config.config.lastRoot;
  if (last.isNotEmpty && Directory(last).existsSync()) {
    try {
      await ws.open(Directory(last));
    } on FileSystemException catch (e) {
      debugPrint('上次的数据集打不开:$e');
    }
  }
  runApp(NlaptApp(config: config, ws: ws, local: local));
}
