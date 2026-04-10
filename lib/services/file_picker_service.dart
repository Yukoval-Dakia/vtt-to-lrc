import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'rust_backend_service.dart';

/// 文件选择结果
class FileSelectionResult {
  final List<String> files;
  final String? directory;
  final int fileCount;
  final String statusText;
  final bool canConvert;

  FileSelectionResult({
    required this.files,
    this.directory,
    required this.fileCount,
    required this.statusText,
    required this.canConvert,
  });
}

/// 文件选择服务
/// 负责处理文件和目录的选择、扫描等操作
class FilePickerService {
  final RustBackendService _rustBackendService;

  FilePickerService({
    RustBackendService? rustBackendService,
  }) : _rustBackendService = rustBackendService ?? RustBackendService();

  /// 选择 VTT 文件
  Future<FileSelectionResult?> pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['vtt'],
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final paths = result.paths.whereType<String>().toList();
        if (paths.isNotEmpty) {
          return FileSelectionResult(
            files: paths,
            directory: null,
            fileCount: paths.length,
            statusText: '已选择 ${paths.length} 个文件',
            canConvert: true,
          );
        }
      }
      return null;
    } catch (e) {
      throw FilePickerException('文件选择失败: $e');
    }
  }

  /// 选择目录并扫描 VTT 文件
  Future<FileSelectionResult?> pickDirectory({
    required void Function(String) onWarning,
  }) async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();

      if (result != null) {
        final scanResult = await _rustBackendService.scanPaths([result]);
        for (final warning in scanResult.warnings) {
          onWarning(warning);
        }

        return FileSelectionResult(
          files: scanResult.files,
          directory: result,
          fileCount: scanResult.files.length,
          statusText: '${p.basename(result)}/  — 发现 ${scanResult.files.length} 个 VTT 文件',
          canConvert: scanResult.files.isNotEmpty,
        );
      }
      return null;
    } on RustBackendException catch (e) {
      throw FilePickerException('目录扫描失败: $e');
    } catch (e) {
      throw FilePickerException('目录选择失败: $e');
    }
  }

  /// 处理拖拽的文件和目录
  Future<FileSelectionResult?> processDroppedFiles(
    List<String> paths, {
    required void Function(String) onWarning,
    required void Function(String) onLog,
  }) async {
    if (paths.isEmpty) return null;

    final directories = paths
        .where((p) => FileSystemEntity.isDirectorySync(p))
        .toList();
    final files = paths
        .where((p) => FileSystemEntity.isFileSync(p))
        .toList();

    // 如果只拖拽了一个目录，直接处理该目录
    if (paths.length == 1 && directories.isNotEmpty && files.isEmpty) {
      final scanResult = await _rustBackendService.scanPaths([directories.first]);
      for (final warning in scanResult.warnings) {
        onWarning(warning);
      }

      return FileSelectionResult(
        files: scanResult.files,
        directory: directories.first,
        fileCount: scanResult.files.length,
        statusText: '${p.basename(directories.first)}/  — 发现 ${scanResult.files.length} 个 VTT 文件',
        canConvert: scanResult.files.isNotEmpty,
      );
    }

    // 处理混合内容（文件和目录）
    final scanResult = await _rustBackendService.scanPaths(paths);
    for (final warning in scanResult.warnings) {
      onWarning(warning);
    }

    if (scanResult.files.isNotEmpty && directories.isNotEmpty && files.isNotEmpty) {
      onLog('  (包含 ${directories.length} 个目录，已展开)');
    }

    return FileSelectionResult(
      files: scanResult.files,
      directory: null,
      fileCount: scanResult.files.length,
      statusText: '已选择 ${scanResult.files.length} 个文件',
      canConvert: scanResult.files.isNotEmpty,
    );
  }
}

/// 文件选择异常
class FilePickerException implements Exception {
  final String message;
  FilePickerException(this.message);

  @override
  String toString() => message;
}
