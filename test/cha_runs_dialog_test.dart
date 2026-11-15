import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/ui/core/theme.dart';
import 'package:nlaptxd/ui/features/cha/cha_runs_dialog.dart';
import 'package:nlaptxd/ui/features/workspace/workspace.dart';

void main() {
  testWidgets('opens on the newest CHA run, steps back to the older one', (tester) async {
    final ws = Workspace(dataHome: Directory.systemTemp)
      ..chaRuns = [
        (time: DateTime(2026, 11, 15, 9), model: 'old-model', cards: [(name: 'Aoba', series: '', text: 'Aoba has purple hair.', images: <String>[])], written: 3, skipped: 0, failed: 0, cancelled: false),
        (time: DateTime(2026, 11, 16, 9), model: 'new-model', cards: [(name: 'Yun', series: 'NG', text: 'Yun has brown hair.', images: ['a/1.png'])], written: 1, skipped: 2, failed: 0, cancelled: false),
      ];
    await tester.pumpWidget(MaterialApp(
      theme: nlTheme(),
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(onPressed: () => showChaRuns(context, ws), child: const Text('open'))),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 2 次'), findsOneWidget);
    expect(find.text('Yun has brown hair.'), findsOneWidget);
    expect(find.text('1.png'), findsOneWidget);
    await tester.tap(find.byTooltip('上一次'));
    await tester.pumpAndSettle();
    expect(find.text('第 1 / 2 次'), findsOneWidget);
    expect(find.text('Aoba has purple hair.'), findsOneWidget);
    expect(find.textContaining('old-model'), findsOneWidget);
  });
}
