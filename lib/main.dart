import 'package:flutter/widgets.dart';

import 'app.dart';
import 'services/services.dart';

void main() {
  // 共享同一个 RustBackendService 实例，避免文件选择器和转换器各自解压
  // Rust 后端二进制（参考代码审查报告，原先会造成重复 I/O 与独立缓存）。
  final rustBackend = RustBackendService();
  runApp(
    VttToLrcApp(
      filePickerService: FilePickerService(rustBackendService: rustBackend),
      conversionService: ConversionService(rustBackendService: rustBackend),
      appState: AppState(),
    ),
  );
}
