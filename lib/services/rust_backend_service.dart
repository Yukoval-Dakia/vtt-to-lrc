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

/// 解析 `assets/backend/<binary>.stamp`：第一行 SHA-256，第二行字节长度
class _BackendStamp {
  final String raw;
  final int size;

  const _BackendStamp(this.raw, this.size);

  static _BackendStamp? parse(String content) {
    final normalized = content.replaceAll('\r\n', '\n');
    final lines = normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length < 2) {
      return null;
    }
    final size = int.tryParse(lines[1]);
    if (size == null || size <= 0) {
      return null;
    }
    // raw 规范化为 LF，写盘与读盘保持一致，避免跨平台换行差异导致快路径失效
    return _BackendStamp(normalized, size);
  }
}

/// Rust 后端服务
/// 负责按宿主 OS+架构选择内置二进制、解压到临时目录并调用，解析输出协议
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
      final process = await Process.start(executablePath, invocation.arguments);
      final files = <String>[];
      final warnings = <String>[];

      final stdoutDone = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          files.add(trimmed);
        }
      });
      final stderrDone = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          warnings.add(trimmed);
        }
      });

      final exitCode = await process.exitCode;
      // forEach 监听器在进程退出前已并发运行；exitCode 解决时 stdout/stderr
      // 可能仍有缓冲数据，Future.wait 确保两个流全部消费完毕后再检查结果。
      await Future.wait<void>([stdoutDone, stderrDone]);

      if (exitCode != 0) {
        final message = warnings.isNotEmpty
            ? warnings.join('\n')
            : 'Rust 扫描进程退出码异常：$exitCode';
        throw RustBackendException(message);
      }

      return RustScanResult(files: files, warnings: warnings);
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

    for (var i = 0; i < normalizedFiles.length; i++) {
      sourceIndex[normalizedFiles[i]] = i;
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

              final result = _parseSuccessLine(trimmed, sourceIndex);
              if (result == null) {
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
    final stampAssetPath = '$assetPath.stamp';

    if (_cachedExecutablePath != null &&
        await File(_cachedExecutablePath!).exists()) {
      return _cachedExecutablePath!;
    }

    final backendDir = Directory(
      p.join(Directory.systemTemp.path, 'vtt_to_lrc_backend'),
    );
    await backendDir.create(recursive: true);

    final executablePath = p.join(backendDir.path, assetName);
    final stampPath = p.join(backendDir.path, '$assetName.stamp');
    final executableFile = File(executablePath);
    final stampFile = File(stampPath);

    final assetStamp = await _loadBackendStamp(stampAssetPath);

    // 快路径：磁盘已有可执行文件、本地 stamp 与资源 stamp 一致、文件大小匹配
    // → 跳过整段二进制资源加载（约 2 MB asset I/O）
    if (assetStamp != null &&
        await executableFile.exists() &&
        await stampFile.exists()) {
      final existingStamp =
          (await stampFile.readAsString()).replaceAll('\r\n', '\n');
      final existingLength = await executableFile.length();
      if (existingStamp == assetStamp.raw &&
          existingLength == assetStamp.size) {
        _cachedExecutablePath = executablePath;
        return executablePath;
      }
    }

    // 慢路径：从资源加载完整二进制写盘
    final bytes = await _loadBackendBytes(assetPath);
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

    if (assetStamp != null) {
      await stampFile.writeAsString(assetStamp.raw, flush: true);
    } else if (await stampFile.exists()) {
      // 资源里没带 stamp（向后兼容）：清掉旧 stamp，避免下次冷启动误命中老二进制
      await stampFile.delete();
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

  /// 加载资源里的版本戳；若不存在（旧版资源/未运行 build-and-sync），返回 null 走慢路径
  Future<_BackendStamp?> _loadBackendStamp(String stampAssetPath) async {
    try {
      final raw = await rootBundle.loadString(stampAssetPath);
      return _BackendStamp.parse(raw);
    } catch (_) {
      return null;
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

  ConvertResult? _parseSuccessLine(
    String line,
    Map<String, int> sourceIndex,
  ) {
    const prefix = 'Converted: ';
    if (!line.startsWith(prefix)) {
      return null;
    }

    // 协议：`Converted: <src> -> <dst>`。
    // lastIndexOf 确保源路径本身含有 ' -> ' 时仍能正确切分。
    final body = line.substring(prefix.length);
    final separator = body.lastIndexOf(' -> ');
    if (separator == -1) {
      return null;
    }

    final source = _normalizePath(body.substring(0, separator).trim());
    final destination = _normalizePath(body.substring(separator + 4).trim());
    if (!sourceIndex.containsKey(source)) {
      return null;
    }

    return ConvertResult.success(source, destination);
  }

  ConvertResult? _parseFailureLine(
    String line,
    Map<String, int> sourceIndex,
  ) {
    const prefix = 'Failed: ';
    if (!line.startsWith(prefix)) {
      return null;
    }

    // lastIndexOf 确保源路径本身含有 ' -> ' 时仍能正确切分。
    final body = line.substring(prefix.length);
    final separator = body.lastIndexOf(' -> ');
    if (separator == -1) {
      return null;
    }

    final source = _normalizePath(body.substring(0, separator).trim());
    final error = body.substring(separator + 4).trim();
    if (!sourceIndex.containsKey(source)) {
      return null;
    }

    return ConvertResult.failure(source, error);
  }

  String _normalizePath(String path) {
    return p.normalize(p.absolute(path));
  }
}
