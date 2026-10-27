import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/app.dart';
import 'package:nlaptxd/core/llm/translate.dart';
import 'package:nlaptxd/data/app_config.dart';
import 'package:nlaptxd/data/config_store.dart';
import 'package:nlaptxd/ui/features/local/local_store.dart';
import 'package:nlaptxd/ui/features/workspace/workspace.dart';

// 界面测试里时间是假的、网络被替换,所以这里不打真接口:翻译器本身在 core/translate_test.dart 里测。
void main() {
  late Directory home;
  late Directory data;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('nlx_tr_home');
    data = await Directory.systemTemp.createTemp('nlx_tr_data');
    File('${data.path}/10_aoba/a.png').createSync(recursive: true);
    File('${data.path}/10_aoba/a.txt').writeAsStringSync('purple hair, smile');
  });
  tearDown(() async {
    await home.delete(recursive: true);
    await data.delete(recursive: true);
  });

  Future<Workspace> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final config = ConfigStore(home);
    // 选了「大模型」却没选文本模型:翻译一定失败,并说明去哪设置。
    await tester.runAsync(() => config.update(const AppConfig(translate: TranslateSettings(service: TranslateService.llm))));
    final ws = Workspace();
    await tester.runAsync(() => ws.open(data));
    await tester.pumpWidget(NlaptApp(config: config, ws: ws, local: LocalStore(home), windowChrome: false));
    await tester.pumpAndSettle();
    return ws;
  }

  testWidgets('translate menu without a configured service says where to set it up; so does the gloss', (tester) async {
    await pump(tester);
    await tester.tap(find.text('翻译'));
    await tester.pumpAndSettle();
    expect(find.text('整篇译成日本語'), findsOneWidget);
    await tester.tap(find.text('整篇译成中文'));
    await tester.pumpAndSettle();
    expect(find.textContaining('翻译设置'), findsOneWidget);

    await tester.tap(find.text('译文'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.textContaining('译文 · 中文'), findsOneWidget);
    expect(find.textContaining('文本模型'), findsWidgets);
  });

  testWidgets('a translation previews under the editor, and accepting writes it with a translate history label', (tester) async {
    final ws = await pump(tester);
    ws.proposeTranslation('紫色头发, 微笑', '翻译为中文');
    await tester.pumpAndSettle();
    expect(find.text('翻译结果'), findsOneWidget);
    expect(find.text('推理结果'), findsNothing, reason: '右栏不重复显示');
    await tester.tap(find.text('采纳'));
    await tester.pumpAndSettle();
    expect(ws.textOf(ws.entry!), '紫色头发, 微笑');
    expect(ws.history!.entries.last.label, '翻译为中文');
    expect(find.text('翻译结果'), findsNothing);
  });
}
