import 'package:flutter/material.dart';
import '../ui/log_view.dart' show LogEntry;
import 'log_service.dart';

/// 应用状态
/// 管理 UI 相关的状态，如选择的文件、转换进度等
class AppState extends ChangeNotifier {
  // 文件选择状态
  List<String> _selectedFiles = [];
  String _selectedDirectory = '';
  String _statusText = '未选择文件或目录';
  int _fileCount = 0;
  bool _canConvert = false;

  // 拖拽状态
  bool _isDragging = false;

  // 转换进度状态
  bool _isConverting = false;
  int _convertedCount = 0;
  int _totalCount = 0;
  String _currentFile = '';

  // 日志服务
  final LogService _logService = LogService();

  // Getters
  List<String> get selectedFiles => List.unmodifiable(_selectedFiles);
  String get selectedDirectory => _selectedDirectory;
  String get statusText => _statusText;
  int get fileCount => _fileCount;
  bool get canConvert => _canConvert;
  bool get isDragging => _isDragging;
  bool get isConverting => _isConverting;
  int get convertedCount => _convertedCount;
  int get totalCount => _totalCount;
  String get currentFile => _currentFile;
  List<LogEntry> get logEntries => _logService.entries;

  /// 设置选中的文件
  void setSelectedFiles(List<String> files, {String source = 'dialog'}) {
    _selectedFiles = files;
    _selectedDirectory = '';
    _statusText = '已选择 ${files.length} 个文件';
    _canConvert = true;
    _fileCount = files.length;

    _log(
      source == 'drop' ? '拖拽导入文件：' : '选择了文件：',
      isInfo: true,
    );
    for (final f in files) {
      _log('   $f', isMuted: true);
    }

    notifyListeners();
  }

  /// 设置选中的目录
  void setSelectedDirectory(String directory, List<String> vttFiles, {String source = 'dialog'}) {
    _selectedDirectory = directory;
    _selectedFiles = [];
    _statusText = '$directory/  — 发现 ${vttFiles.length} 个 VTT 文件';
    _canConvert = vttFiles.isNotEmpty;
    _fileCount = vttFiles.length;

    _log(
      source == 'drop'
          ? '拖拽导入目录：$directory'
          : '扫描目录：$directory',
      isSuccess: true,
    );
    for (final f in vttFiles) {
      _log('   $f', isMuted: true);
    }

    notifyListeners();
  }

  /// 清除选择
  void clearSelection() {
    _selectedFiles = [];
    _selectedDirectory = '';
    _statusText = '未选择文件或目录';
    _canConvert = false;
    _fileCount = 0;

    _log('已清除选择', isWarning: true);
    notifyListeners();
  }

  /// 设置拖拽状态
  void setDragging(bool value) {
    _isDragging = value;
    notifyListeners();
  }

  /// 开始转换
  void startConversion(int total) {
    _isConverting = true;
    _convertedCount = 0;
    _totalCount = total;
    _currentFile = '';

    _log('开始转换 $total 个文件…', isInfo: true);
    notifyListeners();
  }

  /// 更新转换进度
  void updateProgress(int current, {String? currentFile}) {
    _convertedCount = current;
    if (currentFile != null) {
      _currentFile = currentFile;
    }
    notifyListeners();
  }

  /// 完成转换
  void finishConversion() {
    _isConverting = false;
    _convertedCount = 0;
    _totalCount = 0;
    _currentFile = '';
    notifyListeners();
  }

  /// 添加日志
  void _log(
    String message, {
    bool isError = false,
    bool isSuccess = false,
    bool isWarning = false,
    bool isInfo = false,
    bool isMuted = false,
  }) {
    Color? color;
    if (isError) color = const Color(0xFFFF3B30);
    if (isSuccess) color = const Color(0xFF34C759);
    if (isWarning) color = const Color(0xFFFF9500);
    if (isInfo) color = const Color(0xFF007AFF);

    _logService.add(message, color: color);
    notifyListeners();
  }

  /// 添加外部日志（带颜色）
  void addLog(String message, {Color? color}) {
    _logService.add(message, color: color);
    notifyListeners();
  }

  /// 清除日志
  void clearLogs() {
    _logService.clear();
    notifyListeners();
  }

  /// 获取要转换的文件列表
  List<String> getFilesToConvert() {
    if (_selectedFiles.isNotEmpty) {
      return _selectedFiles;
    }
    return [];
  }

  /// 获取要扫描的目录
  String? getDirectoryToScan() {
    if (_selectedDirectory.isNotEmpty) {
      return _selectedDirectory;
    }
    return null;
  }
}
