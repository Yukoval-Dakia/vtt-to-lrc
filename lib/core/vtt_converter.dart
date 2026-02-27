import 'dart:io';
import 'package:path/path.dart' as p;

/// 将 VTT 时间格式 (HH:MM:SS.mmm) 转为 LRC 时间标签 [MM:SS.xx]
/// 解析失败时返回 null
String? vttTimeToLrc(String t) {
  try {
    final parts = t.split(':');
    if (parts.length != 3) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final secParts = parts[2].split('.');
    if (secParts.length != 2) return null;
    final s = int.tryParse(secParts[0]);
    final ms = int.tryParse(secParts[1]);
    if (h == null || m == null || s == null || ms == null) return null;

    final totalMs = (h * 3600 + m * 60 + s) * 1000 + ms;
    final minutes = (totalMs ~/ 60000).toString().padLeft(2, '0');
    final seconds = ((totalMs % 60000) ~/ 1000).toString().padLeft(2, '0');
    final centis = ((totalMs % 1000) ~/ 10).toString().padLeft(2, '0');
    return '[$minutes:$seconds.$centis]';
  } catch (_) {
    return null;
  }
}

/// 将单个 VTT 文件转换为 LRC 文件，返回输出路径（异步版本）
/// 如果解析失败则抛出 FormatException
Future<String> convertVttToLrcAsync(String path) async {
  final file = File(path);
  List<String> content;
  // 尝试 UTF-8，失败则回退到系统编码
  try {
    content = await file.readAsLines();
  } catch (_) {
    content = await file.readAsLines(encoding: SystemEncoding());
  }

  final out = <String>[];
  var i = 0;
  while (i < content.length) {
    final line = content[i].trim();
    if (line.contains('-->')) {
      final start = line.split('-->')[0].trim();
      final lrcTime = vttTimeToLrc(start);
      if (lrcTime == null) {
        throw FormatException('无法解析时间戳: $start');
      }
      i++;
      final textParts = <String>[];
      while (i < content.length && content[i].trim().isNotEmpty) {
        textParts.add(content[i].trim());
        i++;
      }
      out.add('$lrcTime${textParts.join(' ')}');
    }
    i++;
  }

  final baseName = p.withoutExtension(path);
  final lrcPath = '$baseName.lrc';
  await File(lrcPath).writeAsString(out.join('\n'));
  return lrcPath;
}

/// 将单个 VTT 文件转换为 LRC 文件，返回输出路径（同步版本）
/// @Deprecated('请使用异步版本 convertVttToLrcAsync')
/// 如果解析失败则抛出 FormatException
String convertVttToLrc(String path) {
  final file = File(path);
  final lines = file.readAsLinesSync(encoding: SystemEncoding());
  // 尝试 UTF-8，失败则回退
  List<String> content;
  try {
    content = file.readAsLinesSync();
  } catch (_) {
    content = lines;
  }

  final out = <String>[];
  var i = 0;
  while (i < content.length) {
    final line = content[i].trim();
    if (line.contains('-->')) {
      final start = line.split('-->')[0].trim();
      final lrcTime = vttTimeToLrc(start);
      if (lrcTime == null) {
        throw FormatException('无法解析时间戳: $start');
      }
      i++;
      final textParts = <String>[];
      while (i < content.length && content[i].trim().isNotEmpty) {
        textParts.add(content[i].trim());
        i++;
      }
      out.add('$lrcTime${textParts.join(' ')}');
    }
    i++;
  }

  final baseName = p.withoutExtension(path);
  final lrcPath = '$baseName.lrc';
  File(lrcPath).writeAsStringSync(out.join('\n'));
  return lrcPath;
}

/// 转换结果
class ConvertResult {
  final String source;
  final String? destination;
  final String? error;

  ConvertResult.success(this.source, this.destination) : error = null;
  ConvertResult.failure(this.source, this.error) : destination = null;

  bool get isSuccess => error == null;
}

/// 进度回调类型定义
/// [current] 当前已完成的文件数
/// [total] 总文件数
/// [result] 刚完成的转换结果（可为 null 表示正在处理中）
typedef ProgressCallback = void Function(int current, int total, ConvertResult? result);

/// 批量转换文件（异步版本）
/// 支持 [onProgress] 回调通知转换进度
Future<List<ConvertResult>> convertFilesAsync(
  List<String> filePaths, {
  ProgressCallback? onProgress,
}) async {
  final results = <ConvertResult>[];
  final vttFiles = filePaths
      .where((p) => p.toLowerCase().endsWith('.vtt'))
      .toList();

  for (var i = 0; i < vttFiles.length; i++) {
    final path = vttFiles[i];

    // 通知进度（转换开始前）
    onProgress?.call(i, vttFiles.length, null);

    if (!await File(path).exists()) continue;
    try {
      final lrcPath = await convertVttToLrcAsync(path);
      results.add(ConvertResult.success(path, lrcPath));
    } on FileSystemException catch (e) {
      results.add(ConvertResult.failure(path, '文件访问失败：${e.message}'));
    } catch (e) {
      results.add(ConvertResult.failure(path, '转换失败：$e'));
    }

    // 通知进度（转换完成后，传递结果）
    onProgress?.call(i + 1, vttFiles.length, results.last);
  }
  return results;
}

/// 批量转换文件（同步版本）
/// @Deprecated('请使用异步版本 convertFilesAsync')
List<ConvertResult> convertFiles(List<String> filePaths) {
  final results = <ConvertResult>[];
  for (final path in filePaths) {
    if (!path.toLowerCase().endsWith('.vtt')) continue;
    if (!File(path).existsSync()) continue;
    try {
      final lrcPath = convertVttToLrc(path);
      results.add(ConvertResult.success(path, lrcPath));
    } on FileSystemException catch (e) {
      results.add(ConvertResult.failure(path, '文件访问失败：${e.message}'));
    } catch (e) {
      results.add(ConvertResult.failure(path, '转换失败：$e'));
    }
  }
  return results;
}
