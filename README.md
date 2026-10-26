# NLaptXD

NLapt 的重构版本:图片 + 同名 `.txt` 训练集的自然语言标注台。Flutter + Dart 编写的 Windows 桌面应用,界面采用 Penna 的设计语言。与旧仓库 [storyAura/NLapt](https://github.com/storyAura/NLapt) 分开开发。

## 功能(0.1.0 原型)

- 打开数据集文件夹:递归扫描,按同名配对 txt,按 kohya 文件夹分组;记住上次打开的数据集
- 列表 / 网格浏览,搜索文件名与标注,筛选全部 / 未标注 / 未保存,多选与四图对比
- 胶囊、分句、文本三种标注编辑,拖拽排序,触发词锁定显示
- 保存与全部保存(原子写入),逐步历史、撤销与重做
- 批量查找替换、前缀 / 后缀:执行前自动打包快照,可在操作日志整批回滚
- 视觉模型推标(OpenAI 兼容接口):单张结果以红绿对比呈现,采纳后写入;批量推标带进度、后台运行与取消
- 深色模式(圆形扩散切换)

## 开发

```powershell
flutter pub get
dart analyze lib test
flutter test
pwsh tool/build.ps1          # 编译 Windows Release
```

网页原型在 `prototype/`:`pip install fonttools` 后运行 `python prototype/build.py`。

## 致谢与许可

- 字体:Maple Mono、霞鹜 975 圆体(SIL OFL 1.1),Material Icons(Apache 2.0),许可原文在 `fonts/`
