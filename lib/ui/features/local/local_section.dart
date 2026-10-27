import 'package:flutter/material.dart';

import 'package:file_selector/file_selector.dart';

import '../../../core/local/caption_catalog.dart';
import '../../../core/local/cl_tagger.dart';
import '../../../core/local/llama_server.dart';
import '../../../data/config_store.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'local_store.dart';

String _gb(int bytes) => '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';

/// 「本地模型」页的内容:llama.cpp 运行时与服务,模型清单(按系列),下载 / 删除 / 选用。
class LocalSection extends StatelessWidget {
  const LocalSection({super.key, required this.local, required this.config});

  final LocalStore local;
  final ConfigStore config;

  void _say(BuildContext context, String? problem, String ok) {
    if (context.mounted) showToast(context, problem ?? ok, warn: problem != null);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: local,
    builder: (context, _) {
      final series = [...{for (final m in captionModels) m.series}];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Label('下载来源', trailing: Align(
            alignment: Alignment.centerRight,
            child: Seg<String>(
              value: local.source,
              onChanged: (s) => local.update(() => local.source = s),
              items: const [('mirror', '国内镜像', null), ('huggingface', 'HuggingFace', null)],
            ),
          )),
          _runtime(context),
          const SizedBox(height: 10),
          _TaggerCard(local: local, config: config, say: (p, ok) => _say(context, p, ok)),
          const SizedBox(height: 10),
          for (final s in series) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 6, 0, 6),
              child: Text(s, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: NlColors.slate500)),
            ),
            for (final m in captionModels.where((m) => m.series == s)) _ModelRow(local: local, model: m, say: (p, ok) => _say(context, p, ok)),
          ],
        ],
      );
    },
  );

  Widget _runtime(BuildContext context) {
    final ready = local.serverExe != null;
    final progress = local.progressOf('runtime');
    final running = local.server.running;
    return NlCard(
      child: Row(
        children: [
          Icon(Icons.terminal, size: 16, color: NlColors.slate700),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('llama.cpp $llamaCppTag · Vulkan', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text(
                  running
                      ? '服务运行中 · ${local.server.baseUrl}'
                      : ready
                      ? '已就绪 · 推理时自动启动'
                      : '第一次用 GGUF 模型时自动下载(${_gb(llamaRuntimeSize)})',
                  style: TextStyle(fontSize: 11.5, color: running ? NlColors.accent : NlColors.slate500),
                ),
              ],
            ),
          ),
          if (progress != null)
            _Progress(progress: progress, onCancel: () => local.cancelDownload('runtime'))
          else if (!ready)
            NlButton(label: '下载', icon: Icons.download_outlined, tone: Tone.outline, onPressed: () async {
              final problem = await local.downloadRuntime();
              if (context.mounted) _say(context, problem, 'llama.cpp 已就绪');
            })
          else if (running)
            NlButton(label: '停止服务', icon: Icons.stop_circle_outlined, tone: Tone.outline, onPressed: local.stopServer)
          else
            NlButton(
              label: local.starting ? '启动中…' : '启动服务',
              icon: Icons.play_arrow_rounded,
              tone: Tone.outline,
              busy: local.starting,
              onPressed: local.picked == null || local.picked!.florence
                  ? null
                  : () async {
                      final problem = await local.startServer();
                      if (context.mounted) _say(context, problem, '本地服务已就绪');
                    },
            ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({super.key, required this.progress, required this.onCancel});

  final Progress progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final p = progress.total == null || progress.total == 0 ? null : (progress.received / progress.total!).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 110,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: p ?? 0),
              duration: Motion.base,
              builder: (_, v, _) => LinearProgressIndicator(value: p == null ? null : v, minHeight: 5, color: NlColors.primary, backgroundColor: NlColors.slate100),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(p == null ? '下载中' : '${(p * 100).toStringAsFixed(0)}%', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
        NlIconButton(Icons.close, tooltip: '取消(已下的部分保留,可续传)', onPressed: onCancel),
      ],
    );
  }
}

/// CL Tagger v2.01a:CHA 角色卡「识别角色」用。受限模型,要 HuggingFace Token;也可以指向已经下好的文件夹。
class _TaggerCard extends StatefulWidget {
  const _TaggerCard({required this.local, required this.config, required this.say});

  final LocalStore local;
  final ConfigStore config;
  final void Function(String? problem, String ok) say;

  @override
  State<_TaggerCard> createState() => _TaggerCardState();
}

class _TaggerCardState extends State<_TaggerCard> {
  LocalStore get local => widget.local;
  ConfigStore get config => widget.config;
  void say(String? problem, String ok) => widget.say(problem, ok);

  // 下载进度一跳页面就重画,控制器放在这里,输入时光标才不乱跳。
  late final _token = TextEditingController(text: config.config.hfToken);

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _pickDir() async {
    final dir = await getDirectoryPath(confirmButtonText: '选择');
    if (dir != null) say(local.useTaggerDir(dir), 'CL Tagger 已就绪');
  }

  @override
  Widget build(BuildContext context) {
    final ready = local.taggerReady;
    final progress = local.progressOf('tagger');
    return NlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.face_retouching_natural_outlined, size: 16, color: NlColors.slate700),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('角色识别 · CL Tagger v2.01a', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    Text(
                      ready ? '已就绪 · ${local.clTaggerDir}' : 'CHA 角色卡识别角色名 / 作品名 · 约 ${_gb(clTaggerSize)}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: ready ? NlColors.accent : NlColors.slate500),
                    ),
                  ],
                ),
              ),
              if (progress != null)
                _Progress(progress: progress, onCancel: () => local.cancelDownload('tagger'))
              else ...[
                NlButton(label: ready ? '换文件夹' : '选已下好的', icon: Icons.folder_open_outlined, tone: Tone.ghost, onPressed: _pickDir),
                if (!ready) ...[
                  const SizedBox(width: 6),
                  NlButton(
                    label: '下载',
                    icon: Icons.download_outlined,
                    tone: Tone.outline,
                    onPressed: () async => say(await local.downloadTagger(config.config.hfToken), 'CL Tagger 已就绪'),
                  ),
                ],
              ],
            ],
          ),
          if (!ready) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _token,
              obscureText: true,
              style: const TextStyle(fontSize: 12.5),
              decoration: fieldDecoration('HuggingFace Token(先在模型页同意条款:huggingface.co/$clTaggerRepo)', icon: Icons.key_outlined),
              onChanged: (v) => config.update(config.config.copyWith(hfToken: v.trim())),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.local, required this.model, required this.say});

  final LocalStore local;
  final CaptionModel model;
  final void Function(String? problem, String ok) say;

  @override
  Widget build(BuildContext context) {
    final m = model;
    final installed = local.installed(m);
    final picked = local.pick == m.id;
    final progress = local.progressOf(m.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: NlCard(
        borderColor: picked ? NlColors.primaryBorder : null,
        color: picked ? NlColors.primaryBg : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: '  ${m.note}', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
                  ]), overflow: TextOverflow.ellipsis),
                ),
                if (m.florence) const Padding(padding: EdgeInsets.only(left: 6), child: Pill('ONNX')),
                if (picked) const Padding(padding: EdgeInsets.only(left: 6), child: Pill('当前', tone: PillTone.blue)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (m.quants.length > 1)
                  Flexible(
                    child: Wrap(spacing: 4, runSpacing: 4, children: [
                      for (final q in m.quants)
                        NlChip(
                          label: q.recommended ? '${q.label} ★' : q.label,
                          selected: local.quantOf(m).label == q.label,
                          onTap: progress != null ? null : () => local.pickQuant(m, q.label),
                        ),
                    ]),
                  )
                else
                  Pill(local.quantOf(m).label),
                const SizedBox(width: 8),
                Text(_gb(local.sizeOf(m)), style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
                const Spacer(),
                AnimatedSwitcher(
                  duration: Motion.base,
                  child: progress != null
                      ? _Progress(key: const ValueKey('p'), progress: progress, onCancel: () => local.cancelDownload(m.id))
                      : installed
                      ? Row(key: const ValueKey('ok'), mainAxisSize: MainAxisSize.min, children: [
                          if (!picked)
                            NlButton(label: '设为当前', tone: Tone.outline, onPressed: () {
                              local.use(m);
                              say(null, '本地推标 → ${m.name}');
                            }),
                          NlIconButton(Icons.delete_outline, tooltip: '删除这一档', onPressed: () async => say(await local.removeModel(m), '已删除')),
                        ])
                      : NlButton(
                          key: const ValueKey('dl'),
                          label: '下载',
                          icon: Icons.download_outlined,
                          tone: Tone.outline,
                          onPressed: () async => say(await local.downloadModel(m), '已就绪 ${m.name} · SHA256 校验通过'),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
