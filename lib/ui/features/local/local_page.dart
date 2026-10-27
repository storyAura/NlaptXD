import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../../data/config_store.dart';
import 'local_section.dart';
import 'local_store.dart';

/// 「本地模型」页:下载、运行时、选用。和「模型」页的 API 接口分开放。
class LocalPage extends StatelessWidget {
  const LocalPage({super.key, required this.local, required this.config});

  final LocalStore local;
  final ConfigStore config;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      NlBar(
        children: [
          const Text('本地模型', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Text('llama.cpp · Florence-2', style: TextStyle(fontSize: 11.5, color: NlColors.slate500)),
        ],
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: LocalSection(local: local, config: config),
            ),
          ),
        ),
      ),
    ],
  );
}
