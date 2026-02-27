import 'dart:io';
import 'package:path/path.dart' as p;

/// 递归扫描目录下的所有 VTT 文件
List<String> scanDirectoryForVtt(
  String directory, {
  void Function(String)? onWarning,
}) {
  final vttFiles = <String>[];
  final dir = Directory(directory);

  if (!dir.existsSync()) return vttFiles;

  try {
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.vtt')) {
        vttFiles.add(entity.path);
      }
    }
  } on FileSystemException catch (e) {
    onWarning?.call('跳过不可访问目录：${e.path ?? directory}（${e.message}）');
  }

  return vttFiles;
}

/// 从一组路径中收集所有 VTT 文件（支持文件和目录混合）
List<String> collectVttFromPaths(
  List<String> paths, {
  void Function(String)? onWarning,
}) {
  final collected = <String>[];

  for (final path in paths) {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.directory) {
      collected.addAll(scanDirectoryForVtt(path, onWarning: onWarning));
    } else if (type == FileSystemEntityType.file &&
        path.toLowerCase().endsWith('.vtt')) {
      collected.add(path);
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
