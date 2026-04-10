# AGENTS.md

> 本文件供 AI 编程助手阅读。项目所有注释和文档均使用中文。

## 项目概述

`vtt-to-lrc` 是一个基于 Flutter 的 **macOS 桌面应用**，用于将 WebVTT (`.vtt`) 字幕文件批量转换为 LRC (`.lrc`) 歌词格式。项目同时提供一个纯 Dart CLI 入口，支持命令行批量转换。

### 主要功能
- 文件选择或目录递归扫描批量转换
- 拖拽文件/目录直接导入（`desktop_drop`）
- 实时操作日志显示
- 自动检测多种文件编码（UTF-8 / ASCII / GBK / Windows-1252 / Latin1）
- 自动适配 macOS 深色/浅色模式
- 原生 macOS 外观（`macos_ui`）

---

## 技术栈

| 层级 | 技术 |
|------|------|
| 框架 | Flutter (SDK ^3.11.0) |
| 平台 | macOS (已配置 `macos/` 原生工程) |
| UI 库 | `macos_ui: ^2.1.4` |
| 状态管理 | 自定义 `ChangeNotifier`（`AppState`） |
| 文件选择 | `file_picker: ^8.0.0` |
| 拖拽支持 | `desktop_drop: ^0.5.0` |
| 路径处理 | `path: ^1.9.0` |
| 编码支持 | `gbk_codec: ^0.4.0`（中文 GBK 解码） |
| 测试 | `flutter_test` + `flutter_lints: ^6.0.0` |

---

## 项目结构

```
lib/
├── main.dart                  # GUI 入口：runApp(VttToLrcApp)
├── app.dart                   # MacosApp 配置、主题、依赖注入
├── core/
│   ├── vtt_converter.dart     # VTT → LRC 核心转换逻辑、编码检测
│   └── file_scanner.dart      # 目录递归扫描、VTT 文件收集
├── services/
│   ├── services.dart          # 统一导出所有服务
│   ├── app_state.dart         # UI 状态管理（ChangeNotifier）
│   ├── conversion_service.dart # 转换业务逻辑封装
│   ├── file_picker_service.dart # 文件/目录选择、拖拽处理
│   └── log_service.dart       # 日志条目管理
└── ui/
    ├── home_page.dart         # 主页面（按钮、进度、日志、拖拽区域）
    ├── log_view.dart          # 可滚动日志列表组件
    └── drop_overlay.dart      # 拖拽时显示的浮层提示

bin/
└── cli.dart                   # Dart CLI 入口（纯命令行模式）

test/
├── vtt_converter_test.dart    # 转换核心单元测试
└── vtt_file_converter_test.dart # 文件级批量转换测试

macos/                         # Flutter macOS 原生工程
├── Runner/
├── RunnerTests/
└── Pods/                      # CocoaPods 依赖
```

---

## 构建与运行命令

### GUI 开发模式
```bash
flutter run -d macos
```

### CLI 模式
```bash
# 指定文件/目录
dart run bin/cli.dart file1.vtt file2.vtt

# 不指定参数时扫描当前目录
dart run bin/cli.dart
```

### 构建发布版
```bash
flutter build macos
```
发布产物位于 `build/macos/Build/Products/Release/`。

### 运行测试
```bash
flutter test
```

### 静态分析
```bash
flutter analyze
```
分析规则配置在 `analysis_options.yaml`，默认引入 `package:flutter_lints/flutter.yaml`。

---

## 架构设计

### 1. 分层架构
- **`core/`**：纯 Dart 逻辑，不依赖 Flutter，负责文件 I/O、编码检测、VTT 解析、LRC 生成。
- **`services/`**：业务服务层，连接 core 与 UI。`ConversionService`、`FilePickerService` 可注入 mock，便于测试。
- **`ui/`**：仅负责展示，业务逻辑下沉到 services/core。

### 2. 状态管理
- `AppState` 继承 `ChangeNotifier`，管理：
  - 已选文件/目录
  - 转换进度（`isConverting`、`convertedCount`、`totalCount`）
  - 拖拽状态
  - 日志条目
- `HomePage` 监听 `AppState` 并调用 `setState`。

### 3. 依赖注入
- `VttToLrcApp` 和 `HomePage` 的构造函数允许传入可选的 `FilePickerService` 和 `ConversionService`。
- 若未传入，则自动实例化默认实现。这是为了方便在测试中注入 mock。

### 4. 异步与批量处理
- **优先使用异步 API**：`convertVttToLrcAsync`、`convertFilesAsync`。
- 批量转换采用**分批并行**（batch size = 8），通过 `Future.wait` 控制并发，避免大量文件时耗尽 I/O。
- 同步版本（`convertVttToLrc`、`convertFiles`）已标记 `@Deprecated`，仅 CLI 中仍有少量使用。

---

## 代码风格规范

1. **注释语言**：所有代码注释、文档、UI 文案均使用**简体中文**。
2. **lint 规则**：基于 `flutter_lints`，无额外自定义禁用。
3. **颜色常量**：UI 颜色集中在 `HomePage._AppColors` 内部类中，按语义命名（`success`、`error`、`info` 等），并区分深色/浅色主题。
4. **异常处理**：
   - 业务异常使用自定义 Exception（`ConversionException`、`FilePickerException`）。
   - 文件系统异常（`FileSystemException`）在 core 层捕获并包装为 `ConvertResult.failure`，不直接抛到 UI。
5. **编码处理**：`EncodingDetector.detectAndDecode` 的优先级为：
   UTF-8 (含 BOM) → ASCII → GBK → Windows-1252 → Latin1（最终回退）。

---

## 测试策略

- **测试框架**：`flutter_test`
- **测试文件**：
  - `test/vtt_converter_test.dart`：覆盖 `cleanVttText`、`vttTimeToLrc`、`EncodingDetector`、`ConvertResult` 等纯逻辑单元。
  - `test/vtt_file_converter_test.dart`：覆盖完整文件读写、批量转换、进度回调、异常场景（文件不存在、无效时间戳）。
- **测试环境**：使用 `Directory.systemTemp.createTemp` 创建临时目录进行文件 I/O 测试，`tearDownAll` 负责清理。
- **新增代码建议**：core 层的任何修改都应补充对应单元测试；services/ui 层修改应验证集成行为。

---

## 安全与边界注意事项

1. **目录扫描深度限制**：`file_scanner.dart` 中默认最大递归深度为 `10`（`defaultMaxDepth`），防止符号链接或异常深层目录导致栈溢出/长时间阻塞。
2. **符号链接**：扫描时 `followLinks: false`，避免循环链接问题。
3. **编码安全**：GBK 检测使用特征字节范围判断，若字节范围与 Latin1 重叠可能存在歧义，测试已接受这种固有局限性。
4. **路径验证**：CLI 和 services 层均对输入路径做 `FileSystemEntity.typeSync` 检查，过滤不存在的路径。
5. **避免外部依赖风险**：本项目为本地离线工具，无网络请求、无用户认证、无敏感数据持久化。

---

## 快速参考：修改代码时的注意点

- 若改动 `core/vtt_converter.dart`，请同步检查/更新 `test/vtt_converter_test.dart` 和 `test/vtt_file_converter_test.dart`。
- 若新增 UI 颜色，请在 `HomePage._AppColors` 中定义，并同时提供深色/浅色值。
- 若新增服务类，请在 `lib/services/services.dart` 中 `export`，并在 `HomePage` 或 `app.dart` 中按需注入。
- 若改动 CLI 行为，请确保 `bin/cli.dart` 的退出码和错误输出保持一致（失败返回 `exit(1)`，文件系统错误返回 `exit(3)` 等）。
