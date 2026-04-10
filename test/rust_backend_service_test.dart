import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vtt_to_lrc/services/rust_backend_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late RustBackendService rustBackendService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vtt_rust_backend_test_');
    rustBackendService = RustBackendService();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('通过 Flutter 调用 Rust 后端完成扫描与转换', () async {
    final nestedDir = Directory(p.join(tempDir.path, 'nested'));
    await nestedDir.create(recursive: true);

    final basicPath = p.join(tempDir.path, 'basic.vtt');
    await File(basicPath).writeAsString('''WEBVTT

00:00:01.000 --> 00:00:04.000
第一行字幕

00:00:05.000 --> 00:00:08.000
第二行字幕
''');

    final htmlPath = p.join(tempDir.path, 'html_tags.vtt');
    await File(htmlPath).writeAsString('''WEBVTT

00:00:01.000 --> 00:00:04.000
<b>粗体</b>和<i>斜体</i>
''');

    final invalidPath = p.join(tempDir.path, 'invalid.vtt');
    await File(invalidPath).writeAsString('''WEBVTT

invalid_timestamp --> 00:00:04.000
无效时间戳
''');

    final bomPath = p.join(tempDir.path, 'bom.vtt');
    await File(bomPath).writeAsBytes([
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode('''WEBVTT

00:00:02.000 --> 00:00:05.000
UTF-8 BOM 测试
'''),
    ]);

    final gbkPath = p.join(nestedDir.path, 'gbk.vtt');
    await File(gbkPath).writeAsBytes(<int>[
      0x57,
      0x45,
      0x42,
      0x56,
      0x54,
      0x54,
      0x0A,
      0x0A,
      0x30,
      0x30,
      0x3A,
      0x30,
      0x30,
      0x3A,
      0x30,
      0x33,
      0x2E,
      0x30,
      0x30,
      0x30,
      0x20,
      0x2D,
      0x2D,
      0x3E,
      0x20,
      0x30,
      0x30,
      0x3A,
      0x30,
      0x30,
      0x3A,
      0x30,
      0x36,
      0x2E,
      0x30,
      0x30,
      0x30,
      0x0A,
      0xD6,
      0xD0,
      0xCE,
      0xC4,
      0x47,
      0x42,
      0x4B,
      0xB2,
      0xE2,
      0xCA,
      0xD4,
      0x0A,
    ]);

    final scanResult = await rustBackendService.scanPaths([tempDir.path]);
    expect(scanResult.warnings, isEmpty);
    expect(scanResult.files.length, 5);

    final progressEvents = <String>[];
    final results = await rustBackendService.convertFiles(
      scanResult.files,
      onProgress: (current, total, result) {
        if (result != null) {
          progressEvents.add('$current/$total:${p.basename(result.source)}');
        }
      },
    );

    expect(results.length, 5);
    expect(results.where((result) => result.isSuccess).length, 4);
    expect(results.where((result) => !result.isSuccess).length, 1);
    expect(progressEvents.length, 5);

    final invalidResult = results.firstWhere((result) => result.source == p.absolute(invalidPath));
    expect(invalidResult.isSuccess, false);
    expect(invalidResult.error, contains('无法解析时间戳'));

    expect(
      await File(p.join(tempDir.path, 'basic.lrc')).readAsString(),
      '[00:01.00]第一行字幕\n[00:05.00]第二行字幕',
    );
    expect(
      await File(p.join(tempDir.path, 'html_tags.lrc')).readAsString(),
      '[00:01.00]粗体和斜体',
    );
    expect(
      await File(p.join(tempDir.path, 'bom.lrc')).readAsString(),
      '[00:02.00]UTF-8 BOM 测试',
    );
    expect(
      await File(p.join(nestedDir.path, 'gbk.lrc')).readAsString(),
      '[00:03.00]中文GBK测试',
    );
  });
}
