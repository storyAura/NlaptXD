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
}
