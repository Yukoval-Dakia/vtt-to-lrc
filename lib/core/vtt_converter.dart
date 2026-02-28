import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:gbk_codec/gbk_codec.dart';

/// 支持的编码类型枚举
enum EncodingType {
  utf8,
  ascii,
  latin1,
  windows1252,
  gbk,
}

/// 编码检测和转换工具类
class EncodingDetector {
  /// Windows-1252 到 Unicode 的映射表（0x80-0x9F 范围的特殊字符）
  static const Map<int, int> _windows1252ToUnicode = {
    0x80: 0x20AC, // Euro Sign
    0x82: 0x201A, // Single Low-9 Quotation Mark
    0x83: 0x0192, // Latin Small Letter F with Hook
    0x84: 0x201E, // Double Low-9 Quotation Mark
    0x85: 0x2026, // Horizontal Ellipsis
    0x86: 0x2020, // Dagger
    0x87: 0x2021, // Double Dagger
    0x88: 0x02C6, // Modifier Letter Circumflex Accent
    0x89: 0x2030, // Per Mille Sign
    0x8A: 0x0160, // Latin Capital Letter S with Caron
    0x8B: 0x2039, // Single Left-Pointing Angle Quotation Mark
    0x8C: 0x0152, // Latin Capital Ligature OE
    0x8E: 0x017D, // Latin Capital Letter Z with Caron
    0x91: 0x2018, // Left Single Quotation Mark
    0x92: 0x2019, // Right Single Quotation Mark
    0x93: 0x201C, // Left Double Quotation Mark
    0x94: 0x201D, // Right Double Quotation Mark
    0x95: 0x2022, // Bullet
    0x96: 0x2013, // En Dash
    0x97: 0x2014, // Em Dash
    0x98: 0x02DC, // Small Tilde
    0x99: 0x2122, // Trade Mark Sign
    0x9A: 0x0161, // Latin Small Letter S with Caron
    0x9B: 0x203A, // Single Right-Pointing Angle Quotation Mark
    0x9C: 0x0153, // Latin Small Ligature OE
    0x9E: 0x017E, // Latin Small Letter Z with Caron
    0x9F: 0x0178, // Latin Capital Letter Y with Diaeresis
  };

  /// 将 Windows-1252 字节转换为字符串
  static String decodeWindows1252(List<int> bytes) {
    final codeUnits = <int>[];
    for (final byte in bytes) {
      if (byte < 0x80) {
        codeUnits.add(byte);
      } else if (_windows1252ToUnicode.containsKey(byte)) {
        codeUnits.add(_windows1252ToUnicode[byte]!);
      } else if (byte >= 0xA0 && byte <= 0xFF) {
        // 0xA0-0xFF 范围与 Latin-1 相同
        codeUnits.add(byte);
      } else {
        // 无法识别的字节，使用替换字符
        codeUnits.add(0xFFFD);
      }
    }
    return String.fromCharCodes(codeUnits);
  }

  /// 检测字节是否为有效的 UTF-8
  static bool _isValidUtf8(List<int> bytes) {
    try {
      utf8.decode(bytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 检测字节是否为有效的 ASCII
  static bool _isValidAscii(List<int> bytes) {
    for (final byte in bytes) {
      if (byte > 127) return false;
    }
    return true;
  }

  /// 检测字节是否可能为 GBK 编码（包含中文字符）
  static bool _isLikelyGbk(List<int> bytes) {
    // 检查是否有 GBK 编码特征（双字节中文字符）
    for (int i = 0; i < bytes.length - 1; i++) {
      final b1 = bytes[i];
      final b2 = bytes[i + 1];
      // GBK 第一字节范围: 0x81-0xFE
      // GBK 第二字节范围: 0x40-0xFE (不含 0x7F)
      if (b1 >= 0x81 && b1 <= 0xFE && b2 >= 0x40 && b2 <= 0xFE && b2 != 0x7F) {
        return true;
      }
    }
    return false;
  }

  /// 尝试使用指定编码解码字节，失败返回 null
  static String? _tryDecode(List<int> bytes, EncodingType encoding) {
    try {
      switch (encoding) {
        case EncodingType.utf8:
          return utf8.decode(bytes);
        case EncodingType.ascii:
          if (_isValidAscii(bytes)) {
            return ascii.decode(bytes);
          }
          return null;
        case EncodingType.latin1:
          return latin1.decode(bytes);
        case EncodingType.windows1252:
          return decodeWindows1252(bytes);
        case EncodingType.gbk:
          return gbk.decode(bytes);
      }
    } catch (_) {
      return null;
    }
  }

  /// 检测文件编码并返回解码后的内容
  /// 按优先级尝试不同编码：UTF-8 > ASCII > GBK > Windows-1252 > Latin1
  static String detectAndDecode(List<int> bytes) {
    // 1. 首先检查 BOM (Byte Order Mark)
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      // UTF-8 with BOM
      return utf8.decode(bytes.sublist(3));
    }

    // 2. 尝试 UTF-8（最常用的编码）
    if (_isValidUtf8(bytes)) {
      return utf8.decode(bytes);
    }

    // 3. 如果是纯 ASCII，使用 ASCII 编码
    if (_isValidAscii(bytes)) {
      return ascii.decode(bytes);
    }

    // 4. 检测是否可能为 GBK 编码（中文内容）
    if (_isLikelyGbk(bytes)) {
      final decoded = _tryDecode(bytes, EncodingType.gbk);
      if (decoded != null) {
        return decoded;
      }
    }

    // 5. 尝试 Windows-1252（西欧语言常用）
    final win1252Result = _tryDecode(bytes, EncodingType.windows1252);
    if (win1252Result != null) {
      return win1252Result;
    }

    // 6. 最后回退到 Latin1（ISO-8859-1，兼容性最广）
    return latin1.decode(bytes);
  }

  /// 检测文件编码类型
  static EncodingType detectEncoding(List<int> bytes) {
    // 检查 BOM
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      return EncodingType.utf8;
    }

    // 尝试 UTF-8
    if (_isValidUtf8(bytes)) {
      return EncodingType.utf8;
    }

    // 检查 ASCII
    if (_isValidAscii(bytes)) {
      return EncodingType.ascii;
    }

    // 检测 GBK
    if (_isLikelyGbk(bytes)) {
      try {
        gbk.decode(bytes);
        return EncodingType.gbk;
      } catch (_) {
        // 继续尝试其他编码
      }
    }

    // 默认返回 Latin1（兼容性最广）
    return EncodingType.latin1;
  }
}

/// 清理 VTT 文本中的 HTML 标签
/// 清理的标签包括: <b>, </b>, <i>, </i>, <c>, </c>, <u>, </u>, <ruby>, </ruby>, <rt>, </rt>
/// 同时处理带有属性的标签，如 <c.classname>, <c.style.color>
String cleanVttText(String text) {
  // 使用正则表达式匹配所有 VTT 格式标签
  // 匹配: <tag>, </tag>, <tag.attr>, </tag>
  final tagPattern = RegExp(
    r'<(/?)(b|i|c|u|ruby|rt)(?:\s+[^>]*)?>',
    caseSensitive: false,
  );
  return text.replaceAll(tagPattern, '');
}

/// VTT 时间戳格式正则表达式
/// 格式: HH:MM:SS.mmm
/// - 小时: 任意数字（至少一位）
/// - 分钟: 00-59
/// - 秒: 00-59
/// - 毫秒: 000-999（必须三位）
final RegExp _vttTimestampRegex = RegExp(
  r'^(\d+):([0-5]\d):([0-5]\d)\.\d{3}$',
);

/// 验证 VTT 时间戳格式是否严格符合 HH:MM:SS.mmm
/// 返回 true 如果格式正确，false 否则
bool isValidVttTimestamp(String timestamp) {
  return _vttTimestampRegex.hasMatch(timestamp.trim());
}

/// 将 VTT 时间格式 (HH:MM:SS.mmm) 转为 LRC 时间标签 [MM:SS.xx]
/// 解析失败时返回 null
/// 使用正则表达式严格验证时间戳格式
String? vttTimeToLrc(String t) {
  try {
    final trimmed = t.trim();

    // 使用正则表达式严格验证格式
    if (!isValidVttTimestamp(trimmed)) {
      return null;
    }

    final parts = trimmed.split(':');
    if (parts.length != 3) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final secParts = parts[2].split('.');
    if (secParts.length != 2) return null;
    final s = int.tryParse(secParts[0]);
    final ms = int.tryParse(secParts[1]);
    if (h == null || m == null || s == null || ms == null) return null;

    // 额外验证数值范围（正则已验证大部分，这里做二次确认）
    if (m < 0 || m > 59 || s < 0 || s > 59 || ms < 0 || ms > 999) {
      return null;
    }

    final totalMs = (h * 3600 + m * 60 + s) * 1000 + ms;
    final minutes = (totalMs ~/ 60000).toString().padLeft(2, '0');
    final seconds = ((totalMs % 60000) ~/ 1000).toString().padLeft(2, '0');
    final centis = ((totalMs % 1000) ~/ 10).toString().padLeft(2, '0');
    return '[$minutes:$seconds.$centis]';
  } catch (_) {
    return null;
  }
}

/// 解析 VTT 内容并生成 LRC 行
/// [decodedContent] 已解码的 VTT 文件内容
/// 返回 LRC 格式的行列表
/// 如果解析失败则抛出 FormatException
List<String> _parseVttContent(String decodedContent) {
  final content = decodedContent.split('\n');
  final out = <String>[];
  var i = 0;
  while (i < content.length) {
    final line = content[i].trim();
    if (line.contains('-->')) {
      final arrowIndex = line.indexOf('-->');
      final start = line.substring(0, arrowIndex).trim();
      final lrcTime = vttTimeToLrc(start);
      if (lrcTime == null) {
        throw FormatException('无法解析时间戳: $start');
      }
      i++;
      final textParts = <String>[];
      while (i < content.length && content[i].trim().isNotEmpty) {
        textParts.add(cleanVttText(content[i].trim()));
        i++;
      }
      out.add('$lrcTime${textParts.join(' ')}');
    }
    i++;
  }
  return out;
}

/// 根据源文件路径生成 LRC 输出路径
String _getLrcOutputPath(String sourcePath) {
  final baseName = p.withoutExtension(sourcePath);
  return '$baseName.lrc';
}

/// 将单个 VTT 文件转换为 LRC 文件，返回输出路径（异步版本）
/// 如果解析失败则抛出 FormatException
Future<String> convertVttToLrcAsync(String path) async {
  final file = File(path);
  final bytes = await file.readAsBytes();
  final decodedContent = EncodingDetector.detectAndDecode(bytes);
  final lrcLines = _parseVttContent(decodedContent);
  
  final lrcPath = _getLrcOutputPath(path);
  await File(lrcPath).writeAsString(lrcLines.join('\n'));
  return lrcPath;
}

/// 将单个 VTT 文件转换为 LRC 文件，返回输出路径（同步版本）
/// @Deprecated('请使用异步版本 convertVttToLrcAsync')
/// 如果解析失败则抛出 FormatException
String convertVttToLrc(String path) {
  final file = File(path);
  final bytes = file.readAsBytesSync();
  final decodedContent = EncodingDetector.detectAndDecode(bytes);
  final lrcLines = _parseVttContent(decodedContent);
  
  final lrcPath = _getLrcOutputPath(path);
  File(lrcPath).writeAsStringSync(lrcLines.join('\n'));
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

/// 执行单个文件的转换并处理异常（异步版本）
/// 返回转换结果，不会抛出异常
Future<ConvertResult> _convertSingleFileAsync(String path) async {
  try {
    final lrcPath = await convertVttToLrcAsync(path);
    return ConvertResult.success(path, lrcPath);
  } on FileSystemException catch (e) {
    // 捕获文件不存在或读取失败的异常
    return ConvertResult.failure(path, '文件访问失败：${e.message}');
  } catch (e) {
    return ConvertResult.failure(path, '转换失败：$e');
  }
}

/// 执行单个文件的转换并处理异常（同步版本）
/// 返回转换结果，不会抛出异常
ConvertResult _convertSingleFile(String path) {
  try {
    final lrcPath = convertVttToLrc(path);
    return ConvertResult.success(path, lrcPath);
  } on FileSystemException catch (e) {
    // 捕获文件不存在或读取失败的异常
    return ConvertResult.failure(path, '文件访问失败：${e.message}');
  } catch (e) {
    return ConvertResult.failure(path, '转换失败：$e');
  }
}

/// 过滤出 VTT 文件路径
List<String> _filterVttFiles(List<String> filePaths) {
  return filePaths.where((p) => p.toLowerCase().endsWith('.vtt')).toList();
}

/// 批量转换文件（异步版本，并行处理）
/// 支持 [onProgress] 回调通知转换进度
/// 使用 [Future.wait] 实现并行转换，显著提升大量文件的处理速度
Future<List<ConvertResult>> convertFilesAsync(
  List<String> filePaths, {
  ProgressCallback? onProgress,
}) async {
  final vttFiles = _filterVttFiles(filePaths);
  
  if (vttFiles.isEmpty) {
    return [];
  }
  
  // 通知开始处理
  onProgress?.call(0, vttFiles.length, null);
  
  // 使用 Map 存储结果，保证顺序与输入一致
  final resultMap = <int, ConvertResult>{};
  var completedCount = 0;
  
  // 创建所有转换任务并并行执行
  final futures = <Future<void>>[];
  for (var i = 0; i < vttFiles.length; i++) {
    final index = i;
    final path = vttFiles[i];
    
    futures.add(_convertSingleFileAsync(path).then((result) {
      // 存储结果（保持原始顺序）
      resultMap[index] = result;
      // 更新完成计数
      completedCount++;
      // 通知进度（传递刚完成的结果）
      onProgress?.call(completedCount, vttFiles.length, result);
    }));
  }
  
  // 等待所有任务完成
  await Future.wait(futures);
  
  // 按原始顺序返回结果
  return List.generate(vttFiles.length, (i) => resultMap[i]!);
}

/// 批量转换文件（同步版本）
/// @Deprecated('请使用异步版本 convertFilesAsync')
List<ConvertResult> convertFiles(List<String> filePaths) {
  final vttFiles = _filterVttFiles(filePaths);
  return vttFiles.map(_convertSingleFile).toList();
}
