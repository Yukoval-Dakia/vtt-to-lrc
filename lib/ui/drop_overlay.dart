import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';

/// 拖拽提示浮层
class DropOverlay extends StatelessWidget {
  final bool visible;

  const DropOverlay({super.key, required this.visible});

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final brightness = MacosTheme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    return Positioned.fill(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xE6141218)
              : const Color(0xE6FFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? const Color(0xFF6699FF)
                : const Color(0xFF0066CC),
            width: 2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                const IconData(0xF090, fontFamily: 'CupertinoIcons', fontPackage: 'cupertino_icons'),
                size: 48,
                color: isDark
                    ? const Color(0xFF6699FF)
                    : const Color(0xFF0066CC),
              ),
              const SizedBox(height: 12),
              Text(
                '拖拽文件或目录到此处',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? const Color(0xFF6699FF)
                      : const Color(0xFF0066CC),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
