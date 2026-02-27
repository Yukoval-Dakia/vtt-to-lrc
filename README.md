# vtt-to-lrc

将 WebVTT (.vtt) 字幕文件批量转换为 LRC 歌词格式的 macOS 桌面应用。

## 功能

- 选择文件或目录批量转换
- 拖拽文件/目录直接导入
- 递归扫描子目录
- 操作日志实时显示
- 自动适配深色/浅色模式
- macOS 原生外观 (macos_ui)

## 快速开始

```bash
flutter run -d macos
```

## CLI 模式

```bash
dart run bin/cli.dart file1.vtt file2.vtt
```

不指定文件时，会自动扫描当前目录下的 .vtt 文件。

## 构建发布版

```bash
flutter build macos
```

产物位于 `build/macos/Build/Products/Release/`。

## 项目结构

```
lib/
├── main.dart              # GUI 入口
├── app.dart               # MacosApp 配置
├── core/
│   ├── vtt_converter.dart # VTT→LRC 转换逻辑
│   └── file_scanner.dart  # 文件扫描
└── ui/
    ├── home_page.dart     # 主页面
    ├── log_view.dart      # 日志组件
    └── drop_overlay.dart  # 拖拽浮层
bin/
└── cli.dart               # Dart CLI 入口
