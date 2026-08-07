/// Centralized design tokens for the ScholarBird premium EdTech look.
///
/// Keep this file pure-dart so it can be imported by any widget without
/// pulling in Firebase or project architecture concerns.
library;

import 'package:flutter/material.dart';

/// Core ScholarBird color palette used across the home experience.
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF1E54FF);
  static const Color primaryDark = Color(0xFF0B3FCC);
  static const Color primarySoft = Color(0xFFE8EFFF);
  static const Color deepNavy = Color(0xFF0B1B3D);
  static const Color ink = Color(0xFF0F172A);

  // Surfaces
  static const Color background = Color(0xFFF4F6FB);
  static const Color surface = Colors.white;
  static const Color cardBorder = Color(0xFFE6EAF2);
  static const Color divider = Color(0xFFEDF1F7);

  // Text
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF5A6B85);
  static const Color textMuted = Color(0xFF8A95AB);
  static const Color textOnDark = Colors.white;

  // Accents
  static const Color accentViolet = Color(0xFF8B5CF6);
  static const Color accentMint = Color(0xFF10B981);
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color accentRose = Color(0xFFF43F5E);
  static const Color accentSky = Color(0xFF38BDF8);

  // Status
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);

  // Legacy aliases (preserved to avoid touching unrelated widgets).
  static const Color legacyPrimary = Color(0xFF5B7AE8);
  static const Color legacyInk = Color(0xFF1A1A2E);
  static const Color legacyMuted = Color(0xFF6B7A95);
  static const Color legacyHint = Color(0xFF9CA3AF);
}

/// Reusable shadow presets tuned for a layered, premium feel.
class AppShadows {
  AppShadows._();

  static List<BoxShadow> get soft => [
        BoxShadow(
          color: const Color(0xFF0B1B3D).withValues(alpha: 0.05),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get medium => [
        BoxShadow(
          color: const Color(0xFF0B1B3D).withValues(alpha: 0.08),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> get primaryGlow => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.25),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ];

  static List<BoxShadow> get innerSoft => [
        BoxShadow(
          color: const Color(0xFF0B1B3D).withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];
}

/// Gradients used for hero cards, banners and decorative surfaces.
class AppGradients {
  AppGradients._();

  static const LinearGradient primary = LinearGradient(
    colors: [Color(0xFF1E54FF), Color(0xFF4F7BFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient deepNight = LinearGradient(
    colors: [Color(0xFF0B1B3D), Color(0xFF1E3A8A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient sunrise = LinearGradient(
    colors: [Color(0xFF93C5FD), Color(0xFFFDE68A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient mint = LinearGradient(
    colors: [Color(0xFF34D399), Color(0xFF60A5FA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient violet = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient headerBackdrop = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFF4F6FB)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

/// Typography presets for the home screen.
class AppText {
  AppText._();

  static const String fontFamily = 'Roboto';

  static const TextStyle display = TextStyle(
    fontFamily: fontFamily,
    fontSize: 26,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: -0.4,
    height: 1.2,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
    height: 1.25,
  );

  static const TextStyle title = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle subtitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
  );

  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    letterSpacing: 0.2,
  );
}

/// Reusable shape tokens.
class AppRadius {
  AppRadius._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double pill = 999;
}

/// Spacing tokens keeping the page rhythm consistent.
class AppSpacing {
  AppSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Lightweight section header used to keep visual hierarchy consistent.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: AppText.headline),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: AppText.subtitle),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
