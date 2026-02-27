import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';

/// 单条日志
class LogEntry {
  final String timestamp;
  final String message;
  final Color? color;

  LogEntry({
    required this.timestamp,
    required this.message,
    this.color,
  });
}

/// 日志列表组件
class LogView extends StatefulWidget {
  final List<LogEntry> entries;

  const LogView({super.key, required this.entries});

  @override
  State<LogView> createState() => LogViewState();
}

class LogViewState extends State<LogView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entries.length > oldWidget.entries.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MacosTheme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final bgColor = isDark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFF5F5F5);
    final borderColor = isDark
        ? const Color(0xFF4A4A4A)
        : const Color(0xFFD0D0D0);
    final tsColor = isDark
        ? const Color(0xFFA0A0A0)
        : const Color(0xFF999999);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: widget.entries.isEmpty
          ? Center(
              child: Text(
                '操作日志将在此处显示…',
                style: TextStyle(
                  fontSize: 12,
                  color: tsColor,
                ),
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: widget.entries.length,
              itemBuilder: (context, index) {
                final entry = widget.entries[index];
                final defaultColor = isDark
                    ? const Color(0xFFE0E0E0)
                    : const Color(0xFF333333);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '[${entry.timestamp}] ',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'Menlo',
                            color: tsColor,
                          ),
                        ),
                        TextSpan(
                          text: entry.message,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'Menlo',
                            color: entry.color ?? defaultColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
