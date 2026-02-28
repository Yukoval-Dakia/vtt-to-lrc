import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vtt_to_lrc/core/vtt_converter.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUpAll(() async {
    // 创建临时目录用于测试
    tempDir = await Directory.systemTemp.createTemp('vtt_test_');
  });

  tearDownAll(() async {
    // 清理临时目录
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('convertVttToLrc / convertVttToLrcAsync', () {
    test('转换标准 VTT 文件', () async {
      // 创建测试 VTT 文件
      final vttContent = '''WEBVTT

00:00:01.000 --> 00:00:04.000
第一行字幕

00:00:05.000 --> 00:00:08.000
第二行字幕
''';
      final vttPath = p.join(tempDir.path, 'test1.vtt');
      await File(vttPath).writeAsString(vttContent);

      // 执行转换
      final lrcPath = await convertVttToLrcAsync(vttPath);

      // 验证输出文件存在
      expect(await File(lrcPath).exists(), true);
      expect(lrcPath.endsWith('.lrc'), true);

      // 验证输出内容
      final lrcContent = await File(lrcPath).readAsString();
      expect(lrcContent, contains('[00:01.00]第一行字幕'));
      expect(lrcContent, contains('[00:05.00]第二行字幕'));

      // 清理
      await File(vttPath).delete();
      await File(lrcPath).delete();
    });

    test('转换带 HTML 标签的 VTT 文件', () async {
      final vttContent = '''WEBVTT

00:00:01.000 --> 00:00:04.000
<b>粗体</b>和<i>斜体</i>
''';
      final vttPath = p.join(tempDir.path, 'test2.vtt');
      await File(vttPath).writeAsString(vttContent);

      final lrcPath = await convertVttToLrcAsync(vttPath);
      final lrcContent = await File(lrcPath).readAsString();

      // 标签应该被清理
      expect(lrcContent, contains('[00:01.00]粗体和斜体'));
      expect(lrcContent.contains('<b>'), false);
      expect(lrcContent.contains('</b>'), false);

      // 清理
      await File(vttPath).delete();
      await File(lrcPath).delete();
    });

    test('转换多行文本的 VTT 文件', () async {
      final vttContent = '''WEBVTT

00:00:01.000 --> 00:00:04.000
第一行
第二行

00:00:05.000 --> 00:00:08.000
第三行
''';
      final vttPath = p.join(tempDir.path, 'test3.vtt');
      await File(vttPath).writeAsString(vttContent);

      final lrcPath = await convertVttToLrcAsync(vttPath);
      final lrcContent = await File(lrcPath).readAsString();

      // 多行文本应该合并为一行
      expect(lrcContent, contains('[00:01.00]第一行 第二行'));

      // 清理
      await File(vttPath).delete();
      await File(lrcPath).delete();
    });

    test('转换超过1小时的 VTT 时间戳', () async {
      final vttContent = '''WEBVTT

01:30:45.500 --> 01:30:50.500
长时间字幕
''';
      final vttPath = p.join(tempDir.path, 'test4.vtt');
      await File(vttPath).writeAsString(vttContent);

      final lrcPath = await convertVttToLrcAsync(vttPath);
      final lrcContent = await File(lrcPath).readAsString();

      // 1小时30分 = 90分钟
      expect(lrcContent, contains('[90:45.50]长时间字幕'));

      // 清理
      await File(vttPath).delete();
      await File(lrcPath).delete();
    });

    test('转换 UTF-8 BOM 编码的 VTT 文件', () async {
      final vttContent = '''WEBVTT

00:00:01.000 --> 00:00:04.000
UTF-8 BOM 测试
''';
      // 添加 UTF-8 BOM
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(vttContent)];
      final vttPath = p.join(tempDir.path, 'test5.vtt');
      await File(vttPath).writeAsBytes(bytes);

      final lrcPath = await convertVttToLrcAsync(vttPath);
      final lrcContent = await File(lrcPath).readAsString();

      expect(lrcContent, contains('[00:01.00]UTF-8 BOM 测试'));

      // 清理
      await File(vttPath).delete();
      await File(lrcPath).delete();
    });

    test('转换不存在的文件抛出异常', () async {
      final nonExistentPath = p.join(tempDir.path, 'non_existent.vtt');
      
      expect(
        () => convertVttToLrcAsync(nonExistentPath),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('转换无效时间戳格式的 VTT 抛出异常', () async {
      final vttContent = '''WEBVTT

invalid_timestamp --> 00:00:04.000
无效时间戳
''';
      final vttPath = p.join(tempDir.path, 'test6.vtt');
      await File(vttPath).writeAsString(vttContent);

      expect(
        () => convertVttToLrcAsync(vttPath),
        throwsA(isA<FormatException>()),
      );

      // 清理
      await File(vttPath).delete();
    });
  });

  group('convertFilesAsync', () {
    test('批量转换多个 VTT 文件', () async {
      // 创建多个测试文件
      final vtt1Content = '''WEBVTT

00:00:01.000 --> 00:00:04.000
文件一
''';
      final vtt2Content = '''WEBVTT

00:00:02.000 --> 00:00:05.000
文件二
''';
      
      final vtt1Path = p.join(tempDir.path, 'batch1.vtt');
      final vtt2Path = p.join(tempDir.path, 'batch2.vtt');
      
      await File(vtt1Path).writeAsString(vtt1Content);
      await File(vtt2Path).writeAsString(vtt2Content);

      // 执行批量转换
      final results = await convertFilesAsync([vtt1Path, vtt2Path]);

      // 验证结果
      expect(results.length, 2);
      expect(results.every((r) => r.isSuccess), true);

      // 清理
      for (final result in results) {
        await File(result.source).delete();
        if (result.destination != null) {
          await File(result.destination!).delete();
        }
      }
    });

    test('批量转换包含非 VTT 文件', () async {
      final vttContent = '''WEBVTT

00:00:01.000 --> 00:00:04.000
VTT 文件
''';
      final vttPath = p.join(tempDir.path, 'only_vtt.vtt');
      final txtPath = p.join(tempDir.path, 'not_vtt.txt');
      
      await File(vttPath).writeAsString(vttContent);
      await File(txtPath).writeAsString('这不是 VTT 文件');

      // 执行批量转换
      final results = await convertFilesAsync([vttPath, txtPath]);

      // 只有 VTT 文件应该被转换
      expect(results.length, 1);
      expect(results[0].isSuccess, true);
      expect(results[0].source, vttPath);

      // 清理
      await File(vttPath).delete();
      await File(txtPath).delete();
      if (results[0].destination != null) {
        await File(results[0].destination!).delete();
      }
    });

    test('批量转换空列表返回空结果', () async {
      final results = await convertFilesAsync([]);
      expect(results, isEmpty);
    });

    test('批量转换带进度回调', () async {
      final vttContent = '''WEBVTT

00:00:01.000 --> 00:00:04.000
进度测试
''';
      final vtt1Path = p.join(tempDir.path, 'progress1.vtt');
      final vtt2Path = p.join(tempDir.path, 'progress2.vtt');
      
      await File(vtt1Path).writeAsString(vttContent);
      await File(vtt2Path).writeAsString(vttContent);

      final progressCalls = <String>[];
      
      await convertFilesAsync(
        [vtt1Path, vtt2Path],
        onProgress: (current, total, result) {
          progressCalls.add('$current/$total');
        },
      );

      // 验证进度回调被调用
      expect(progressCalls.length, greaterThanOrEqualTo(2));
      expect(progressCalls.last, '2/2');

      // 清理
      await File(vtt1Path).delete();
      await File(vtt2Path).delete();
      final lrc1Path = p.join(tempDir.path, 'progress1.lrc');
      final lrc2Path = p.join(tempDir.path, 'progress2.lrc');
      if (await File(lrc1Path).exists()) await File(lrc1Path).delete();
      if (await File(lrc2Path).exists()) await File(lrc2Path).delete();
    });
  });
}
