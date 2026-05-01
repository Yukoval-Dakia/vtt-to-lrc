import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import 'ui/app_colors.dart';
import 'ui/home_page.dart';
import 'services/services.dart';

/// 应用入口
/// 服务实例由 main.dart 统一注入，避免在不同入口构造出多份 RustBackendService
class VttToLrcApp extends StatelessWidget {
  final FilePickerService filePickerService;
  final ConversionService conversionService;
  final AppState appState;

  const VttToLrcApp({
    super.key,
    required this.filePickerService,
    required this.conversionService,
    required this.appState,
  });

  /// 仅用于 Widget 测试：内部构造一份独立的依赖图
  @visibleForTesting
  factory VttToLrcApp.forTest({
    Key? key,
    AppState? appState,
  }) {
    final backend = RustBackendService();
    return VttToLrcApp(
      key: key,
      filePickerService: FilePickerService(rustBackendService: backend),
      conversionService: ConversionService(rustBackendService: backend),
      appState: appState ?? AppState(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MacosApp(
      title: 'VTT → LRC 转换器',
      theme: MacosThemeData.light(),
      darkTheme: MacosThemeData.dark(),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) {
          final brightness = MacosTheme.of(context).brightness;
          final isDark = brightness == Brightness.dark;
          return MacosWindow(
            backgroundColor: AppThemeColors.background(isDark),
            child: HomePage(
              filePickerService: filePickerService,
              conversionService: conversionService,
              appState: appState,
            ),
          );
        },
      ),
    );
  }
}
