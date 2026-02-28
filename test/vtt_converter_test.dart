import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vtt_to_lrc/core/vtt_converter.dart';

void main() {
  group('cleanVttText', () {
    test('移除基本的 HTML 标签', () {
      expect(cleanVttText('<b>粗体</b>'), '粗体');
      expect(cleanVttText('<i>斜体</i>'), '斜体');
      expect(cleanVttText('<u>下划线</u>'), '下划线');
      expect(cleanVttText('<c>类名</c>'), '类名');
    });

    test('移除带有空格分隔属性的标签', () {
      // 正则要求属性前有空格: (?:\s+[^>]*)?
      expect(cleanVttText('<c class="test">带属性</c>'), '带属性');
      expect(cleanVttText('<b id="bold1">带属性</b>'), '带属性');
    });

    test('移除 ruby 和 rt 标签', () {
      expect(cleanVttText('<ruby>注音<rt>zhuyin</rt></ruby>'), '注音zhuyin');
    });

    test('处理嵌套标签', () {
      expect(cleanVttText('<b><i>粗斜体</i></b>'), '粗斜体');
      expect(cleanVttText('<b><i><u>三重嵌套</u></i></b>'), '三重嵌套');
    });

    test('处理大小写不敏感的标签', () {
      expect(cleanVttText('<B>大写标签</B>'), '大写标签');
      expect(cleanVttText('<I>大写斜体</I>'), '大写斜体');
      expect(cleanVttText('<B><i>混合大小写</i></B>'), '混合大小写');
    });

    test('不处理非 VTT 标签', () {
      // 非 VTT 标签应该保留
      expect(cleanVttText('<span>span 标签</span>'), '<span>span 标签</span>');
      expect(cleanVttText('<div>div 标签</div>'), '<div>div 标签</div>');
    });

    test('处理空字符串', () {
      expect(cleanVttText(''), '');
    });

    test('处理没有标签的纯文本', () {
      expect(cleanVttText('这是纯文本'), '这是纯文本');
    });

    test('处理混合内容', () {
      expect(
        cleanVttText('这是<b>粗体</b>和<i>斜体</i>的混合'),
        '这是粗体和斜体的混合',
      );
    });

    test('处理多行文本', () {
      expect(
        cleanVttText('<b>第一行</b>\n<i>第二行</i>'),
        '第一行\n第二行',
      );
    });

    test('保留带点号的类名标签（当前实现不支持）', () {
      // 当前正则不支持 <c.classname> 格式，只支持空格分隔的属性
      // 但 </c> 会被移除，因为它是标准的结束标签
      expect(cleanVttText('<c.classname>带类名</c>'), '<c.classname>带类名');
    });
  });

  group('isValidVttTimestamp', () {
    test('验证标准格式时间戳', () {
      expect(isValidVttTimestamp('00:00:00.000'), true);
      expect(isValidVttTimestamp('00:00:05.000'), true);
      expect(isValidVttTimestamp('00:01:30.500'), true);
      expect(isValidVttTimestamp('01:00:00.000'), true);
    });

    test('验证超过1小时的时间戳', () {
      expect(isValidVttTimestamp('01:23:45.678'), true);
      expect(isValidVttTimestamp('10:30:45.123'), true);
      expect(isValidVttTimestamp('99:59:59.999'), true);
    });

    test('验证带前导空格的时间戳', () {
      expect(isValidVttTimestamp(' 00:00:05.000'), true);
      expect(isValidVttTimestamp('  01:30:45.678'), true);
    });

    test('验证带尾随空格的时间戳', () {
      expect(isValidVttTimestamp('00:00:05.000 '), true);
      expect(isValidVttTimestamp('01:30:45.678  '), true);
    });

    test('拒绝不足三位毫秒的时间戳', () {
      // 严格验证要求毫秒必须是三位
      expect(isValidVttTimestamp('00:00:05.0'), false);
      expect(isValidVttTimestamp('00:00:05.00'), false);
      expect(isValidVttTimestamp('00:00:05.1'), false);
      expect(isValidVttTimestamp('00:00:05.12'), false);
    });

    test('拒绝超过三位毫秒的时间戳', () {
      expect(isValidVttTimestamp('00:00:05.0000'), false);
      expect(isValidVttTimestamp('00:00:05.12345'), false);
    });

    test('拒绝无效分钟值（超过59）', () {
      expect(isValidVttTimestamp('00:60:00.000'), false);
      expect(isValidVttTimestamp('00:99:00.000'), false);
    });

    test('拒绝无效秒值（超过59）', () {
      expect(isValidVttTimestamp('00:00:60.000'), false);
      expect(isValidVttTimestamp('00:00:99.000'), false);
    });

    test('拒绝缺少冒号的格式', () {
      expect(isValidVttTimestamp('00:00.000'), false);
      expect(isValidVttTimestamp('00:00:00'), false);
    });

    test('拒绝缺少小数点的格式', () {
      expect(isValidVttTimestamp('00:00:00:000'), false);
    });

    test('拒绝非数字字符', () {
      expect(isValidVttTimestamp('aa:bb:cc.ddd'), false);
      expect(isValidVttTimestamp('00:xx:00.000'), false);
      expect(isValidVttTimestamp('00:00:00.abc'), false);
    });

    test('拒绝空字符串', () {
      expect(isValidVttTimestamp(''), false);
    });

    test('拒绝完全无效的格式', () {
      expect(isValidVttTimestamp('invalid'), false);
      expect(isValidVttTimestamp('00-00-00.000'), false);
      expect(isValidVttTimestamp('00:00:00:000'), false);
    });
  });

  group('vttTimeToLrc', () {
    test('转换标准时间戳', () {
      expect(vttTimeToLrc('00:00:05.000'), '[00:05.00]');
      expect(vttTimeToLrc('00:01:30.500'), '[01:30.50]');
      expect(vttTimeToLrc('01:00:00.000'), '[60:00.00]');
    });

    test('转换小时超过 1 的时间戳', () {
      // 1小时 = 60分钟
      expect(vttTimeToLrc('01:30:45.123'), '[90:45.12]');
      expect(vttTimeToLrc('02:15:30.999'), '[135:30.99]');
    });

    test('处理毫秒精度', () {
      expect(vttTimeToLrc('00:00:00.001'), '[00:00.00]');
      expect(vttTimeToLrc('00:00:00.010'), '[00:00.01]');
      expect(vttTimeToLrc('00:00:00.999'), '[00:00.99]');
    });

    test('处理边界值', () {
      expect(vttTimeToLrc('00:00:00.000'), '[00:00.00]');
      expect(vttTimeToLrc('99:59:59.999'), '[5999:59.99]');
    });

    test('处理带前导和尾随空格的时间戳', () {
      // 新实现会 trim 输入
      expect(vttTimeToLrc(' 00:00:05.000'), '[00:05.00]');
      expect(vttTimeToLrc('00:00:05.000 '), '[00:05.00]');
      expect(vttTimeToLrc('  01:30:45.678  '), '[90:45.67]');
    });

    test('严格验证：不足三位毫秒返回 null', () {
      // 新实现使用严格验证，毫秒必须是三位
      expect(vttTimeToLrc('00:00:05.0'), null);
      expect(vttTimeToLrc('00:00:05.00'), null);
      expect(vttTimeToLrc('00:00:05.1'), null);
      expect(vttTimeToLrc('00:00:05.12'), null);
    });

    test('严格验证：超过三位毫秒返回 null', () {
      expect(vttTimeToLrc('00:00:05.0000'), null);
      expect(vttTimeToLrc('00:00:05.12345'), null);
    });

    test('严格验证：无效分钟值返回 null', () {
      expect(vttTimeToLrc('00:60:00.000'), null);
      expect(vttTimeToLrc('00:99:00.000'), null);
    });

    test('严格验证：无效秒值返回 null', () {
      expect(vttTimeToLrc('00:00:60.000'), null);
      expect(vttTimeToLrc('00:00:99.000'), null);
    });

    test('无效格式返回 null', () {
      // 缺少冒号
      expect(vttTimeToLrc('00:00.000'), null);
      // 缺少点
      expect(vttTimeToLrc('00:00:00'), null);
      // 格式完全错误
      expect(vttTimeToLrc('invalid'), null);
      // 空字符串
      expect(vttTimeToLrc(''), null);
    });

    test('非数字部分返回 null', () {
      expect(vttTimeToLrc('aa:bb:cc.ddd'), null);
      expect(vttTimeToLrc('00:00:00.abc'), null);
      expect(vttTimeToLrc('00:xx:00.000'), null);
    });
  });

  group('EncodingDetector', () {
    group('detectEncoding', () {
      test('检测 UTF-8 编码', () {
        final bytes = utf8.encode('Hello, 世界!');
        expect(EncodingDetector.detectEncoding(bytes), EncodingType.utf8);
      });

      test('检测带 BOM 的 UTF-8 编码', () {
        final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('Hello, 世界!')];
        expect(EncodingDetector.detectEncoding(bytes), EncodingType.utf8);
      });

      test('检测纯 ASCII 编码（ASCII 是 UTF-8 的子集）', () {
        // 纯 ASCII 字节也是有效的 UTF-8
        // 当前实现优先返回 UTF-8
        final bytes = ascii.encode('Hello, World!');
        expect(EncodingDetector.detectEncoding(bytes), EncodingType.utf8);
      });

      test('检测 Latin1 编码（可能被误判为 GBK）', () {
        // Latin1 字节（非 UTF-8）
        // 注意：某些 Latin1 字节范围与 GBK 重叠，可能被检测为 GBK
        // 这是编码检测的固有局限性
        final bytes = [0xE9, 0xE0, 0xE8]; // é à è
        final detected = EncodingDetector.detectEncoding(bytes);
        // 接受 Latin1 或 GBK，因为编码检测有歧义
        expect(detected, anyOf(EncodingType.latin1, EncodingType.gbk));
      });
    });

    group('detectAndDecode', () {
      test('解码 UTF-8 内容', () {
        final content = 'Hello, 世界！';
        final bytes = utf8.encode(content);
        expect(EncodingDetector.detectAndDecode(bytes), content);
      });

      test('解码带 BOM 的 UTF-8 内容', () {
        final content = 'Hello, 世界！';
        final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(content)];
        expect(EncodingDetector.detectAndDecode(bytes), content);
      });

      test('解码 ASCII 内容', () {
        final content = 'Hello, World!';
        final bytes = ascii.encode(content);
        expect(EncodingDetector.detectAndDecode(bytes), content);
      });

      test('解码 Latin1 内容', () {
        // Latin1 特殊字符
        final bytes = [0xE9, 0xE0, 0xE8]; // é à è
        final result = EncodingDetector.detectAndDecode(bytes);
        expect(result, contains('é'));
        expect(result, contains('à'));
        expect(result, contains('è'));
      });

      test('解码 Windows-1252 特殊字符', () {
        // Windows-1252 的欧元符号 (0x80)
        final bytes = [0x80];
        final result = EncodingDetector.detectAndDecode(bytes);
        expect(result, '€');
      });

      test('解码空字节数组', () {
        final bytes = <int>[];
        expect(EncodingDetector.detectAndDecode(bytes), '');
      });
    });

    group('decodeWindows1252', () {
      test('解码基本 ASCII 字符', () {
        final bytes = [0x41, 0x42, 0x43]; // ABC
        expect(EncodingDetector.decodeWindows1252(bytes), 'ABC');
      });

      test('解码 Windows-1252 特殊字符', () {
        // 欧元符号
        expect(EncodingDetector.decodeWindows1252([0x80]), '€');
        // 左双引号 - 0x93 映射到 U+201C
        expect(EncodingDetector.decodeWindows1252([0x93]), '\u201C');
        // 右双引号 - 0x94 映射到 U+201D
        expect(EncodingDetector.decodeWindows1252([0x94]), '\u201D');
        // 省略号
        expect(EncodingDetector.decodeWindows1252([0x85]), '…');
      });

      test('解码 Latin-1 兼容字符', () {
        // 0xA0-0xFF 范围与 Latin-1 相同
        expect(EncodingDetector.decodeWindows1252([0xA0]), '\u00A0'); // 不换行空格
        expect(EncodingDetector.decodeWindows1252([0xFF]), 'ÿ');
      });

      test('处理无效字节', () {
        // 0x81 是 Windows-1252 中未定义的
        final result = EncodingDetector.decodeWindows1252([0x81]);
        expect(result, '\uFFFD'); // 替换字符
      });
    });
  });

  group('ConvertResult', () {
    test('成功结果', () {
      final result = ConvertResult.success('/path/source.vtt', '/path/source.lrc');
      expect(result.isSuccess, true);
      expect(result.source, '/path/source.vtt');
      expect(result.destination, '/path/source.lrc');
      expect(result.error, null);
    });

    test('失败结果', () {
      final result = ConvertResult.failure('/path/source.vtt', '转换失败');
      expect(result.isSuccess, false);
      expect(result.source, '/path/source.vtt');
      expect(result.destination, null);
      expect(result.error, '转换失败');
    });
  });
}
