import 'package:flutter/foundation.dart';

@immutable
class HistoryEntry {
  const HistoryEntry(this.time, this.label, this.text);

  final DateTime time;
  final String label;
  final String text;
}

/// 一个文件的逐步历史:带标签的快照 + 当前位置。回退只挪位置不删记录,
/// 在过去的位置上做新编辑时剪掉「未来」那一段。
class CaptionHistory {
  CaptionHistory(String initial, {DateTime? time})
    : _entries = [HistoryEntry(time ?? DateTime.now(), '打开', initial)];

  static const limit = 30;

  final List<HistoryEntry> _entries;
  int _cursor = 0;

  List<HistoryEntry> get entries => List.unmodifiable(_entries);
  int get cursor => _cursor;
  HistoryEntry get current => _entries[_cursor];
  bool get canUndo => _cursor > 0;
  bool get canRedo => _cursor < _entries.length - 1;

  void push(String label, String text) {
    if (text == current.text) return;
    _entries
      ..removeRange(_cursor + 1, _entries.length)
      ..add(HistoryEntry(DateTime.now(), label, text));
    if (_entries.length > limit) _entries.removeAt(0);
    _cursor = _entries.length - 1;
  }

  String undo() => jumpTo(_cursor - 1);
  String redo() => jumpTo(_cursor + 1);

  String jumpTo(int index) {
    _cursor = index.clamp(0, _entries.length - 1);
    return current.text;
  }

  void clear() {
    final keep = current;
    _entries
      ..clear()
      ..add(keep);
    _cursor = 0;
  }
}
