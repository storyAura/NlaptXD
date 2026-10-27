import 'package:flutter/material.dart';

import '../../../data/config_store.dart';
import '../../core/look_switcher.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.config});

  final ConfigStore config;

  @override
  Widget build(BuildContext context) {
    Widget row(String k, Widget v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(k, style: TextStyle(fontSize: 12.5, color: NlColors.slate500))),
          Expanded(child: Align(alignment: Alignment.centerLeft, child: v)),
        ],
      ),
    );
    Widget section(IconData icon, String title, List<Widget> rows) => NlCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 16), const SizedBox(width: 6), Text(title, style: const TextStyle(fontWeight: FontWeight.w600))]),
          for (final (i, r) in rows.indexed) ...[if (i > 0) Divider(height: 1, color: NlColors.border), r],
        ],
      ),
    );
    const text = TextStyle(fontSize: 12.5);
    return ListenableBuilder(
      listenable: config,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const NlBar(children: [Text('设置', style: TextStyle(fontWeight: FontWeight.w600))]),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      children: [
                        PopIn(
                          child: section(Icons.palette_outlined, '外观', [
                            row(
                              '深色模式',
                              Listener(
                                onPointerDown: (e) => lookRevealOrigin = e.position,
                                child: Switch(
                                  value: config.config.darkMode,
                                  onChanged: (v) => config.update(config.config.copyWith(darkMode: v)),
                                ),
                              ),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        PopIn(
                          delay: const Duration(milliseconds: 40),
                          child: section(Icons.info_outline, '关于', [
                            row('版本', const Text('NLaptXD 0.1.0 · 原型', style: text)),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
