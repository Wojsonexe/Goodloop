import 'package:flutter/material.dart';

class AppColors {
  // Primary Colors
  static const primary = Color(0xFFFF6B9D);
  static const secondary = Color(0xFFC44569);
  static const tertiary = Color(0xFF8E44AD);

  // Gradient Colors
  static const gradientStart = Color(0xFFFFB6C1);
  static const gradientMiddle = Color(0xFFDDA0DD);
  static const gradientEnd = Color(0xFF87CEEB);

  // Background Colors
  static const backgroundLight = Color(0xFFFFF5F7);
  static const backgroundDark = Color(0xFF1A1A2E);
  static const cardLight = Colors.white;
  static const cardDark = Color(0xFF16213E);

  // Text Colors
  static const textPrimary = Color(0xFF2D3436);
  static const textSecondary = Color(0xFF636E72);
  static const textLight = Colors.white;

  // Status Colors
  static const success = Color(0xFF55EFC4);
  static const warning = Color(0xFFFDCB6E);
  static const error = Color(0xFFFF7675);
  static const info = Color(0xFF74B9FF);

  // Level Colors
  static const levelStarter = Color(0xFF81C784);
  static const levelHelper = Color(0xFF64B5F6);
  static const levelInspirator = Color(0xFFBA68C8);
  static const levelGuardian = Color(0xFFFFD54F);

  static LinearGradient get primaryGradient => const LinearGradient(
        colors: [gradientStart, gradientMiddle, gradientEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient get cardGradient => LinearGradient(
        colors: [
          gradientStart.withValues(alpha: (25)),
          gradientMiddle.withValues(alpha: (12)),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}
