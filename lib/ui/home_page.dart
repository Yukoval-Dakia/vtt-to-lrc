import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;

import '../services/services.dart';
import '../core/vtt_converter.dart' show ConvertResult;
import '../core/file_scanner.dart' show scanDirectoryForVtt;
import 'log_view.dart';
import 'drop_overlay.dart';

/// 应用颜色配置
/// 统一管理所有颜色，支持深色/浅色主题
class _AppColors {
  // ── 语义颜色 ──
  static const Color success = Color(0xFF34C759);
  static const Color error = Color(0xFFFF3B30);
  static const Color warning = Color(0xFFFF9500);
  static const Color info = Color(0xFF007AFF);
  static const Color muted = Color(0xFF8E8E93);

  // ── 背景颜色 ──
  /// 主背景色
  static const Color backgroundLight = Color(0xFFF5F5F5);
  static const Color backgroundDark = Color(0xFF1E1E1E);

  /// 状态行/卡片背景色
  static const Color surfaceLight = Color(0xFFEEEEEE);
  static const Color surfaceDark = Color(0xFF3A3A3A);

  /// 进度指示器背景色
  static const Color progressBackgroundLight = Color(0xFFE8E8E8);
  static const Color progressBackgroundDark = Color(0xFF2A2A2A);

  // ── 文本颜色 ──
  /// 主要文本颜色
  static const Color textPrimaryLight = Color(0xFF444444);
  static const Color textPrimaryDark = Color(0xFFE0E0E0);

  /// 次要文本颜色
  static const Color textSecondaryLight = Color(0xFF999999);
  static const Color textSecondaryDark = Color(0xFF808080);

  // ── 便捷方法 ──
  /// 根据亮度获取主背景色
  static Color background(bool isDark) =>
      isDark ? backgroundDark : backgroundLight;

  /// 根据亮度获取表面颜色
  static Color surface(bool isDark) =>
      isDark ? surfaceDark : surfaceLight;

  /// 根据亮度获取进度背景色
  static Color progressBackground(bool isDark) =>
      isDark ? progressBackgroundDark : progressBackgroundLight;

  /// 根据亮度获取主要文本颜色
  static Color textPrimary(bool isDark) =>
      isDark ? textPrimaryDark : textPrimaryLight;

  /// 根据亮度获取次要文本颜色
  static Color textSecondary(bool isDark) =>
      isDark ? textSecondaryDark : textSecondaryLight;

  /// 根据亮度获取进度条背景色
  static Color progressIndicatorBackground(bool isDark) =>
      isDark ? Colors.grey[700]! : Colors.grey[300]!;
}

/// 主页组件
/// 使用服务层处理业务逻辑，UI 只负责显示
class HomePage extends StatefulWidget {
  final FilePickerService filePickerService;
  final ConversionService conversionService;

  HomePage({
    super.key,
    FilePickerService? filePickerService,
    ConversionService? conversionService,
  }) : filePickerService = filePickerService ?? FilePickerService(),
       conversionService = conversionService ?? ConversionService();

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 应用状态
  final AppState _appState = AppState();

  @override
  void initState() {
    super.initState();
    _appState.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _appState.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // ── 错误处理 ──

  /// 显示错误提示
  void _showError(String operation, Object error) {
    stderr.writeln('$operation失败: $error');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$operation失败: ${error.toString()}'),
          backgroundColor: _AppColors.error,
        ),
      );
    }
  }

  /// 显示警告对话框
  void _showAlert(String title, String message) {
    showMacosAlertDialog(
      context: context,
      builder: (_) => MacosAlertDialog(
        appIcon: const FlutterLogo(size: 48),
        title: Text(title),
        message: Text(message),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('确定'),
        ),
      ),
    );
  }

  // ── 文件选择处理 ──

  Future<void> _onSelectFiles() async {
    try {
      final result = await widget.filePickerService.pickFiles();
      if (result != null) {
        _appState.setSelectedFiles(result.files);
      }
    } on FilePickerException catch (e) {
      _showError('文件选择', e);
    } catch (e) {
      _showError('文件选择', e);
    }
  }

  Future<void> _onSelectDirectory() async {
    try {
      final result = await widget.filePickerService.pickDirectory(
        onWarning: (msg) => _appState.addLog(msg, color: _AppColors.warning),
      );
      if (result != null) {
        _appState.setSelectedDirectory(
          result.directory!,
          result.files,
        );
      }
    } on FilePickerException catch (e) {
      _showError('目录选择', e);
    } catch (e) {
      _showError('目录选择', e);
    }
  }

  void _onClearSelection() {
    _appState.clearSelection();
  }

  // ── 拖拽处理 ──

  void _onDragDone(DropDoneDetails details) {
    _appState.setDragging(false);
    final localPaths = details.files.map((f) => f.path).toList();
    if (localPaths.isEmpty) return;

    _processDroppedPaths(localPaths);
  }

  Future<void> _processDroppedPaths(List<String> paths) async {
    try {
      final result = await widget.filePickerService.processDroppedFiles(
        paths,
        onWarning: (msg) => _appState.addLog(msg, color: _AppColors.warning),
        onLog: (msg) => _appState.addLog(msg, color: _AppColors.muted),
      );

      if (result != null && result.files.isNotEmpty) {
        if (result.directory != null) {
          _appState.setSelectedDirectory(result.directory!, result.files, source: 'drop');
        } else {
          _appState.setSelectedFiles(result.files, source: 'drop');
        }
      } else {
        _appState.addLog('拖拽内容中未找到可转换的 VTT 文件。', color: _AppColors.error);
        _showAlert('提示', '拖拽内容中没有找到可转换的 VTT 文件。');
      }
    } catch (e) {
      _showError('拖拽处理', e);
    }
  }

  // ── 转换处理 ──

  Future<void> _onConvert() async {
    if (_appState.isConverting) return;

    var filesToConvert = _appState.selectedFiles.toList();

    // If no files selected but a directory is chosen, scan it first
    if (filesToConvert.isEmpty && _appState.selectedDirectory.isNotEmpty) {
      filesToConvert = await scanDirectoryForVtt(
        _appState.selectedDirectory,
        onWarning: (msg) => _appState.addLog(msg, color: _AppColors.warning),
      );
      if (filesToConvert.isEmpty) {
        _appState.addLog('目录中没有找到可转换的 VTT 文件。', color: _AppColors.error);
        _showAlert('提示', '目录中没有找到可转换的 VTT 文件。');
        return;
      }
    }

    if (filesToConvert.isEmpty) {
      _appState.addLog('未找到可转换的 VTT 文件。', color: _AppColors.error);
      _showAlert('提示', '请先选择要转换的 .vtt 文件或包含 VTT 文件的目录。');
      return;
    }

    _appState.startConversion(filesToConvert.length);
    try {
      final summary = await widget.conversionService.convertFiles(
        filesToConvert,
        onProgress: _onConversionProgress,
        onLog: _onConversionLog,
      );
      _handleConversionResult(summary);
    } on ConversionException catch (e) {
      _appState.addLog(e.message, color: _AppColors.error);
      _showAlert('提示', e.message);
    } catch (e) {
      _showError('转换', e);
    } finally {
      _appState.finishConversion();
    }
  }

  void _onConversionProgress(int current, int total, ConvertResult? result) {
    _appState.updateProgress(
      current,
      currentFile: result != null ? p.basename(result.source) : null,
    );
  }

  void _onConversionLog(String message, bool isError) {
    _appState.addLog(
      message,
      color: isError ? _AppColors.error : null,
    );
  }

  void _handleConversionResult(ConversionSummary summary) {
    if (summary.hasFailures) {
      _appState.addLog(
        '转换结束：成功 ${summary.successCount} 个，失败 ${summary.failureCount} 个。',
        color: _AppColors.warning,
      );

      final title = summary.successCount > 0 ? '完成（部分失败）' : '转换失败';
      _showAlert(title, summary.getFailureSummary().join('\n'));
      return;
    }

    if (summary.allSucceeded) {
      _appState.addLog(
        '全部完成！共转换 ${summary.successCount} 个文件',
        color: _AppColors.success,
      );
      _showAlert('完成', '已成功转换 ${summary.successCount} 个文件。');
    } else {
      _appState.addLog('没有成功转换的文件。', color: _AppColors.error);
      _showAlert('提示', '没有成功转换的文件。');
    }
  }

  // ── UI 构建 ──

  @override
  Widget build(BuildContext context) {
    final brightness = MacosTheme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    return MacosScaffold(
      backgroundColor: _AppColors.background(isDark),
      children: [
        ContentArea(
          builder: (context, scrollController) {
            return Container(
              color: _AppColors.background(isDark),
              child: DropTarget(
                onDragEntered: (_) => _appState.setDragging(true),
                onDragExited: (_) => _appState.setDragging(false),
                onDragDone: _onDragDone,
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── 操作按钮行 ──
                          Row(
                            children: [
                              Expanded(
                                child: PushButton(
                                  controlSize: ControlSize.large,
                                  secondary: true,
                                  onPressed: _onSelectFiles,
                                  child: const Text('选择文件'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: PushButton(
                                  controlSize: ControlSize.large,
                                  secondary: true,
                                  onPressed: _onSelectDirectory,
                                  child: const Text('选择目录'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // ── 开始转换按钮 ──
                          PushButton(
                            controlSize: ControlSize.large,
                            onPressed: (_appState.canConvert && !_appState.isConverting)
                                ? _onConvert
                                : null,
                            child: _appState.isConverting
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CupertinoActivityIndicator(
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Text('转换中...'),
                                    ],
                                  )
                                : const Text('开始转换'),
                          ),

                          // ── 进度指示器 ──
                          if (_appState.isConverting) ...[
                            const SizedBox(height: 12),
                            _buildProgressIndicator(isDark),
                          ],
                          const SizedBox(height: 16),

                          // ── 状态行 ──
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _AppColors.surface(isDark),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _appState.statusText,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: _AppColors.textPrimary(isDark),
                                    ),
                                  ),
                                ),
                              ),
                              if (_appState.canConvert) ...[
                                const SizedBox(width: 8),
                                PushButton(
                                  controlSize: ControlSize.small,
                                  secondary: true,
                                  onPressed: _onClearSelection,
                                  child: const Text('清除'),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),

                          // ── 日志标题行 ──
                          Row(
                            children: [
                              Text(
                                '操作日志',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _AppColors.textPrimary(isDark),
                                ),
                              ),
                              const Spacer(),
                              if (_appState.fileCount > 0)
                                Text(
                                  '共 ${_appState.fileCount} 个文件',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _AppColors.textSecondary(isDark),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // ── 日志区域 ──
                          Expanded(
                            child: LogView(entries: _appState.logEntries),
                          ),
                        ],
                      ),
                    ),

                    // ── 拖拽浮层 ──
                    DropOverlay(visible: _appState.isDragging),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ── 进度指示器 ──

  Widget _buildProgressIndicator(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _AppColors.progressBackground(isDark),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CupertinoActivityIndicator(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '正在转换: ${_appState.currentFile}',
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _appState.totalCount > 0
                  ? _appState.convertedCount / _appState.totalCount
                  : 0,
              backgroundColor: _AppColors.progressIndicatorBackground(isDark),
              valueColor: const AlwaysStoppedAnimation(_AppColors.info),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_appState.convertedCount} / ${_appState.totalCount}',
            style: const TextStyle(fontSize: 11, color: _AppColors.muted),
          ),
        ],
      ),
    );
  }
}
