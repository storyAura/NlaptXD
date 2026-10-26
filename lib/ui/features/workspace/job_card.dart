import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'workspace.dart';

String _dur(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// 右下角的批量推标进度卡:滑入、进度条缓动;「后台运行」收成一颗小药丸。
class JobCard extends StatefulWidget {
  const JobCard({super.key, required this.ws});

  final Workspace ws;

  @override
  State<JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<JobCard> {
  // 已用时间每秒走一格;进度本身跟着 Workspace 的通知刷新。
  late final _tick = Timer.periodic(const Duration(seconds: 1), (_) {
    if (mounted && widget.ws.job != null) setState(() {});
  });

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.ws.job;
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.sheet),
      switchInCurve: Motion.enter,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(position: Tween(begin: const Offset(0, .25), end: Offset.zero).animate(a), child: c),
      ),
      child: j == null
          ? const SizedBox.shrink()
          : j.hidden
          ? _mini(j)
          : _full(j),
    );
  }

  Widget _mini(InferJob j) => Bouncy(
    key: const ValueKey('mini'),
    child: GestureDetector(
      onTap: () => widget.ws.setJobHidden(false),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: NlColors.card,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: NlColors.border),
            boxShadow: [BoxShadow(color: NlColors.shadow, blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, value: j.progress, color: NlColors.primary)),
              const SizedBox(width: 8),
              Text('${j.title} · ${j.done}/${j.list.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _full(InferJob j) {
    Widget stat(String k, String v) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: TextStyle(fontSize: 10.5, color: NlColors.slate500)),
          Text(v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
    return Container(
      key: const ValueKey('full'),
      width: 320,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NlColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NlColors.border),
        boxShadow: [BoxShadow(color: NlColors.shadow, blurRadius: 40, offset: const Offset(0, 16))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(j.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${(j.progress * 100).round()}%', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: j.progress),
              duration: Motion.of(context, Motion.base),
              curve: Motion.swift,
              builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 6, color: NlColors.primary, backgroundColor: NlColors.slate100),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              stat('进度', '${j.done}/${j.list.length}'),
              stat('速度', '${j.perMinute.toStringAsFixed(1)} 张/分'),
              stat('已用', _dur(DateTime.now().difference(j.started))),
              stat('剩余', _dur(j.remaining)),
            ],
          ),
          if (j.failed > 0) ...[
            const SizedBox(height: 8),
            Tooltip(
              message: j.lastError ?? '',
              child: Text('${j.failed} 张失败,原文保留', style: TextStyle(fontSize: 11.5, color: NlColors.diffDelText)),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              NlButton(label: '后台运行', icon: Icons.visibility_off_outlined, tone: Tone.outline, onPressed: () => widget.ws.setJobHidden(true)),
              const Spacer(),
              NlButton(
                label: j.cancelled ? '正在取消…' : '取消推标',
                tone: Tone.danger,
                onPressed: j.cancelled ? null : widget.ws.cancelJob,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
