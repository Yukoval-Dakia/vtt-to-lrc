import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:vtt_to_lrc/services/services.dart';
import 'package:vtt_to_lrc/ui/home_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HomePage 使用注入的 AppState 渲染状态文本', (tester) async {
    final appState = AppState();
    appState.setSelectedFiles(['/tmp/demo.vtt']);

    await tester.pumpWidget(
      MacosApp(
        theme: MacosThemeData.light(),
        darkTheme: MacosThemeData.dark(),
        home: MacosWindow(
          child: HomePage(
            filePickerService: FilePickerService(),
            conversionService: ConversionService(),
            appState: appState,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('已选择 1 个文件'), findsOneWidget);
    expect(find.text('共 1 个文件'), findsOneWidget);
    expect(find.text('清除'), findsOneWidget);
  });
}
