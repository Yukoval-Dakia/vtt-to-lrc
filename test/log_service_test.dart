import 'package:flutter_test/flutter_test.dart';
import 'package:vtt_to_lrc/services/log_service.dart';

void main() {
  test('日志超过上限时丢弃最旧条目', () {
    final service = LogService(maxEntries: 3);

    service.add('第一条', timestamp: '00:00:01');
    service.add('第二条', timestamp: '00:00:02');
    service.add('第三条', timestamp: '00:00:03');
    service.add('第四条', timestamp: '00:00:04');

    expect(service.entries.length, 3);
    expect(service.entries.map((entry) => entry.message).toList(), [
      '第二条',
      '第三条',
      '第四条',
    ]);
  });
}
