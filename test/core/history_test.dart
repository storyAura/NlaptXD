import 'package:flutter_test/flutter_test.dart';
import 'package:nlaptxd/core/history.dart';

void main() {
  test('starts with the opened text and nothing to undo', () {
    final h = CaptionHistory('a');
    expect(h.current.text, 'a');
    expect(h.canUndo, isFalse);
    expect(h.canRedo, isFalse);
  });

  test('push, undo, redo walk the timeline', () {
    final h = CaptionHistory('a')
      ..push('编辑', 'b')
      ..push('编辑', 'c');
    expect(h.undo(), 'b');
    expect(h.undo(), 'a');
    expect(h.canUndo, isFalse);
    expect(h.redo(), 'b');
  });

  test('a new edit after undo drops the future branch', () {
    final h = CaptionHistory('a')
      ..push('x', 'b')
      ..push('x', 'c');
    h.undo();
    h.push('y', 'd');
    expect(h.canRedo, isFalse);
    expect(h.entries.map((e) => e.text), ['a', 'b', 'd']);
  });

  test('pushing the current text again is a no-op', () {
    final h = CaptionHistory('a')..push('x', 'a');
    expect(h.entries, hasLength(1));
  });

  test('jumpTo moves the cursor without deleting entries', () {
    final h = CaptionHistory('a')
      ..push('x', 'b')
      ..push('x', 'c');
    expect(h.jumpTo(0), 'a');
    expect(h.entries, hasLength(3));
    expect(h.cursor, 0);
  });

  test('keeps at most the limit, dropping the oldest', () {
    final h = CaptionHistory('0');
    for (var i = 1; i <= CaptionHistory.limit + 5; i++) {
      h.push('x', '$i');
    }
    expect(h.entries, hasLength(CaptionHistory.limit));
    expect(h.current.text, '${CaptionHistory.limit + 5}');
  });

  test('clear keeps only the current state', () {
    final h = CaptionHistory('a')..push('x', 'b');
    h.clear();
    expect(h.entries.single.text, 'b');
  });
}
