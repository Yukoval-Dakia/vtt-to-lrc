import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import 'ui/home_page.dart';

class VttToLrcApp extends StatelessWidget {
  const VttToLrcApp({super.key});

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
            backgroundColor: isDark
                ? const Color(0xFF1E1E1E)  // 深色模式背景
                : const Color(0xFFF5F5F5), // 浅色模式背景
            child: const HomePage(),
          );
        },
      ),
    );
  }
}
