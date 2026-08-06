/// Shared visual primitives and theme values for the admin experience.
import 'package:flutter/material.dart';

/// Admin color palette used across cards, surfaces, and headings.
class AdminPalette {
  const AdminPalette._();

  static const background = Color(0xFFF5F7FB);
  static const primary = Color(0xFF5B7AE8);
  static const primaryDark = Color(0xFF3D5AC1);
  static const heading = Color(0xFF1A1A2E);
  static const body = Color(0xFF6B7A95);
}

/// Admin theme factory used by the shell layout and dashboard pages.
class AdminTheme {
  const AdminTheme._();

  static ThemeData data(BuildContext context) => Theme.of(context).copyWith(
        scaffoldBackgroundColor: AdminPalette.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AdminPalette.background,
          foregroundColor: AdminPalette.heading,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        textTheme: Theme.of(context).textTheme.apply(
              bodyColor: AdminPalette.body,
              displayColor: AdminPalette.heading,
            ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: AdminPalette.primary, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AdminPalette.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
}

/// Standard elevated admin surface used to group related content.
class AdminSurface extends StatelessWidget {
  const AdminSurface(
      {required this.child,
      super.key,
      this.padding = const EdgeInsets.all(20),
      this.margin});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: child,
      );
}

/// Section heading component for the admin UI.
class AdminSectionTitle extends StatelessWidget {
  const AdminSectionTitle({required this.title, super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AdminPalette.heading, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: const TextStyle(color: AdminPalette.body)),
          ],
        ],
      );
}

/// Circular admin avatar used for headings and identity placeholders.
class AdminAvatar extends StatelessWidget {
  const AdminAvatar({required this.name, super.key, this.radius = 20});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: radius * 2,
        height: radius * 2,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
              colors: [AdminPalette.primary, AdminPalette.primaryDark]),
        ),
        child: Text(
          name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase(),
          style: TextStyle(
              color: Colors.white,
              fontSize: radius * .8,
              fontWeight: FontWeight.w700),
        ),
      );
}
