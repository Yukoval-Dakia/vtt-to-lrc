import 'dart:io';

import 'package:path/path.dart' as p;

const _backendBinaryName = 'vtt-to-lrc-rust';
const _backendPathEnvKey = 'VTT_TO_LRC_BACKEND';

Future<void> main(List<String> args) async {
  final backendPath = _resolveBackendPath();

  if (backendPath == null) {
    stderr.writeln(
      '错误: 未找到 Rust 后端可执行文件。请先运行: '
      'cargo build --release --manifest-path rust-cli/Cargo.toml，'
      '或通过环境变量 $_backendPathEnvKey 指定可执行文件路径。',
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

String? _resolveBackendPath() {
  final candidatePaths = <String>{};
  final envPath = Platform.environment[_backendPathEnvKey]?.trim();

  if (envPath != null && envPath.isNotEmpty) {
    candidatePaths.add(p.normalize(p.absolute(envPath)));
  }

  candidatePaths.addAll(_buildRelativeCandidates(Directory.current.path));

  try {
    final scriptPath = Platform.script.toFilePath();
    final scriptRoot = p.dirname(p.dirname(scriptPath));
    candidatePaths.addAll(_buildRelativeCandidates(scriptRoot));
  } catch (_) {}

  final executableDir = p.dirname(Platform.resolvedExecutable);
  candidatePaths.add(p.normalize(p.join(executableDir, _backendBinaryName)));
  candidatePaths.addAll(_buildRelativeCandidates(executableDir));

  for (final candidate in candidatePaths) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }

  return null;
}

Iterable<String> _buildRelativeCandidates(String rootPath) sync* {
  yield p.normalize(
    p.join(rootPath, 'rust-cli', 'target', 'release', _backendBinaryName),
  );
  yield p.normalize(
    p.join(rootPath, '..', 'rust-cli', 'target', 'release', _backendBinaryName),
  );
}
