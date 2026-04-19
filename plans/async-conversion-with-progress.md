# 历史归档：异步化转换 + 进度反馈实施计划

本文件对应的是旧阶段的实施草案，已不再代表当前项目架构或当前待办项。

## 当前状态

- 该计划所针对的“同步 Dart 转换核心”方案已经失效。
- 当前项目已经切换为 **Flutter GUI + Rust 后端** 架构。
- GUI 的转换与扫描均通过 `lib/services/rust_backend_service.dart` 调用 `rust-cli/` 完成。
- 当前仍有效的后续修复计划请查看：`/Users/yukoval/.windsurf/plans/remaining-issues-repair-plan-9c7d00.md`

## 保留原因

- 保留此文件仅用于记录历史设计思路。
- 如需继续维护当前项目，请不要再依据本文中的 `lib/core/...`、纯 Dart 转换流程或旧数据流图实施修改。
