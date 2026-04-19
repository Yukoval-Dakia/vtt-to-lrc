import 'package:flutter_test/flutter_test.dart';
import 'package:vtt_to_lrc/services/app_state.dart';

void main() {
  test('设置文件后可以清空选择并恢复初始状态', () {
    final appState = AppState();

    appState.setSelectedFiles(['/tmp/a.vtt', '/tmp/b.vtt']);
    expect(appState.canConvert, isTrue);
    expect(appState.fileCount, 2);
    expect(appState.statusText, '已选择 2 个文件');

    appState.clearSelection();

    expect(appState.canConvert, isFalse);
    expect(appState.fileCount, 0);
    expect(appState.selectedFiles, isEmpty);
    expect(appState.selectedDirectory, '');
    expect(appState.statusText, '未选择文件或目录');
  });
}
