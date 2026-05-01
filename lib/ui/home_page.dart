import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;

import '../services/services.dart';
import 'app_colors.dart';
import 'log_view.dart';
import 'drop_overlay.dart';

/// 主页组件
/// 使用服务层处理业务逻辑，UI 只负责显示
class HomePage extends StatefulWidget {
  final FilePickerService filePickerService;
  final ConversionService conversionService;
  final AppState appState;

  const HomePage({
    super.key,
    required this.filePickerService,
    required this.conversionService,
    required this.appState,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 应用状态
  late final AppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = widget.appState;
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
          backgroundColor: AppColors.error,
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
        onWarning: (msg) => _appState.addLog(msg, color: AppColors.warning),
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
        onWarning: (msg) => _appState.addLog(msg, color: AppColors.warning),
        onLog: (msg) => _appState.addLog(msg, color: AppColors.muted),
      );

      if (result != null && result.files.isNotEmpty) {
        if (result.directory != null) {
          _appState.setSelectedDirectory(result.directory!, result.files, source: 'drop');
        } else {
          _appState.setSelectedFiles(result.files, source: 'drop');
        }
      } else {
        _appState.addLog('拖拽内容中未找到可转换的 VTT 文件。', color: AppColors.error);
        _showAlert('提示', '拖拽内容中没有找到可转换的 VTT 文件。');
      }
    } catch (e) {
      _showError('拖拽处理', e);
    }
  }

  // ── 转换处理 ──

  Future<void> _onConvert() async {
    if (_appState.isConverting) return;

    final filesToConvert = _appState.getFilesToConvert();

    if (filesToConvert.isEmpty) {
      _appState.addLog('未找到可转换的 VTT 文件。', color: AppColors.error);
      _showAlert('提示', '请先选择要转换的 .vtt 文件或包含 VTT 文件的目录。');
      return;
    }

    _appState.startConversion(filesToConvert.length);
    try {
      final summary = await widget.conversionService.convertFiles(
        filesToConvert,
        onProgress: _onConversionProgress,
        onLog: _onConversionLog,
        onWarning: _onConversionWarning,
      );
      _handleConversionResult(summary);
    } on ConversionException catch (e) {
      _appState.addLog(e.message, color: AppColors.error);
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
      color: isError ? AppColors.error : null,
    );
  }

  void _onConversionWarning(String message) {
    _appState.addLog(message, color: AppColors.warning);
  }

  void _handleConversionResult(ConversionSummary summary) {
    if (summary.hasFailures) {
      _appState.addLog(
        '转换结束：成功 ${summary.successCount} 个，失败 ${summary.failureCount} 个。',
        color: AppColors.warning,
      );

      final title = summary.successCount > 0 ? '完成（部分失败）' : '转换失败';
      _showAlert(title, summary.getFailureSummary().join('\n'));
      return;
    }

    if (summary.allSucceeded) {
      _appState.addLog(
        '全部完成！共转换 ${summary.successCount} 个文件',
        color: AppColors.success,
      );
      _showAlert('完成', '已成功转换 ${summary.successCount} 个文件。');
    } else {
      _appState.addLog('没有成功转换的文件。', color: AppColors.error);
      _showAlert('提示', '没有成功转换的文件。');
    }
  }

  // ── UI 构建 ──

  @override
  Widget build(BuildContext context) {
    final brightness = MacosTheme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    return MacosScaffold(
      backgroundColor: AppThemeColors.background(isDark),
      children: [
        ContentArea(
          builder: (context, scrollController) {
            return Container(
              color: AppThemeColors.background(isDark),
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
                                    color: AppThemeColors.surface(isDark),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _appState.statusText,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppThemeColors.textPrimary(isDark),
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
                                  color: AppThemeColors.textPrimary(isDark),
                                ),
                              ),
                              const Spacer(),
                              if (_appState.fileCount > 0)
                                Text(
                                  '共 ${_appState.fileCount} 个文件',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppThemeColors.textSecondary(isDark),
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
        color: AppThemeColors.progressBackground(isDark),
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
              backgroundColor: AppThemeColors.progressTrack(isDark),
              valueColor: const AlwaysStoppedAnimation(AppColors.info),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_appState.convertedCount} / ${_appState.totalCount}',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
