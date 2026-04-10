import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final scriptPath = Platform.script.toFilePath();
  final projectRoot = p.dirname(p.dirname(scriptPath));
  final backendPath = p.join(
    projectRoot,
    'rust-cli',
    'target',
    'release',
    'vtt-to-lrc-rust',
  );

  if (!File(backendPath).existsSync()) {
    stderr.writeln(
      '错误: 未找到 Rust 后端可执行文件。请先运行: '
      'cargo build --release --manifest-path rust-cli/Cargo.toml',
    );
    exit(5);
  }

  final process = await Process.start(
    backendPath,
    args,
    mode: ProcessStartMode.inheritStdio,
  );

  final exitCode = await process.exitCode;
  exit(exitCode);
}
