/// Shared profile UI primitives used across profile-related screens.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/premium_feature.dart';
import '../../widgets/premium_guard.dart';

/// Color and spacing tokens shared by profile-related widgets.
const Color sbPrimary = Color(0xFF5B7AE8);
const Color sbPrimaryDark = Color(0xFF3D5AC1);
const Color sbBackground = Color(0xFFF5F7FB);
const Color sbText = Color(0xFF1A1A2E);
const Color sbSecondaryText = Color(0xFF6B7A95);
const Color sbMutedText = Color(0xFF9CA3AF);
const Color sbBorder = Color(0xFFE5E7EB);
const Color sbHintText = Color(0xFFB4BAC4);

/// Section label used to divide profile settings groups.
class ProfileSectionLabel extends StatelessWidget {
  const ProfileSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: sbMutedText,
          letterSpacing: 0.5,
          height: 1.2,
        ),
      );
}

/// Tappable profile menu row with icon, title, and optional subtitle.
class ProfileMenuTile extends StatelessWidget {
  const ProfileMenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isDestructive = false,
    this.subtitle,
    super.key,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isDestructive;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  isDestructive ? Colors.red.withValues(alpha: 0.2) : sbBorder,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    color: isDestructive ? Colors.red.shade600 : sbPrimary,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDestructive
                                    ? Colors.red.shade600
                                    : sbText)),
                        if (subtitle != null)
                          Text(subtitle!,
                              style: const TextStyle(
                                  fontSize: 12, color: sbSecondaryText))
                      ]),
                ],
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: isDestructive ? Colors.red.shade300 : sbMutedText,
              ),
            ],
          ),
        ),
      );
}

/// Text field styling used by profile forms.
class ProfileTextField extends StatelessWidget {
  const ProfileTextField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    this.keyboardType,
    this.maxLines = 1,
    this.inputFormatters,
    super.key,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final TextInputType? keyboardType;
  final int maxLines;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        inputFormatters: inputFormatters,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: sbText,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: sbHintText,
          ),
          prefixIcon: Icon(
            prefixIcon,
            color: sbPrimary,
            size: 22,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: sbBorder, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: sbBorder, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: sbPrimary, width: 2),
          ),
        ),
      );
}

/// Dropdown field styling used by profile forms.
class ProfileDropdownField extends StatelessWidget {
  const ProfileDropdownField({
    required this.label,
    required this.items,
    required this.onChanged,
    required this.prefixIcon,
    this.value,
    this.hint = '',
    this.showLabel = true,
    super.key,
  });

  final String label;
  final String hint;
  final String? value;
  final List<String> items;
  final IconData prefixIcon;
  final Function(String?) onChanged;

  /// When false, the [label] text above the field is suppressed so the
  /// dropdown can sit directly under a section header without duplication.
  final bool showLabel;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showLabel)
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: sbMutedText,
                letterSpacing: 0.5,
                height: 1.2,
              ),
            ),
          if (showLabel) const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sbBorder, width: 1.5),
            ),
            child: DropdownButtonFormField<String>(
              initialValue: value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: sbText,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: sbHintText,
                ),
                prefixIcon: Icon(
                  prefixIcon,
                  color: sbPrimary,
                  size: 22,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              items: items
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item,
                      child: Text(
                        item,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: sbText,
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
              isExpanded: true,
              icon: const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(
                  Icons.expand_more,
                  color: sbPrimary,
                  size: 24,
                ),
              ),
              dropdownColor: Colors.white,
            ),
          ),
        ],
      );
}

/// Primary button styling used by profile actions.
class ProfilePrimaryButton extends StatelessWidget {
  const ProfilePrimaryButton({
    required this.title,
    required this.onPressed,
    this.isLoading = false,
    super.key,
  });

  final String title;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: sbPrimary,
          disabledBackgroundColor: sbPrimary.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 3,
        ),
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
      );
}

/// Empty or error state shown inside profile-related views.
class ProfileEmptyState extends StatelessWidget {
  const ProfileEmptyState({
    required this.title,
    required this.message,
    required this.icon,
    this.action,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: sbPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(60),
                ),
                child: Icon(
                  icon,
                  color: sbPrimary,
                  size: 60,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: sbText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: sbSecondaryText,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: 20),
                action!,
              ],
            ],
          ),
        ),
      );
}

/// Verified ScholarBird Pro badge shown next to profile identifiers
/// (e.g. the user's display name or settings header).
///
/// Free users see nothing (the widget returns `SizedBox.shrink()` thanks
/// to the locked builder override). Premium users see a gradient pill
/// that, when tapped, opens the upgrade dialog re-prompting them to
/// keep their subscription active.
class PremiumBadge extends StatelessWidget {
  const PremiumBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return PremiumGuard(
      feature: PremiumFeature.premiumBadge,
      lockedBuilder: (_) => const SizedBox.shrink(),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => PremiumGuard.promptUpgrade(
          context,
          feature: PremiumFeature.premiumBadge,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.workspace_premium,
                size: 14,
                color: Colors.amber,
              ),
              SizedBox(width: 4),
              Text(
                'PRO',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
