import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/ui/core/select.dart';

void main() {
  testWidgets('opens below the field, picks an option and closes', (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 240,
            child: NlSelect<String?>(value: null, hint: '选一个', items: const [('a', '甲'), ('b', '乙')], onChanged: (v) => picked = v),
          ),
        ),
      ),
    ));
    expect(find.text('甲'), findsNothing);

    await tester.tap(find.text('选一个'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('甲')).dy, greaterThan(tester.getBottomLeft(find.text('选一个')).dy));

    await tester.tap(find.text('乙'));
    await tester.pumpAndSettle();
    expect(picked, 'b');
    expect(find.text('甲'), findsNothing);
  });

  testWidgets('the menu lines up with the field instead of sliding towards the middle of the window', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: SizedBox(
            width: 110,
            child: NlSelect<int>(value: 2, items: const [(1, '1 张'), (2, '2 张')], onChanged: (_) {}),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('2 张'));
    await tester.pumpAndSettle();
    final field = tester.getRect(find.byType(NlSelect<int>));
    final option = tester.getRect(find.text('1 张'));
    expect(option.left, greaterThanOrEqualTo(field.left));
    expect(option.right, lessThanOrEqualTo(field.right));
  });

  testWidgets('a narrow field with a list taller than the menu still opens and picks', (tester) async {
    int? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 110,
            child: NlSelect<int>(
              value: 20,
              items: [for (final n in const [1, 2, 4, 8, 12, 16, 20, 32]) (n, '$n 张')],
              onChanged: (n) => picked = n,
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('20 张'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('4 张'));
    await tester.pumpAndSettle();
    expect(picked, 4);
  });
}
