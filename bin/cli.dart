import 'dart:io';
import '../lib/core/vtt_converter.dart';
import '../lib/core/file_scanner.dart';

void main(List<String> args) {
  var targetFiles = <String>[];

  if (args.isNotEmpty) {
    // 从参数中收集文件（支持文件和目录混合）
    targetFiles = collectVttFromPaths(
      args.where((a) => FileSystemEntity.typeSync(a) != FileSystemEntityType.notFound).toList(),
    );
  }

  if (targetFiles.isEmpty) {
    // 扫描当前目录
    targetFiles = Directory.current
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.vtt'))
        .map((f) => f.path)
        .toList();
  }

  if (targetFiles.isEmpty) {
    stderr.writeln('未找到 VTT 文件。用法: dart run bin/cli.dart [file1.vtt file2.vtt ...]');
    exit(1);
  }

  final results = convertFiles(targetFiles);
  var failures = 0;

  for (final r in results) {
    if (r.isSuccess) {
      print('Converted: ${r.destination}');
    } else {
      stderr.writeln('Failed: ${r.source} -> ${r.error}');
      failures++;
    }
  }

  if (failures > 0) exit(1);
}
