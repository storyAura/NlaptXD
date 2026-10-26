import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/text_io.dart';
import 'app_config.dart';

/// 读写 config.json。[home] 不存在时第一次保存会建出来;读坏了就用默认值,不挡启动。
class ConfigStore extends ChangeNotifier {
  ConfigStore(this.home);

  final Directory home;
  AppConfig _config = const AppConfig();

  AppConfig get config => _config;
  File get _file => File('${home.path}${Platform.pathSeparator}config.json');

  Future<void> load() async {
    try {
      if (await _file.exists()) {
        _config = AppConfig.fromJson(jsonDecode(await _file.readAsString()) as Map<String, dynamic>);
      }
    } on Object catch (e) {
      debugPrint('config.json 读取失败,用默认设置:$e');
    }
  }

  /// 换上新设置并写盘;写盘失败只记日志(界面上已经生效)。
  Future<void> update(AppConfig next) async {
    _config = next;
    notifyListeners();
    try {
      await writeAtomic(_file.path, const JsonEncoder.withIndent('  ').convert(next.toJson()));
    } on FileSystemException catch (e) {
      debugPrint('config.json 写入失败:$e');
    }
  }
}
