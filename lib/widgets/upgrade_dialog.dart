/// Beautiful upgrade prompt shown when a free user attempts to open a
/// premium-gated surface (AI Recommendations, SOP Generator, AI Chat,
/// CV Generator, Premium Filters, Saved Scholarships, Premium Badge).
///
/// The dialog is intentionally declarative:
///   •  Caller supplies the [PremiumFeature] being requested.
///   •  Caller supplies a callback for "Upgrade Now" so the dialog
///      stays decoupled from navigation / routing decisions.
///   •  Caller can pass a custom benefit list or rely on the default
///      ScholarBird Pro bullet list.
///
/// Everything else — copy, colors, icon, spacing — is owned by this
/// file so the visual language stays consistent across screens.
library;

import 'package:flutter/material.dart';

import '../screens/premium/premium_upgrade_screen.dart';
import 'premium_feature.dart';

/// Presents a premium-only feature upgrade dialog.
///
/// Pass the [feature] the user tried to access so the dialog can speak
/// to that specific benefit (instead of a generic "go premium"). The
/// optional [customBenefits] lets you override the default bullet list
/// when a particular feature has its own selling points.
class UpgradeDialog extends StatelessWidget {
  const UpgradeDialog({
    required this.feature,
    this.customBenefits,
    this.onUpgrade,
    super.key,
  });

  /// Convenience helper that pushes the dialog using [Navigator] with
  /// the standard Material route so it gets a scrim, scrim dismiss, and
  /// the platform-appropriate entrance animation.
  static Future<T?> show<T>({
    required BuildContext context,
    required PremiumFeature feature,
    List<String>? customBenefits,
    VoidCallback? onUpgrade,
  }) {
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => UpgradeDialog(
        feature: feature,
        customBenefits: customBenefits,
        onUpgrade: onUpgrade,
      ),
    );
  }

  final PremiumFeature feature;
  final List<String>? customBenefits;
  final VoidCallback? onUpgrade;

  static const _defaultBenefits = <String>[
    'Unlimited AI-powered scholarship recommendations',
    'AI SOP, CV and Chat assistants',
    'Premium filters (deadline, IELTS, funding type)',
    'Unlimited saved scholarships across devices',
    'Verified ScholarBird Pro badge on your profile',
    'Priority support and early access to new features',
  ];

  @override
  Widget build(BuildContext context) {
    final benefits = customBenefits ?? _defaultBenefits;
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(feature: feature),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feature.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      feature.description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6B7A95),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'What you unlock with Pro',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...benefits.map(_buildBenefitRow),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          final handler = onUpgrade ??
                              () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const PremiumUpgradeScreen(),
                                    ),
                                  );
                          handler();
                        },
                        icon: const Icon(Icons.workspace_premium),
                        label: const Text('Upgrade Now'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5B7AE8),
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Maybe later',
                        style: TextStyle(
                          color: Color(0xFF6B7A95),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitRow(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.check_circle,
                size: 18,
                color: Color(0xFF5B7AE8),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF1A1A2E),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.feature});
  final PremiumFeature feature;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              feature.icon,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'ScholarBird Pro',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Unlock ${feature.title}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}