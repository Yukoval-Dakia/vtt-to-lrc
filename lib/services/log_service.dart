import 'package:flutter/material.dart';
import '../ui/log_view.dart' show LogEntry;

/// 日志服务
/// 负责管理日志条目的添加、获取和清除
class LogService {
  final List<LogEntry> _entries = [];

  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// 添加日志条目
  void add(String message, {Color? color, String? timestamp}) {
    _entries.add(LogEntry(
      timestamp: timestamp ?? _generateTimestamp(),
      message: message,
      color: color,
    ));
  }

  /// 清除所有日志
  void clear() {
    _entries.clear();
  }

  // 时间戳缓存：避免频繁创建 DateTime 对象
  static int _cachedTimestampSecond = -1;
  static String _cachedTimestampString = '';

  /// 生成时间戳字符串（带缓存优化）
  /// 同一秒内的多次调用返回缓存的结果，减少 DateTime 对象创建
  String _generateTimestamp() {
    final now = DateTime.now();
    final currentSecond = now.hour * 3600 + now.minute * 60 + now.second;

    // 如果在同一秒内，返回缓存的时间戳
    if (currentSecond == _cachedTimestampSecond) {
      return _cachedTimestampString;
    }

    // 更新缓存
    _cachedTimestampSecond = currentSecond;
    _cachedTimestampString =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    return _cachedTimestampString;
  }
}
