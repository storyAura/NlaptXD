import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nlaptxd/core/cha_store.dart';
import 'package:nlaptxd/core/dataset.dart';
import 'package:nlaptxd/data/app_config.dart';
import 'package:nlaptxd/ui/core/theme.dart';
import 'package:nlaptxd/ui/features/cha/cha_dialog.dart';
import 'package:nlaptxd/ui/features/local/local_store.dart';

void main() {
  late Directory root;
  late List<ImageEntry> images;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nlx_chadlg');
    final png = img.encodePng(img.Image(width: 8, height: 8));
    images = [
      for (final n in ['1', '2', '3'])
        () {
          final f = File('${root.path}${Platform.pathSeparator}$n.png')
            ..writeAsBytesSync(png);
          return ImageEntry(
            imagePath: f.path,
            txtPath: '${f.path}.txt',
            folder: '',
          );
        }(),
    ];
  });
  // Windows 上测试刚结束时图片可能还被占着,删不掉就留给系统清理。
  tearDown(() => root.delete(recursive: true).catchError((Object _) => root));

  /// 打开 CHA 弹窗(数据集就是 [root])。
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nlTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showChaDialog(
                context,
                config: const AppConfig(),
                local: LocalStore(root),
                images: images,
                root: root,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('add a part, then pick its image from the grid', (tester) async {
    await open(tester);
    expect(find.text('主参考图'), findsOneWidget);
    await tester.tap(find.text('添加部件'));
    await tester.pumpAndSettle();
    expect(find.text('为部件 1选一张图'), findsOneWidget);
    // 网格第二张(选图时图上蒙着一层主色,点击落在那层上,所以不提示没点中)。
    await tester.tap(find.byType(Image).at(1), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('部件 1'), findsOneWidget, reason: '网格里那张标上了序号');
    expect(find.text('主'), findsOneWidget);
    expect(find.text('主参考图'), findsOneWidget, reason: '选完退回主参考图');
  });

  testWidgets(
    'cards saved last time can be reused and go straight to confirm',
    (tester) async {
      await tester.runAsync(
        () => saveChaCards(root, [
          (
            name: 'Si',
            series: 'Arknights',
            text: 'Si from Arknights has green hair. She wears a white dress.',
            ref: images[2].imagePath,
            references: const [],
          ),
        ]),
      );
      await open(tester);
      // 存档是真读磁盘:给它真实时间读完。
      for (
        var i = 0;
        i < 20 && find.textContaining('上次的角色卡').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('上次的角色卡 · Si'), findsOneWidget);
      await tester.tap(find.text('复用'));
      await tester.pumpAndSettle();
      expect(find.text('开始CHA标注'), findsOneWidget);
      expect(find.textContaining('has green hair'), findsWidgets);
    },
  );
}
