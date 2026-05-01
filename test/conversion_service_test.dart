import 'package:flutter_test/flutter_test.dart';
import 'package:vtt_to_lrc/services/conversion_service.dart';
import 'package:vtt_to_lrc/services/rust_backend_service.dart';

/// 单元测试用的假后端：直接返回预设结果，不启动 Rust 进程
class _FakeBackend extends RustBackendService {
  _FakeBackend({
    this.results = const <ConvertResult>[],
    this.error,
    this.warnings = const <String>[],
    this.delay = Duration.zero,
  });

  final List<ConvertResult> results;
  final Object? error;
  final List<String> warnings;
  final Duration delay;

  int convertCallCount = 0;
  List<String>? lastFilesArg;

  @override
  Future<List<ConvertResult>> convertFiles(
    List<String> files, {
    ProgressCallback? onProgress,
    WarningCallback? onWarning,
  }) async {
    convertCallCount++;
    lastFilesArg = files;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (error != null) {
      throw error!;
    }
    for (final warning in warnings) {
      onWarning?.call(warning);
    }
    onProgress?.call(0, results.length, null);
    var done = 0;
    for (final result in results) {
      done++;
      onProgress?.call(done, results.length, result);
    }
    return results;
  }
}

void main() {
  group('ConversionService.convertFiles', () {
    test('全部成功时返回正确摘要并按结果调用日志回调', () async {
      final backend = _FakeBackend(results: <ConvertResult>[
        ConvertResult.success('/tmp/a.vtt', '/tmp/a.lrc'),
        ConvertResult.success('/tmp/b.vtt', '/tmp/b.lrc'),
      ]);
      final service = ConversionService(rustBackendService: backend);

      final logs = <String>[];
      final summary = await service.convertFiles(
        ['/tmp/a.vtt', '/tmp/b.vtt'],
        onProgress: (_, _, _) {},
        onLog: (msg, isError) => logs.add('${isError ? "E" : "I"}:$msg'),
      );

      expect(summary.total, 2);
      expect(summary.successCount, 2);
      expect(summary.failureCount, 0);
      expect(summary.allSucceeded, isTrue);
      expect(summary.hasFailures, isFalse);
      expect(logs, hasLength(2));
      expect(logs.every((line) => line.startsWith('I:')), isTrue);
      expect(service.isConverting, isFalse);
    });

    test('部分失败时摘要分桶并把失败项标记为错误日志', () async {
      final backend = _FakeBackend(results: <ConvertResult>[
        ConvertResult.success('/tmp/ok.vtt', '/tmp/ok.lrc'),
        ConvertResult.failure('/tmp/bad.vtt', '无法解析时间戳'),
      ]);
      final service = ConversionService(rustBackendService: backend);

      final logs = <String>[];
      final summary = await service.convertFiles(
        ['/tmp/ok.vtt', '/tmp/bad.vtt'],
        onProgress: (_, _, _) {},
        onLog: (msg, isError) => logs.add('${isError ? "E" : "I"}:$msg'),
      );

      expect(summary.successCount, 1);
      expect(summary.failureCount, 1);
      expect(summary.hasFailures, isTrue);
      expect(summary.allSucceeded, isFalse);
      expect(summary.allFailed, isFalse);
      expect(logs.where((line) => line.startsWith('E:')), hasLength(1));
      expect(logs.firstWhere((line) => line.startsWith('E:')),
          contains('无法解析时间戳'));
    });

    test('空文件列表时直接抛 ConversionException', () async {
      final backend = _FakeBackend();
      final service = ConversionService(rustBackendService: backend);

      expect(
        () => service.convertFiles(
          <String>[],
          onProgress: (_, _, _) {},
          onLog: (_, _) {},
        ),
        throwsA(isA<ConversionException>()
            .having((e) => e.message, 'message', '没有可转换的文件')),
      );
      expect(backend.convertCallCount, 0);
      expect(service.isConverting, isFalse);
    });

    test('已有任务进行中时再次调用应抛异常且不重复触发后端', () async {
      final backend = _FakeBackend(
        results: <ConvertResult>[
          ConvertResult.success('/tmp/a.vtt', '/tmp/a.lrc'),
        ],
        delay: const Duration(milliseconds: 50),
      );
      final service = ConversionService(rustBackendService: backend);

      final firstCall = service.convertFiles(
        ['/tmp/a.vtt'],
        onProgress: (_, _, _) {},
        onLog: (_, _) {},
      );

      expect(service.isConverting, isTrue);
      expect(
        () => service.convertFiles(
          ['/tmp/a.vtt'],
          onProgress: (_, _, _) {},
          onLog: (_, _) {},
        ),
        throwsA(isA<ConversionException>()
            .having((e) => e.message, 'message', '转换正在进行中')),
      );

      await firstCall;
      expect(service.isConverting, isFalse);
      expect(backend.convertCallCount, 1);
    });

    test('后端抛异常后状态会复位以便重试', () async {
      final backend = _FakeBackend(error: RustBackendException('后端炸了'));
      final service = ConversionService(rustBackendService: backend);

      await expectLater(
        () => service.convertFiles(
          ['/tmp/a.vtt'],
          onProgress: (_, _, _) {},
          onLog: (_, _) {},
        ),
        throwsA(isA<RustBackendException>()),
      );

      expect(service.isConverting, isFalse,
          reason: '异常后必须释放标志位，否则后续调用会被永久阻塞');
    });

    test('warning 回调透传给上层', () async {
      final backend = _FakeBackend(
        results: <ConvertResult>[
          ConvertResult.success('/tmp/a.vtt', '/tmp/a.lrc'),
        ],
        warnings: <String>['路径不存在: /tmp/x.vtt'],
      );
      final service = ConversionService(rustBackendService: backend);

      final warnings = <String>[];
      await service.convertFiles(
        ['/tmp/a.vtt'],
        onProgress: (_, _, _) {},
        onLog: (_, _) {},
        onWarning: warnings.add,
      );

      expect(warnings, ['路径不存在: /tmp/x.vtt']);
    });
  });

  group('ConversionSummary', () {
    test('getFailureSummary 在超过 5 条失败时附加省略行', () {
      final failures = List.generate(
        7,
        (i) => ConvertResult.failure('/tmp/f$i.vtt', '错误$i'),
      );
      final summary = ConversionSummary(
        total: 7,
        successCount: 0,
        failureCount: 7,
        successes: const <ConvertResult>[],
        failures: failures,
      );

      final lines = summary.getFailureSummary();
      expect(lines.first, contains('成功 0 个，失败 7 个'));
      expect(lines.where((l) => l.startsWith('- f')), hasLength(5));
      expect(lines.last, '- ... 另有 2 个失败');
    });

    test('全部失败时 allFailed 为真且 allSucceeded 为假', () {
      final summary = ConversionSummary(
        total: 2,
        successCount: 0,
        failureCount: 2,
        successes: const <ConvertResult>[],
        failures: <ConvertResult>[
          ConvertResult.failure('/tmp/a.vtt', 'oops'),
          ConvertResult.failure('/tmp/b.vtt', 'oops'),
        ],
      );

      expect(summary.allFailed, isTrue);
      expect(summary.allSucceeded, isFalse);
      expect(summary.hasFailures, isTrue);
    });
  });
}
