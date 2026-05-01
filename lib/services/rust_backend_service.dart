import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Rust 扫描结果
class RustScanResult {
  final List<String> files;
  final List<String> warnings;

  const RustScanResult({
    required this.files,
    required this.warnings,
  });
}

/// Rust 转换结果
class ConvertResult {
  final String source;
  final String? destination;
  final String? error;

  ConvertResult.success(this.source, this.destination) : error = null;
  ConvertResult.failure(this.source, this.error) : destination = null;

  bool get isSuccess => error == null;
}

/// Rust 进度回调类型
typedef ProgressCallback = void Function(
  int current,
  int total,
  ConvertResult? result,
);

/// Rust 警告回调类型（需要提醒用户但不导致转换失败的 stderr 信息）
typedef WarningCallback = void Function(String message);

/// Rust 后端异常
class RustBackendException implements Exception {
  final String message;

  RustBackendException(this.message);

  @override
  String toString() => message;
}

class _RustCommandInvocation {
  final List<String> arguments;
  final String? cleanupDirectoryPath;

  const _RustCommandInvocation({
    required this.arguments,
    this.cleanupDirectoryPath,
  });
}

/// Rust 后端服务
/// 负责解压、调用并解析 Rust 可执行文件
class RustBackendService {
  static const int _defaultMaxInlineArgumentCount = 200;
  static const int _defaultMaxInlineArgumentBytes = 100000;

  RustBackendService({
    int maxInlineArgumentCount = _defaultMaxInlineArgumentCount,
    int maxInlineArgumentBytes = _defaultMaxInlineArgumentBytes,
  }) : _maxInlineArgumentCount = maxInlineArgumentCount < 1
           ? 1
           : maxInlineArgumentCount,
       _maxInlineArgumentBytes = maxInlineArgumentBytes < 1
           ? 1
           : maxInlineArgumentBytes;

  String? _cachedExecutablePath;
  final int _maxInlineArgumentCount;
  final int _maxInlineArgumentBytes;

  /// 扫描路径中的所有 VTT 文件
  Future<RustScanResult> scanPaths(List<String> paths) async {
    if (paths.isEmpty) {
      return const RustScanResult(files: <String>[], warnings: <String>[]);
    }

    final executablePath = await _ensureExecutable();
    final invocation = await _buildCommandInvocation('scan', paths);
    try {
      final result = await Process.run(
        executablePath,
        invocation.arguments,
      );

      final files = _parseOutputLines(result.stdout);
      final warnings = _parseOutputLines(result.stderr);

      if (result.exitCode != 0) {
        final message = warnings.isNotEmpty
            ? warnings.join('\n')
            : 'Rust 扫描进程退出码异常：${result.exitCode}';
        throw RustBackendException(message);
      }

      return RustScanResult(
        files: files,
        warnings: warnings,
      );
    } finally {
      await _cleanupInvocation(invocation);
    }
  }

  /// 批量转换文件
  ///
  /// [onProgress] 会在每个文件完成（成功或失败）时回调。
  /// [onWarning] 会在 Rust stderr 输出非 `Failed:` 前缀的诊断信息时回调（如路径不存在、
  /// 深度超限等）。这类信息不会导致整体转换失败，只作为提醒向 UI 显示。
  Future<List<ConvertResult>> convertFiles(
    List<String> files, {
    ProgressCallback? onProgress,
    WarningCallback? onWarning,
  }) async {
    if (files.isEmpty) {
      return <ConvertResult>[];
    }

    final executablePath = await _ensureExecutable();
    final normalizedFiles = files.map(_normalizePath).toList();
    final invocation = await _buildCommandInvocation('convert', normalizedFiles);
    final results = List<ConvertResult?>.filled(normalizedFiles.length, null);
    final sourceIndex = <String, int>{};
    final destinationIndex = <String, int>{};

    for (var i = 0; i < normalizedFiles.length; i++) {
      final source = normalizedFiles[i];
      sourceIndex[source] = i;
      destinationIndex[_expectedDestination(source)] = i;
    }

    onProgress?.call(0, normalizedFiles.length, null);

    try {
      final process = await Process.start(
        executablePath,
        invocation.arguments,
      );

      var completed = 0;
      final warnings = <String>[];
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              final trimmed = line.trim();
              if (trimmed.isEmpty) return;

              final result = _parseSuccessLine(trimmed, destinationIndex, normalizedFiles);
              if (result == null) {
                return;
              }

              final index = destinationIndex[_normalizePath(result.destination!)];
              if (index == null || results[index] != null) {
                return;
              }

              results[index] = result;
              completed++;
              onProgress?.call(completed, normalizedFiles.length, result);
            },
            onDone: () => stdoutDone.complete(),
            onError: (Object error, StackTrace stackTrace) {
              stdoutDone.completeError(error, stackTrace);
            },
            cancelOnError: true,
          );

      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              final trimmed = line.trim();
              if (trimmed.isEmpty) return;

              final result = _parseFailureLine(trimmed, sourceIndex);
              if (result == null) {
                warnings.add(trimmed);
                onWarning?.call(trimmed);
                return;
              }

              final index = sourceIndex[_normalizePath(result.source)];
              if (index == null || results[index] != null) {
                return;
              }

              results[index] = result;
              completed++;
              onProgress?.call(completed, normalizedFiles.length, result);
            },
            onDone: () => stderrDone.complete(),
            onError: (Object error, StackTrace stackTrace) {
              stderrDone.completeError(error, stackTrace);
            },
            cancelOnError: true,
          );

      final exitCode = await process.exitCode;
      await Future.wait<void>([stdoutDone.future, stderrDone.future]);

      final hasAnyRealResult = results.any((r) => r != null);

      for (var i = 0; i < results.length; i++) {
        if (results[i] == null) {
          results[i] = ConvertResult.failure(
            normalizedFiles[i],
            '转换失败：后端未返回该文件的处理结果',
          );
        }
      }

      final resolvedResults = results.cast<ConvertResult>();

      if (!hasAnyRealResult) {
        if (warnings.isNotEmpty) {
          throw RustBackendException(warnings.join('\n'));
        }
        if (exitCode != 0) {
          throw RustBackendException('Rust 转换进程退出码异常：$exitCode');
        }
      }

      return resolvedResults;
    } finally {
      await _cleanupInvocation(invocation);
    }
  }

  Future<String> _ensureExecutable() async {
    final assetName = await _resolveBackendAssetName();
    final assetPath = 'assets/backend/$assetName';

    if (_cachedExecutablePath != null &&
        await File(_cachedExecutablePath!).exists()) {
      return _cachedExecutablePath!;
    }

    final backendDir = Directory(
      p.join(Directory.systemTemp.path, 'vtt_to_lrc_backend'),
    );
    await backendDir.create(recursive: true);

    final executablePath = p.join(backendDir.path, assetName);
    final bytes = await _loadBackendBytes(assetPath);
    final executableFile = File(executablePath);

    if (await executableFile.exists()) {
      final existingLength = await executableFile.length();
      if (existingLength == bytes.length) {
        final existingBytes = await executableFile.readAsBytes();
        if (_bytesEqual(existingBytes, bytes)) {
          _cachedExecutablePath = executablePath;
          return executablePath;
        }
      }
    }

    await executableFile.writeAsBytes(bytes, flush: true);

    if (!Platform.isWindows) {
      final chmodResult = await Process.run(
        '/bin/chmod',
        ['755', executablePath],
      );
      if (chmodResult.exitCode != 0) {
        final message = chmodResult.stderr.toString().trim();
        throw RustBackendException(
          message.isNotEmpty ? message : '无法设置 Rust 后端可执行权限。',
        );
      }
    }

    _cachedExecutablePath = executablePath;
    return executablePath;
  }

  Future<String> _resolveBackendAssetName() async {
    final os = _resolveOsTag();
    final arch = await _resolveArchTag();
    final suffix = Platform.isWindows ? '.exe' : '';
    return 'vtt-to-lrc-$os-$arch$suffix';
  }

  String _resolveOsTag() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    throw RustBackendException(
      '当前操作系统不受支持：${Platform.operatingSystem}',
    );
  }

  Future<String> _resolveArchTag() async {
    if (Platform.isWindows) {
      final raw =
          (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '').toLowerCase();
      return _normalizeArch(raw);
    }
    final result = await Process.run('uname', ['-m']);
    if (result.exitCode != 0) {
      final message = result.stderr.toString().trim();
      throw RustBackendException(
        message.isNotEmpty ? message : '无法检测 CPU 架构。',
      );
    }
    return _normalizeArch(result.stdout.toString().trim().toLowerCase());
  }

  String _normalizeArch(String raw) {
    switch (raw) {
      case 'arm64':
      case 'aarch64':
        return 'arm64';
      case 'x86_64':
      case 'amd64':
        return 'x64';
      default:
        throw RustBackendException('不支持的 CPU 架构：$raw');
    }
  }

  Future<List<int>> _loadBackendBytes(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (error) {
      throw RustBackendException('无法加载 Rust 后端资源：$error');
    }
  }

  Future<_RustCommandInvocation> _buildCommandInvocation(
    String command,
    List<String> paths,
  ) async {
    if (!_shouldUseInputFile(paths)) {
      return _RustCommandInvocation(arguments: [command, ...paths]);
    }

    final inputDir = await Directory.systemTemp.createTemp('vtt_to_lrc_args_');
    final inputFile = File(p.join(inputDir.path, 'paths.txt'));
    await inputFile.writeAsString(paths.join('\n'), flush: true);

    return _RustCommandInvocation(
      arguments: [command, '--input-file', inputFile.path],
      cleanupDirectoryPath: inputDir.path,
    );
  }

  Future<void> _cleanupInvocation(_RustCommandInvocation invocation) async {
    final cleanupPath = invocation.cleanupDirectoryPath;
    if (cleanupPath == null) {
      return;
    }

    final directory = Directory(cleanupPath);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  bool _shouldUseInputFile(List<String> paths) {
    if (paths.length > _maxInlineArgumentCount) {
      return true;
    }

    var totalBytes = 0;
    for (final path in paths) {
      totalBytes += utf8.encode(path).length + 1;
      if (totalBytes > _maxInlineArgumentBytes) {
        return true;
      }
    }

    return false;
  }

  bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }

    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) {
        return false;
      }
    }

    return true;
  }

  List<String> _parseOutputLines(Object output) {
    final text = output.toString().trim();
    if (text.isEmpty) {
      return <String>[];
    }

    return const LineSplitter()
        .convert(text)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  ConvertResult? _parseSuccessLine(
    String line,
    Map<String, int> destinationIndex,
    List<String> normalizedFiles,
  ) {
    const prefix = 'Converted: ';
    if (!line.startsWith(prefix)) {
      return null;
    }

    final destination = _normalizePath(line.substring(prefix.length).trim());
    final index = destinationIndex[destination];
    if (index == null) {
      return null;
    }

    return ConvertResult.success(
      normalizedFiles[index],
      destination,
    );
  }

  ConvertResult? _parseFailureLine(
    String line,
    Map<String, int> sourceIndex,
  ) {
    const prefix = 'Failed: ';
    if (!line.startsWith(prefix)) {
      return null;
    }

    final separator = line.indexOf(' -> ');
    if (separator == -1) {
      return null;
    }

    final source = _normalizePath(line.substring(prefix.length, separator).trim());
    final error = line.substring(separator + 4).trim();
    if (!sourceIndex.containsKey(source)) {
      return null;
    }

    return ConvertResult.failure(
      source,
      error,
    );
  }

  String _expectedDestination(String source) {
    // 与 Rust output_path 同步：剥掉 .vtt 和紧邻的一层扩展名后追加 .lrc。
    final stripped = p.withoutExtension(p.withoutExtension(source));
    return _normalizePath('$stripped.lrc');
  }

  String _normalizePath(String path) {
    return p.normalize(p.absolute(path));
  }
}
