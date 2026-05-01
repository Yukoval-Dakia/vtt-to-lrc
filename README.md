# vtt-to-lrc

将 WebVTT (.vtt) 字幕文件批量转换为 LRC 歌词格式的 macOS 桌面应用。

当前架构为 Flutter GUI + Rust 后端：
- Flutter 负责 macOS 图形界面、文件选择、日志和进度展示
- Rust 负责目录扫描、编码检测、VTT 解析和 LRC 输出
- Dart CLI 入口仅作为 Rust 后端的薄包装

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

该入口会直接调用 `rust-cli/target/release/vtt-to-lrc-rust`，并在需要时自动切换到 `--input-file` 协议，降低大批量路径触发参数长度上限的风险。

## Rust CLI

```bash
cargo run --manifest-path rust-cli/Cargo.toml -- file1.vtt file2.vtt

# 大批量路径可改用输入文件
cargo run --manifest-path rust-cli/Cargo.toml -- convert --input-file paths.txt
```

- 默认保持当前 Dart CLI 的核心行为：目录参数递归扫描、当前目录默认非递归扫描；输出 `.lrc` 时会剥掉 `.vtt` 以及紧邻的一层扩展名（如 `song.wav.vtt` → `song.lrc`）
- Flutter GUI 当前也通过该 Rust 后端完成扫描和转换
- 运行 Rust CLI 需要本机已安装 Rust toolchain

## 后端资源同步

Flutter GUI 运行时会从 `assets/backend/vtt-to-lrc-macos-arm64` 解压 Rust 后端二进制并执行。

如果修改了 `rust-cli/` 代码，需要重新构建并同步资源：

```bash
sh scripts/build-and-sync-rust-backend.sh
```

等价的手工命令为：

```bash
cargo build --release --manifest-path rust-cli/Cargo.toml
cp rust-cli/target/release/vtt-to-lrc-rust assets/backend/vtt-to-lrc-macos-arm64
chmod +x assets/backend/vtt-to-lrc-macos-arm64
cp rust-cli/target/release/vtt-to-lrc-rust skill-package/vtt-to-lrc/scripts/vtt-to-lrc-macos-arm64
chmod +x skill-package/vtt-to-lrc/scripts/vtt-to-lrc-macos-arm64
```

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
├── services/
│   ├── rust_backend_service.dart # 调用 Rust 二进制的桥接层
│   ├── conversion_service.dart   # GUI 转换编排
│   └── file_picker_service.dart  # 文件/目录选择与扫描入口
└── ui/
    ├── home_page.dart     # 主页面
    ├── log_view.dart      # 日志组件
    └── drop_overlay.dart  # 拖拽浮层
bin/
└── cli.dart               # Dart CLI 包装器，转调 Rust 后端
assets/
└── backend/
    └── vtt-to-lrc-macos-arm64 # Flutter GUI 打包的 Rust 二进制
rust-cli/
├── Cargo.toml             # Rust CLI 包定义
└── src/
    ├── main.rs            # Rust CLI 入口
    ├── converter.rs       # VTT→LRC 核心转换逻辑
    └── scanner.rs         # 目录扫描与路径收集
```
