# NLaptXD

NLapt 的重构版本，与旧仓库 [storyAura/NLapt](https://github.com/storyAura/NLapt) 分开开发。界面改用 Penna 的设计语言。

## 原型

`prototype/` 是可交互的网页原型（单个 HTML，示例数据）。

```powershell
pip install fonttools
python prototype/build.py        # → prototype/dist/nlapt-studio.html
```

- `src.html`：界面与交互源码。改完重新构建。
- `build.py`：把字体按页面实际用到的字裁剪后内嵌，产物约 300 KB，离线可用。
- `fonts/`：Maple Mono、霞鹜 975 圆体（SIL OFL 1.1，来自 Penna）与 Material Icons（Apache 2.0，来自 Flutter SDK），许可证原文同目录。

## 设计来源

- 配色、字体、动效：Penna `lib/ui/core/theme.dart`、`motion.dart`
- 功能与重构分析：「NLapt UI 原型文档」
