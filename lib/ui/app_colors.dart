import 'package:flutter/material.dart';

/// 语义色板：状态/反馈相关，无需关心主题
class AppColors {
  static const Color success = Color(0xFF34C759);
  static const Color error = Color(0xFFFF3B30);
  static const Color warning = Color(0xFFFF9500);
  static const Color info = Color(0xFF007AFF);
  static const Color muted = Color(0xFF8E8E93);
}

/// 主题相关的中性色：背景、表面、文本，按亮/暗模式分别取值
class AppThemeColors {
  AppThemeColors._();

  // ── 背景 ──
  static const Color _backgroundLight = Color(0xFFF5F5F5);
  static const Color _backgroundDark = Color(0xFF1E1E1E);

  // ── 状态行/卡片表面 ──
  static const Color _surfaceLight = Color(0xFFEEEEEE);
  static const Color _surfaceDark = Color(0xFF3A3A3A);

  // ── 进度容器背景 ──
  static const Color _progressBackgroundLight = Color(0xFFE8E8E8);
  static const Color _progressBackgroundDark = Color(0xFF2A2A2A);

  // ── 进度条轨道 ──
  static const Color _progressTrackLight = Color(0xFFE0E0E0);
  static const Color _progressTrackDark = Color(0xFF707070);

  // ── 主要文本 ──
  static const Color _textPrimaryLight = Color(0xFF444444);
  static const Color _textPrimaryDark = Color(0xFFE0E0E0);

  // ── 次要文本 ──
  static const Color _textSecondaryLight = Color(0xFF999999);
  static const Color _textSecondaryDark = Color(0xFF808080);

  static Color background(bool isDark) =>
      isDark ? _backgroundDark : _backgroundLight;

  static Color surface(bool isDark) =>
      isDark ? _surfaceDark : _surfaceLight;

  static Color progressBackground(bool isDark) =>
      isDark ? _progressBackgroundDark : _progressBackgroundLight;

  static Color progressTrack(bool isDark) =>
      isDark ? _progressTrackDark : _progressTrackLight;

  static Color textPrimary(bool isDark) =>
      isDark ? _textPrimaryDark : _textPrimaryLight;

  static Color textSecondary(bool isDark) =>
      isDark ? _textSecondaryDark : _textSecondaryLight;
}
