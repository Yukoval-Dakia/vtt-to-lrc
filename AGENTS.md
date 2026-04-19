# AGENTS.md

> 本文件供 AI 编程助手阅读。项目所有注释、文档与 UI 文案均使用简体中文。

## 项目概述

`vtt-to-lrc` 是一个 **Flutter GUI + Rust 后端** 的 macOS 桌面应用，用于将 WebVTT (`.vtt`) 字幕文件批量转换为 LRC (`.lrc`) 歌词格式。同时提供一个 Dart CLI 薄包装，可以从命令行驱动 Rust 后端。

### 分工

- **Flutter**：macOS 图形界面、文件选择 / 拖拽、进度与日志展示。
- **Rust CLI (`rust-cli/`)**：目录扫描、编码检测、VTT 解析、LRC 输出。
- **Dart CLI (`bin/cli.dart`)**：定位并执行 Rust 可执行文件，不做业务逻辑。

### 主要功能

- 文件选择或目录递归扫描批量转换
- 拖拽文件/目录直接导入（`desktop_drop`）
- 实时操作日志与进度显示
- 自动检测多种文件编码（UTF-8 / ASCII / GBK / Windows-1252 / Latin1）
- 自动适配 macOS 深色/浅色模式
- 原生 macOS 外观（`macos_ui`）

---

## 技术栈

| 层级 | 技术 |
|------|------|
| GUI 框架 | Flutter (SDK ^3.11.0) |
| 平台 | macOS（已配置 `macos/` 原生工程，当前只打包 arm64 Rust 后端） |
| UI 库 | `macos_ui: ^2.1.4` |
| 状态管理 | 自定义 `ChangeNotifier`（`AppState`） |
| 文件选择 | `file_picker: ^8.0.0` |
| 拖拽支持 | `desktop_drop: ^0.5.0` |
| 路径处理 | `path: ^1.9.0` |
| 后端语言 | Rust (edition 2021) |
| Rust 依赖 | `encoding_rs`、`rayon`、`regex`；dev `tempfile` |
| 测试 | `flutter_test` + `flutter_lints: ^6.0.0`；Rust `cargo test` |

> 注：项目已不再使用 `gbk_codec`。GBK/Windows-1252/Latin1 解码改由 Rust 端 `encoding_rs` 负责。

---

## 项目结构

```
lib/
├── main.dart                      # GUI 入口；创建共享 RustBackendService 并注入两个服务
├── app.dart                       # MacosApp 配置、主题、依赖注入
├── services/
│   ├── services.dart              # 统一导出所有服务
│   ├── app_state.dart             # UI 状态管理（ChangeNotifier）
│   ├── conversion_service.dart    # 批量转换业务编排
│   ├── file_picker_service.dart   # 文件/目录选择与拖拽入口
│   ├── log_service.dart           # 日志条目管理
│   └── rust_backend_service.dart  # 调用 Rust 可执行文件的桥接层
└── ui/
    ├── home_page.dart             # 主页面（按钮、进度、日志、拖拽区域、_AppColors）
    ├── log_view.dart              # 可滚动日志列表组件
    └── drop_overlay.dart          # 拖拽时显示的浮层提示

bin/
└── cli.dart                       # Dart CLI：定位 rust-cli/target/release/... 并透传参数

rust-cli/                          # 本地构建的 Rust 后端
├── Cargo.toml
└── src/
    ├── main.rs                    # 入口：scan / convert 两个子命令
    ├── lib.rs                     # pub mod converter; pub mod scanner;
    ├── converter.rs               # VTT 解析、编码检测、并发转换
    └── scanner.rs                 # 递归扫描、路径规范化

assets/
└── backend/
    └── vtt-to-lrc-macos-arm64     # 内嵌到 Flutter 资源中的 Rust 二进制（macOS arm64）

skill-package/
└── vtt-to-lrc/                    # Skill 发布包，含独立的 macOS arm64 二进制和 scripts/convert.sh

test/
└── rust_backend_service_test.dart # 通过 Flutter 调用真实 Rust 后端的集成测试

macos/                             # Flutter macOS 原生工程（Runner、Podfile 等）
```

---

## 构建与运行

### GUI 开发

```bash
flutter run -d macos
```

Flutter 启动时会把 `assets/backend/vtt-to-lrc-macos-arm64` 解压到系统临时目录并 `chmod 755` 后执行。

### CLI

```bash
# 依赖 rust-cli/target/release/vtt-to-lrc-rust（需先 cargo build --release）
dart run bin/cli.dart file1.vtt file2.vtt

# 直接跑 Rust CLI（更常用）
cargo run --release --manifest-path rust-cli/Cargo.toml -- file1.vtt file2.vtt

# 大批量路径可改用输入文件，规避 argv 过长
cargo run --release --manifest-path rust-cli/Cargo.toml -- convert --input-file paths.txt
```

### 构建 macOS 发布版

```bash
flutter build macos
```
产物位于 `build/macos/Build/Products/Release/`。

### Rust 后端构建与资源同步（修改 `rust-cli/` 后必做）

```bash
sh scripts/build-and-sync-rust-backend.sh

# 等价的手工命令：
# cargo build --release --manifest-path rust-cli/Cargo.toml
# cp rust-cli/target/release/vtt-to-lrc-rust assets/backend/vtt-to-lrc-macos-arm64
# chmod +x assets/backend/vtt-to-lrc-macos-arm64
# cp rust-cli/target/release/vtt-to-lrc-rust skill-package/vtt-to-lrc/scripts/vtt-to-lrc-macos-arm64
# chmod +x skill-package/vtt-to-lrc/scripts/vtt-to-lrc-macos-arm64
```

### 测试与静态分析

```bash
flutter analyze        # Dart 静态分析（analysis_options.yaml 引入 flutter_lints）
flutter test           # 运行 test/ 下的集成测试（会真实调用 Rust 二进制）
cargo test --manifest-path rust-cli/Cargo.toml
cargo clippy --manifest-path rust-cli/Cargo.toml --all-targets -- -D warnings
```

---

## 架构设计

### 1. 分层

- **`rust-cli/src/`**：所有核心算法（编码检测、VTT 解析、目录扫描、并发）。纯 Rust，无任何 Flutter 依赖。
- **`lib/services/`**：Dart 服务层。`RustBackendService` 是与 Rust 进程交互的唯一桥梁；`ConversionService`、`FilePickerService` 在其上构造业务流程。
- **`lib/ui/`**：仅负责展示与用户交互，不持有业务逻辑。

### 2. 状态管理

`AppState` 继承 `ChangeNotifier`，管理：
- 已选文件列表 / 目录
- 转换进度（`isConverting`、`convertedCount`、`totalCount`、`currentFile`）
- 拖拽状态 `isDragging`
- 日志条目列表（通过内部持有的 `LogService`）

`HomePage` 通过 `addListener → setState` 监听变更。

### 3. 依赖注入

- `main.dart` 一次性创建 `RustBackendService`，注入给 `FilePickerService` 和 `ConversionService`。这样两个服务共用同一份二进制缓存路径，避免重复解压。
- `VttToLrcApp` 与 `HomePage` 构造函数允许传入任意服务实例，便于测试替换；`HomePage` 也支持注入 `AppState`。
- 即使直接无参构造 `VttToLrcApp`，其内部默认依赖也会复用同一个 `RustBackendService`，不会再生成两份独立后端实例。

### 4. 进程通信协议（Dart ↔ Rust）

Rust 可执行文件接受两个子命令：

- `scan <path...>`：递归扫描路径，stdout 每行一个绝对路径，stderr 每行一条警告。正常退出码 0。
- `convert <file...>`：并发转换。stdout 每行 `Converted: <dst>`；stderr 每行 `Failed: <src> -> <error>` 或其它警告；若存在 `Failed:` 则退出码 1，否则 0。
- `scan --input-file <txt>` / `convert --input-file <txt>`：从文本文件读取路径列表，每行一个路径，供大批量输入时使用。

`RustBackendService` 在 Dart 侧解析：
- stdout 只匹配 `Converted: ` 前缀。
- stderr 匹配 `Failed: X -> Y` 变为 `ConvertResult.failure`；**其他 stderr 行视为警告**，通过 `onWarning` 回调透传给 UI（而非抛异常），只有当进程完全没有返回任何成功/失败结果时，才作为 `RustBackendException` 抛出。

### 5. 并发

- Rust 端使用 `rayon` + `ThreadPoolBuilder`，worker 数根据当前机器 `available_parallelism()` 动态计算，并限制上限为 `8`（见 `rust-cli/src/converter.rs`）。
- Dart 端不再做任何并发，只是启动 Rust 进程并读取 stdout/stderr 流。

### 6. 编码检测优先级（Rust 端，`converter.rs::detect_and_decode`）

1. UTF-8 BOM (`EF BB BF`)
2. 合法 UTF-8
3. 纯 ASCII
4. GBK（基于字节范围启发式 + `encoding_rs` 校验）
5. Windows-1252
6. Latin1（兜底）

---

## 代码风格规范

1. **注释语言**：所有代码注释、日志、UI 文案、错误信息一律使用简体中文。
2. **Dart lint**：基于 `flutter_lints`，无自定义禁用。
3. **Rust lint**：对 `cargo clippy -D warnings` 零告警。
4. **UI 颜色**：语义色集中在 `lib/ui/app_colors.dart` 的 `AppColors`；`lib/ui/home_page.dart` 内的 `_AppColors` 只保留主题相关背景和文本色。
5. **异常处理**：
   - 服务层自定义 Exception：`ConversionException`、`FilePickerException`、`RustBackendException`。
   - 单文件失败包装为 `ConvertResult.failure`，不直接抛到 UI。
   - Rust stderr 上的非 `Failed:` 警告通过 `onWarning` 传递，不中断转换。
6. **路径**：`rust_backend_service.dart` 使用 `p.normalize(p.absolute(path))` 统一规范化，避免 `./` 与相对路径误匹配结果。

---

## 测试策略

- **Rust 单元测试**：
  - `rust-cli/src/converter.rs` 内 `#[cfg(test)] mod tests`：覆盖 `clean_vtt_text`、`vtt_time_to_lrc`、`detect_encoding`、`detect_and_decode`、`parse_vtt_content`、`convert_vtt_to_lrc`、`convert_files_parallel`。
  - `rust-cli/src/scanner.rs` 内 `#[cfg(test)] mod tests`：覆盖 `collect_vtt_from_paths`、最大深度、`to_absolute_path` 规范化。
- **Flutter 集成测试**：
  - `test/rust_backend_service_test.dart` 启动真实 Rust 二进制，覆盖 scan + convert 全链路（含 UTF-8 BOM、GBK、HTML 标签、无效时间戳）。
  - 包含回归测试：当传入路径中含有不存在文件时，成功结果不应被 stderr 警告吞掉，且应通过 `onWarning` 传出。
- **新增代码建议**：
  - 改动 Rust 核心请加同文件的单元测试。
  - 改动 `RustBackendService` 的解析/警告语义请扩展 `test/rust_backend_service_test.dart`。
  - 纯 Dart 服务（`ConversionService`、`FilePickerService` 等）目前无单元测试，鼓励新增。

---

## 安全与边界

1. **扫描深度**：Rust `DEFAULT_MAX_DEPTH = 10`（见 `rust-cli/src/scanner.rs`）。超过会写入警告并跳过。
2. **符号链接**：Rust 扫描使用 `fs::symlink_metadata`，`FileType::is_file() / is_dir()` 判断会自动跳过符号链接，防止循环。
3. **编码歧义**：GBK 与 Latin1 字节范围重叠，存在极小概率的歧义，测试已接受此固有局限。
4. **进程参数长度**：`RustBackendService` 会在路径数量或参数总长度超过阈值时自动切换到 `--input-file` 协议，降低触发 macOS `ARG_MAX` 的风险。
5. **架构限制**：`RustBackendService._ensureExecutable` 仅支持 macOS arm64。Intel Mac 会抛 `RustBackendException`。
6. **无网络 / 无持久化**：纯本地离线工具，不存在外部 API、用户认证、敏感数据等风险面。

---

## 修改代码时的注意点

- **改动 Rust 核心（`rust-cli/`）后**，优先运行 `sh scripts/build-and-sync-rust-backend.sh` 同步 `assets/backend/vtt-to-lrc-macos-arm64`（GUI 依赖）和 `skill-package/vtt-to-lrc/scripts/vtt-to-lrc-macos-arm64`（Skill 发布依赖）。两份二进制若不同步，GUI 与 Skill 会表现不一致。
- **改动 Dart/Rust 进程协议**（stdout/stderr 行格式）需同时更新 `rust-cli/src/main.rs` 与 `lib/services/rust_backend_service.dart`，并扩展 `test/rust_backend_service_test.dart`。
- **新增语义色** 请在 `lib/ui/app_colors.dart` 中集中定义；若是主题相关背景/文本色，再放入 `_AppColors`。
- **新增服务类** 请在 `lib/services/services.dart` 中 `export`；若需在 UI 前构造，走 `main.dart` 的依赖注入链。
- **改动 CLI 行为** 请保持 `bin/cli.dart` 退出码与 Rust 后端一致（失败 1、未找到二进制 5）；Rust `main.rs` 中失败返回 1、IO 返回 3、线程池失败 4。
