/// Declarative gate for premium-only UI.
///
/// Usage:
///
/// ```dart
/// PremiumGuard(
///   feature: PremiumFeature.aiRecommendations,
///   child: ElevatedButton(
///     onPressed: () => Navigator.pushNamed(context, '/ai-advisor'),
///     child: const Text('Find my matches'),
///   ),
/// )
/// ```
///
/// The guard reads [SubscriptionProvider] (the app-wide source of truth)
/// and either renders [child] directly or replaces it with a locked
/// placeholder that triggers [UpgradeDialog] on tap.
///
/// Two modes are supported:
///
///   1. [PremiumGuard] — replaces the child widget for free users with a
///      locked placeholder that opens the upgrade dialog on tap.
///   2. [premiumAction] / `PremiumGate.of(context).run(...)` — programmatic
///      helper that opens the dialog from inside an event handler (e.g.
///      an `onPressed` callback that performs some non-UI side effect).
///
/// Both modes share the same provider and dialog so the visual language
/// is consistent.
library;

import 'package:flutter/material.dart';

import '../screens/premium/premium_upgrade_screen.dart';
import '../services/subscription_provider.dart';
import 'premium_feature.dart';
import 'upgrade_dialog.dart';

/// Wraps a [child] widget so that free users see a locked placeholder
/// instead of the premium content. The placeholder opens [UpgradeDialog]
/// when tapped.
class PremiumGuard extends StatelessWidget {
  const PremiumGuard({
    required this.feature,
    required this.child,
    this.lockedBuilder,
    this.onUpgrade,
    super.key,
  });

  /// Identifier for the feature this guard protects. Drives the dialog
  /// title / description / icon.
  final PremiumFeature feature;

  /// The premium content to render for active subscribers.
  final Widget child;

  /// Optional override for the locked placeholder. When `null` we use a
  /// tasteful default that still matches the ScholarBird visual language.
  final WidgetBuilder? lockedBuilder;

  /// Optional callback invoked when the user taps the locked placeholder
  /// or the dialog's "Upgrade Now" button. Defaults to navigating to the
  /// [PremiumUpgradeScreen].
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final provider = SubscriptionProviderScope.of(context);
    if (provider.isPremium) {
      return child;
    }

    return lockedBuilder?.call(context) ?? _DefaultLockedTile(feature: feature);
  }

  /// Helper for guarded widgets: opens the upgrade dialog immediately.
  ///
  /// Use this inside event handlers (e.g. an `onPressed` that performs
  /// a non-UI side effect) when you cannot wrap the UI in [PremiumGuard].
  static Future<void> promptUpgrade(
    BuildContext context, {
    required PremiumFeature feature,
    VoidCallback? onUpgrade,
  }) {
    return UpgradeDialog.show<void>(
      context: context,
      feature: feature,
      onUpgrade: onUpgrade ??
          () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PremiumUpgradeScreen(),
                ),
              ),
    );
  }
}

class _DefaultLockedTile extends StatelessWidget {
  const _DefaultLockedTile({required this.feature});
  final PremiumFeature feature;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => PremiumGuard.promptUpgrade(context, feature: feature),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            gradient: const LinearGradient(
              colors: [Color(0xFFF8FAFC), Color(0xFFEEF2FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF5B7AE8).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  feature.icon,
                  color: const Color(0xFF5B7AE8),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feature.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Pro feature • Tap to unlock',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7A95),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Pro',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.4,
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
}

/// Lightweight dependency lookup for [SubscriptionProvider] that
/// works with any `Provider`-style package — but also has a sensible
/// default when no provider is registered (e.g. in tests or previews).
///
/// We intentionally do not depend on a third-party `provider` package;
/// callers wire the provider into a `ChangeNotifierProvider` (or a
/// custom `ListenableBuilder`) at the top of the tree and access it
/// through this scope.
class SubscriptionProviderScope extends InheritedNotifier<SubscriptionProvider> {
  const SubscriptionProviderScope({
    required SubscriptionProvider provider,
    required super.child,
    super.key,
  }) : super(notifier: provider);

  static SubscriptionProvider of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SubscriptionProviderScope>();
    assert(
      scope != null,
      'SubscriptionProviderScope is missing from the widget tree. Wrap your '
      'MaterialApp with a ChangeNotifierProvider<SubscriptionProvider> or '
      'a SubscriptionProviderScope widget.',
    );
    return scope!.notifier!;
  }
}