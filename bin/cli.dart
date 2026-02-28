import 'dart:io';
import '../lib/core/vtt_converter.dart';
import '../lib/core/file_scanner.dart';

void main(List<String> args) {
  var targetFiles = <String>[];

  if (args.isNotEmpty) {
    // 从参数中收集文件（支持文件和目录混合）
    try {
      final validPaths = <String>[];
      for (final arg in args) {
        try {
          final type = FileSystemEntity.typeSync(arg);
          if (type != FileSystemEntityType.notFound) {
            validPaths.add(arg);
          } else {
            stderr.writeln('警告: 路径不存在: $arg');
          }
        } on FileSystemException catch (e) {
          // 处理权限错误或其他文件系统异常
          stderr.writeln('警告: 无法访问路径 "$arg": ${e.message}');
        }
      }
      targetFiles = collectVttFromPaths(validPaths);
    } catch (e) {
      stderr.writeln('错误: 处理参数时发生异常: $e');
      exit(2);
    }
  }

  if (targetFiles.isEmpty) {
    // 扫描当前目录
    try {
      targetFiles = Directory.current
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.vtt'))
          .map((f) => f.path)
          .toList();
    } on FileSystemException catch (e) {
      stderr.writeln('错误: 无法扫描当前目录: ${e.message}');
      exit(3);
    } catch (e) {
      stderr.writeln('错误: 扫描目录时发生异常: $e');
      exit(3);
    }
  }

  if (targetFiles.isEmpty) {
    stderr.writeln('未找到 VTT 文件。用法: dart run bin/cli.dart [file1.vtt file2.vtt ...]');
    exit(1);
  }

  List<ConversionResult> results;
  try {
    results = convertFiles(targetFiles);
  } catch (e) {
    stderr.writeln('错误: 转换过程中发生异常: $e');
    exit(4);
  }

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
