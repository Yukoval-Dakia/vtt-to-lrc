import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/log_view.dart' show LogEntry;
import 'log_service.dart';

/// 应用状态
/// 管理 UI 相关的状态，如选择的文件、转换进度等。
///
/// 颜色策略：本类只为自己产生的内部事件附带语义色（如"已选择文件"用 info、
/// "已清除"用 warning），外部调用方请通过 [addLog] 传入自己想要的颜色，
/// 避免在两处分别维护语义→颜色的映射。
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

    addLog(
      source == 'drop' ? '拖拽导入文件：' : '选择了文件：',
      color: AppColors.info,
    );
    for (final f in files) {
      addLog('   $f', color: AppColors.muted);
    }

    notifyListeners();
  }

  /// 设置选中的目录
  void setSelectedDirectory(String directory, List<String> vttFiles, {String source = 'dialog'}) {
    _selectedDirectory = directory;
    _selectedFiles = vttFiles;
    _statusText = '$directory/  — 发现 ${vttFiles.length} 个 VTT 文件';
    _canConvert = vttFiles.isNotEmpty;
    _fileCount = vttFiles.length;

    addLog(
      source == 'drop'
          ? '拖拽导入目录：$directory'
          : '扫描目录：$directory',
      color: AppColors.success,
    );
    for (final f in vttFiles) {
      addLog('   $f', color: AppColors.muted);
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

    addLog('已清除选择', color: AppColors.warning);
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

    addLog('开始转换 $total 个文件…', color: AppColors.info);
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

  /// 添加日志（支持自定义颜色）
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
  List<String> getFilesToConvert() => List<String>.unmodifiable(_selectedFiles);
}
