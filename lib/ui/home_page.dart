import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;

import '../core/vtt_converter.dart';
import '../core/file_scanner.dart';
import 'log_view.dart';
import 'drop_overlay.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<String> _selectedFiles = [];
  String _selectedDirectory = '';
  String _statusText = '未选择文件或目录';
  int _fileCount = 0;
  bool _canConvert = false;
  bool _isDragging = false;
  final List<LogEntry> _logEntries = [];

  // 转换进度状态
  bool _isConverting = false;
  int _convertedCount = 0;
  int _totalCount = 0;
  String _currentFile = '';

  String _timestamp() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
  }

  void _log(String msg, {Color? color}) {
    setState(() {
      _logEntries.add(LogEntry(
        timestamp: _timestamp(),
        message: msg,
        color: color,
      ));
    });
  }

  // ── 颜色常量 ──
  static const _colorSuccess = Color(0xFF34C759);
  static const _colorError = Color(0xFFFF3B30);
  static const _colorWarning = Color(0xFFFF9500);
  static const _colorInfo = Color(0xFF007AFF);
  static const _colorMuted = Color(0xFF8E8E93);

  void _setSelectedFiles(List<String> files, {String source = 'dialog'}) {
    setState(() {
      _selectedFiles = files;
      _selectedDirectory = '';
      _statusText = '已选择 ${files.length} 个文件';
      _canConvert = true;
      _fileCount = files.length;
    });
    _log(
      source == 'drop' ? '拖拽导入文件：' : '选择了文件：',
      color: _colorInfo,
    );
    for (final f in files) {
      _log('   ${p.basename(f)}', color: _colorMuted);
    }
  }

  void _setSelectedDirectory(String directory, {String source = 'dialog'}) {
    final vttFiles = scanDirectoryForVtt(
      directory,
      onWarning: (msg) => _log(msg, color: _colorWarning),
    );
    setState(() {
      _selectedDirectory = directory;
      _selectedFiles = [];
      _statusText =
          '${p.basename(directory)}/  — 发现 ${vttFiles.length} 个 VTT 文件';
      _canConvert = vttFiles.isNotEmpty;
      _fileCount = vttFiles.length;
    });
    _log(
      source == 'drop'
          ? '拖拽导入目录：$directory'
          : '扫描目录：$directory',
      color: _colorSuccess,
    );
    for (final f in vttFiles) {
      _log('   ${p.relative(f, from: directory)}', color: _colorMuted);
    }
  }

  // ── 交互逻辑 ──

  Future<void> _onSelectFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['vtt'],
      allowMultiple: true,
    );
    if (result != null && result.files.isNotEmpty) {
      final paths = result.paths.whereType<String>().toList();
      if (paths.isNotEmpty) _setSelectedFiles(paths);
    }
  }

  Future<void> _onSelectDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      _setSelectedDirectory(result);
    }
  }

  void _onClearSelection() {
    setState(() {
      _selectedFiles = [];
      _selectedDirectory = '';
      _statusText = '未选择文件或目录';
      _canConvert = false;
      _fileCount = 0;
    });
    _log('已清除选择', color: _colorWarning);
  }

  Future<void> _onConvert() async {
    if (_isConverting) return; // 防止重复点击

    List<String> filesToConvert = [];

    if (_selectedFiles.isNotEmpty) {
      filesToConvert = _selectedFiles;
    } else if (_selectedDirectory.isNotEmpty) {
      filesToConvert = scanDirectoryForVtt(
        _selectedDirectory,
        onWarning: (msg) => _log(msg, color: _colorWarning),
      );
    } else {
      _showAlert('提示', '请先选择要转换的 .vtt 文件或包含 VTT 文件的目录。');
      return;
    }

    if (filesToConvert.isEmpty) {
      _log('未找到可转换的 VTT 文件。', color: _colorError);
      _showAlert('提示', '没有找到可转换的 VTT 文件。');
      return;
    }

    // 设置转换状态
    setState(() {
      _isConverting = true;
      _convertedCount = 0;
      _totalCount = filesToConvert.length;
      _currentFile = '';
    });

    _log('开始转换 $_totalCount 个文件…', color: _colorInfo);

    final results = await convertFilesAsync(
      filesToConvert,
      onProgress: (current, total, result) {
        setState(() {
          _convertedCount = current;
          if (result != null) {
            _currentFile = p.basename(result.source);
          }
        });

        // 当 result 不为 null 时，表示转换已完成，记录日志
        if (result != null) {
          if (result.isSuccess) {
            _log(
              '✔ ${p.basename(result.source)}  →  ${p.basename(result.destination!)}',
              color: _colorSuccess,
            );
          } else {
            _log(
              '✘ ${p.basename(result.source)}  →  ${result.error}',
              color: _colorError,
            );
          }
        }
      },
    );

    // 重置转换状态
    setState(() {
      _isConverting = false;
      _convertedCount = 0;
      _totalCount = 0;
      _currentFile = '';
    });

    final successes = results.where((r) => r.isSuccess).toList();
    final failures = results.where((r) => !r.isSuccess).toList();

    if (failures.isNotEmpty) {
      _log(
        '转换结束：成功 ${successes.length} 个，失败 ${failures.length} 个。',
        color: _colorWarning,
      );
      final lines = <String>[
        '成功 ${successes.length} 个，失败 ${failures.length} 个。',
        '',
        '失败示例：',
      ];
      for (final r in failures.take(5)) {
        lines.add('- ${p.basename(r.source)}：${r.error}');
      }
      if (failures.length > 5) {
        lines.add('- ... 另有 ${failures.length - 5} 个失败');
      }
      final title = successes.isNotEmpty ? '完成（部分失败）' : '转换失败';
      _showAlert(title, lines.join('\n'));
      return;
    }

    if (successes.isNotEmpty) {
      _log('全部完成！共转换 ${successes.length} 个文件', color: _colorSuccess);
      _showAlert('完成', '已成功转换 ${successes.length} 个文件。');
    } else {
      _log('没有成功转换的文件。', color: _colorError);
      _showAlert('提示', '没有成功转换的文件。');
    }
  }

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

  // ── 进度指示器 ──

  Widget _buildProgressIndicator(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE8E8E8),
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
                  '正在转换: $_currentFile',
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
              value: _totalCount > 0 ? _convertedCount / _totalCount : 0,
              backgroundColor: isDark ? Colors.grey[700] : Colors.grey[300],
              valueColor: AlwaysStoppedAnimation(_colorInfo),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$_convertedCount / $_totalCount',
            style: TextStyle(fontSize: 11, color: _colorMuted),
          ),
        ],
      ),
    );
  }

  // ── 拖拽处理 ──

  void _onDragDone(DropDoneDetails details) {
    setState(() => _isDragging = false);
    final localPaths = details.files.map((f) => f.path).toList();
    if (localPaths.isEmpty) return;

    final directories = localPaths
        .where((p) => FileSystemEntity.isDirectorySync(p))
        .toList();
    final files = localPaths
        .where((p) => FileSystemEntity.isFileSync(p))
        .toList();

    if (localPaths.length == 1 && directories.isNotEmpty && files.isEmpty) {
      _setSelectedDirectory(directories.first, source: 'drop');
      return;
    }

    final vttFiles = collectVttFromPaths(
      localPaths,
      onWarning: (msg) => _log(msg, color: _colorWarning),
    );
    if (vttFiles.isNotEmpty) {
      if (directories.isNotEmpty && files.isNotEmpty) {
        _log('  (包含 ${directories.length} 个目录，已展开)', color: _colorMuted);
      }
      _setSelectedFiles(vttFiles, source: 'drop');
    } else {
      _log('拖拽内容中未找到可转换的 VTT 文件。', color: _colorError);
      _showAlert('提示', '拖拽内容中没有找到可转换的 VTT 文件。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MacosTheme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    return MacosScaffold(
      backgroundColor: isDark
          ? const Color(0xFF1E1E1E)
          : const Color(0xFFF5F5F5),
      children: [
        ContentArea(
          builder: (context, scrollController) {
            return Container(
              color: isDark
                  ? const Color(0xFF1E1E1E)
                  : const Color(0xFFF5F5F5),
              child: DropTarget(
                onDragEntered: (_) => setState(() => _isDragging = true),
                onDragExited: (_) => setState(() => _isDragging = false),
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
                            onPressed: (_canConvert && !_isConverting) ? _onConvert : null,
                            child: _isConverting
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
                          if (_isConverting) ...[
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
                                    color: isDark
                                        ? const Color(0xFF3A3A3A)
                                        : const Color(0xFFEEEEEE),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _statusText,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark
                                          ? const Color(0xFFE0E0E0)
                                          : const Color(0xFF444444),
                                    ),
                                  ),
                                ),
                              ),
                              if (_canConvert) ...[
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
                                  color: isDark
                                      ? const Color(0xFFE0E0E0)
                                      : const Color(0xFF444444),
                                ),
                              ),
                              const Spacer(),
                              if (_fileCount > 0)
                                Text(
                                  '共 $_fileCount 个文件',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? const Color(0xFF808080)
                                        : const Color(0xFF999999),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // ── 日志区域 ──
                          Expanded(
                            child: LogView(entries: _logEntries),
                          ),
                        ],
                      ),
                    ),

                  // ── 拖拽浮层 ──
                  DropOverlay(visible: _isDragging),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
