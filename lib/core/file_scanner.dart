import 'dart:io';
import 'package:path/path.dart' as p;

/// 默认最大扫描深度
const int defaultMaxDepth = 10;

/// 递归扫描目录下的所有 VTT 文件
///
/// [directory] - 要扫描的目录路径
/// [maxDepth] - 最大递归深度，默认为 [defaultMaxDepth]（10层）
/// [onWarning] - 警告回调函数
List<String> scanDirectoryForVtt(
  String directory, {
  int maxDepth = defaultMaxDepth,
  void Function(String)? onWarning,
}) {
  final vttFiles = <String>[];
  final dir = Directory(directory);

  if (!dir.existsSync()) return vttFiles;

  // 使用手动递归来控制深度
  void scanRecursive(Directory currentDir, int currentDepth) {
    if (currentDepth > maxDepth) {
      onWarning?.call('达到最大扫描深度限制 ($maxDepth)，跳过目录：${currentDir.path}');
      return;
    }

    try {
      for (final entity in currentDir.listSync(followLinks: false)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.vtt')) {
          vttFiles.add(entity.path);
        } else if (entity is Directory) {
          scanRecursive(entity, currentDepth + 1);
        }
      }
    } on FileSystemException catch (e) {
      onWarning?.call('跳过不可访问目录：${e.path ?? currentDir.path}（${e.message}）');
    }
  }

  scanRecursive(dir, 1);

  return vttFiles;
}

/// 从一组路径中收集所有 VTT 文件（支持文件和目录混合）
///
/// [paths] - 文件或目录路径列表
/// [maxDepth] - 最大递归深度，默认为 [defaultMaxDepth]（10层）
/// [onWarning] - 警告回调函数
List<String> collectVttFromPaths(
  List<String> paths, {
  int maxDepth = defaultMaxDepth,
  void Function(String)? onWarning,
}) {
  final collected = <String>[];

  for (final path in paths) {
    try {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.directory) {
        collected.addAll(scanDirectoryForVtt(path, maxDepth: maxDepth, onWarning: onWarning));
      } else if (type == FileSystemEntityType.file &&
          path.toLowerCase().endsWith('.vtt')) {
        collected.add(path);
      }
    } on FileSystemException catch (e) {
      // 处理权限问题或无法访问的文件，跳过并继续扫描其他文件
      onWarning?.call('跳过无法访问的路径：${e.path ?? path}（${e.message}）');
    } catch (e) {
      // 处理其他可能的异常
      onWarning?.call('跳过无法访问的路径：$path（$e）');
    }
  }

  // 去重
  final seen = <String>{};
  final uniqueFiles = <String>[];
  for (final path in collected) {
    final absPath = p.absolute(path);
    if (seen.add(absPath)) {
      uniqueFiles.add(absPath);
    }
  }
  return uniqueFiles;
}
