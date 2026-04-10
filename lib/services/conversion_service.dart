import 'package:path/path.dart' as p;

import 'rust_backend_service.dart';

/// 转换进度回调
/// [current]: 当前完成的数量
/// [total]: 总数量
/// [result]: 当前完成的转换结果（可能为 null 表示进度更新）
typedef ConversionProgressCallback = void Function(
  int current,
  int total,
  ConvertResult? result,
);

/// 转换服务
/// 负责处理 VTT 到 LRC 的转换业务逻辑
class ConversionService {
  final RustBackendService _rustBackendService;
  bool _isConverting = false;

  ConversionService({
    RustBackendService? rustBackendService,
  }) : _rustBackendService = rustBackendService ?? RustBackendService();

  bool get isConverting => _isConverting;

  /// 执行批量转换
  ///
  /// [files]: 要转换的文件列表
  /// [onProgress]: 进度回调
  /// [onLog]: 日志回调，用于记录转换过程中的信息
  ///
  /// 返回转换结果列表
  Future<ConversionSummary> convertFiles(
    List<String> files, {
    required ConversionProgressCallback onProgress,
    required void Function(String message, bool isError) onLog,
  }) async {
    if (_isConverting) {
      throw ConversionException('转换正在进行中');
    }

    if (files.isEmpty) {
      throw ConversionException('没有可转换的文件');
    }

    _isConverting = true;

    try {
      final results = await _rustBackendService.convertFiles(
        files,
        onProgress: onProgress,
      );

      final successes = results.where((r) => r.isSuccess).toList();
      final failures = results.where((r) => !r.isSuccess).toList();

      // 记录每个转换结果
      for (final result in results) {
        if (result.isSuccess) {
          onLog(
            '✔ ${p.basename(result.source)}  →  ${p.basename(result.destination!)}',
            false,
          );
        } else {
          onLog(
            '✘ ${p.basename(result.source)}  →  ${result.error}',
            true,
          );
        }
      }

      return ConversionSummary(
        total: results.length,
        successCount: successes.length,
        failureCount: failures.length,
        successes: successes,
        failures: failures,
      );
    } finally {
      _isConverting = false;
    }
  }

  /// 重置转换状态
  void reset() {
    _isConverting = false;
  }
}

/// 转换摘要
class ConversionSummary {
  final int total;
  final int successCount;
  final int failureCount;
  final List<ConvertResult> successes;
  final List<ConvertResult> failures;

  ConversionSummary({
    required this.total,
    required this.successCount,
    required this.failureCount,
    required this.successes,
    required this.failures,
  });

  bool get hasFailures => failureCount > 0;
  bool get allSucceeded => failureCount == 0 && successCount > 0;
  bool get allFailed => successCount == 0 && failureCount > 0;

  /// 获取失败信息摘要（最多显示 5 个）
  List<String> getFailureSummary({int maxItems = 5}) {
    final lines = <String>[
      '成功 $successCount 个，失败 $failureCount 个。',
      '',
      '失败示例：',
    ];

    for (final result in failures.take(maxItems)) {
      lines.add('- ${p.basename(result.source)}：${result.error}');
    }

    if (failures.length > maxItems) {
      lines.add('- ... 另有 ${failures.length - maxItems} 个失败');
    }

    return lines;
  }
}

/// 转换异常
class ConversionException implements Exception {
  final String message;
  ConversionException(this.message);

  @override
  String toString() => message;
}
