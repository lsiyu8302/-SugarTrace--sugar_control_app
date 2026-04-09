import 'package:flutter/material.dart';

class AppColors {
  static const primary    = Color(0xFF4CAF50);
  static const accent     = Color(0xFFFF9800);
  static const background = Color(0xFFF5F5F5);
  static const surface    = Colors.white;
  static const textPrimary   = Color(0xFF212121);
  static const textSecondary = Color(0xFF757575);
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecondary,
      backgroundColor: AppColors.surface,
      elevation: 8,
      type: BottomNavigationBarType.fixed,
    ),
  );
}
