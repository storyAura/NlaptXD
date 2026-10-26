import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/app.dart';
import 'package:nlaptxd/data/config_store.dart';
import 'package:nlaptxd/ui/features/workspace/workspace.dart';

void main() {
  late Directory home;
  late Directory data;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('nlx_home');
    data = await Directory.systemTemp.createTemp('nlx_data');
    File('${data.path}/10_aoba/a.png').createSync(recursive: true);
    File('${data.path}/10_aoba/a.txt').writeAsStringSync('aoba, 1girl, purple hair');
    File('${data.path}/10_aoba/b.png').createSync(recursive: true);
  });
  tearDown(() async {
    await home.delete(recursive: true);
    await data.delete(recursive: true);
  });

  Future<Workspace> pump(WidgetTester tester, {bool open = true}) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final config = ConfigStore(home);
    final ws = Workspace(captioner: () => null);
    if (open) await tester.runAsync(() => ws.open(data));
    await tester.pumpWidget(NlaptApp(config: config, ws: ws, windowChrome: false));
    await tester.pumpAndSettle();
    return ws;
  }

  testWidgets('without a dataset the welcome page offers to open one', (tester) async {
    await pump(tester, open: false);
    expect(find.text('打开数据集文件夹'), findsOneWidget);
  });

  testWidgets('a dataset shows its files, chips and the infer panel', (tester) async {
    await pump(tester);
    expect(find.text('a.png'), findsWidgets);
    expect(find.text('purple hair'), findsOneWidget);
    expect(find.text('推标当前图片'), findsOneWidget);
    expect(find.text('未标注'), findsWidgets);
  });

  testWidgets('removing a chip marks the file unsaved and enables save', (tester) async {
    final ws = await pump(tester);
    await tester.tap(find.text('purple hair'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(ws.textOf(ws.entry!), 'aoba, 1girl');
    expect(find.text('未保存'), findsWidgets);
  });

  testWidgets('inferring without a model explains where to set one up', (tester) async {
    await pump(tester);
    await tester.tap(find.text('推标当前图片'));
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有视觉模型'), findsOneWidget);
  });

  testWidgets('the rail switches to the operation log and models pages', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('操作日志'));
    await tester.pumpAndSettle();
    expect(find.text('还没有批量操作'), findsOneWidget);
    await tester.tap(find.byTooltip('模型'));
    await tester.pumpAndSettle();
    expect(find.text('添加接口'), findsOneWidget);
  });
}
