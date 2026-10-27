import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nlaptxd/app.dart';
import 'package:nlaptxd/core/json_caption.dart';
import 'package:nlaptxd/data/config_store.dart';
import 'package:nlaptxd/ui/features/local/local_store.dart';
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
    try {
      await data.delete(recursive: true);
    } on FileSystemException {
      // 读过文件头(ImmutableBuffer.fromFilePath)的图,Windows 上要等回收才放开,删不掉就留在临时目录。
    }
  });

  Future<Workspace> pump(WidgetTester tester, {bool open = true}) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final config = ConfigStore(home);
    final ws = Workspace(dataHome: home);
    if (open) await tester.runAsync(() => ws.open(data));
    await tester.pumpWidget(NlaptApp(config: config, ws: ws, local: LocalStore(home), windowChrome: false));
    await tester.pumpAndSettle();
    return ws;
  }

  testWidgets('JSON view: summary and item cards, boxes on the preview pick the card', (tester) async {
    File('${data.path}/10_aoba/a.png').writeAsBytesSync(img.encodePng(img.Image(width: 200, height: 100)));
    File('${data.path}/10_aoba/a.txt').writeAsStringSync(
      const MossLayout(caption: 'A girl by the sea.', items: [MossItem(label: 'character', caption: 'Aoba waves.', bbox: [-50, -100, 50, 0])]).toJson(),
    );
    final ws = await pump(tester);
    ws.setView(mode: EditMode.json);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200))); // 读图片文件头
    await tester.pumpAndSettle();
    expect(find.text('A girl by the sea.'), findsOneWidget);
    expect(find.text('Aoba waves.'), findsOneWidget);
    // 测试里图片不真的解码(图是 0×0,框点不到),直接按框的点击。
    tester.widget<GestureDetector>(find.ancestor(of: find.text('1 人物'), matching: find.byType(GestureDetector)).first).onTap!();
    await tester.pumpAndSettle();
    expect(ws.box, 0);
    // 文本视图不画框。
    ws.setView(mode: EditMode.text);
    await tester.pumpAndSettle();
    expect(find.text('1 人物'), findsNothing);
  });

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

  testWidgets('the chip toolbar never covers the editor header and leaves with the page', (tester) async {
    await pump(tester);
    await tester.tap(find.text('purple hair'));
    await tester.pumpAndSettle();
    final header = tester.getRect(find.text('胶囊'));
    final toolbar = tester.getRect(find.text('插入'));
    expect(toolbar.top, greaterThan(header.bottom), reason: 'first-row chip: toolbar flips below');
    await tester.tap(find.byTooltip('操作日志'));
    await tester.pumpAndSettle();
    expect(find.text('插入'), findsNothing);
  });

  testWidgets('inferring without a model explains where to set one up', (tester) async {
    await pump(tester);
    await tester.tap(find.text('推标当前图片'));
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有视觉模型'), findsOneWidget);
  });

  testWidgets('right-click offers infer scopes; without a model it says so before asking to overwrite', (tester) async {
    await pump(tester);
    await tester.tap(find.text('b.png').first, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    for (final t in ['推标这张图片', '推标此文件夹', '推标此文件夹里未标注的', '推标全部', '复制标注']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await tester.tap(find.text('推标全部'));
    await tester.pumpAndSettle();
    expect(find.textContaining('覆盖'), findsNothing);
    expect(find.textContaining('还没有视觉模型'), findsOneWidget);
  });

  /// 一个部件实际画出来的透明度(所有祖先 FadeTransition 相乘)。
  double opacityOf(WidgetTester tester, Finder f) => tester
      .widgetList<FadeTransition>(find.ancestor(of: f, matching: find.byType(FadeTransition)))
      .fold(1.0, (o, w) => o * w.opacity.value);

  testWidgets('the rail switches pages and the old page fades out completely', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('操作日志'));
    await tester.pumpAndSettle();
    expect(find.text('还没有批量操作'), findsOneWidget);
    await tester.tap(find.byTooltip('模型'));
    await tester.pumpAndSettle();
    expect(find.text('添加接口'), findsOneWidget);
    expect(opacityOf(tester, find.text('添加接口')), 1);
    // 回归:TickerMode 包在淡出外面时,离开的页停在不透明、透到新页底下
    expect(opacityOf(tester, find.text('推标当前图片')), 0);
    expect(opacityOf(tester, find.text('还没有批量操作')), 0);
  });
}
