/// Empty state placeholder shown when a list has no items.
library;

import 'package:flutter/material.dart';

class AdminEmptyState extends StatelessWidget {
  const AdminEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(
                      alpha: 0.08,
                    ),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 38,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7A95),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      );
}

/// Animated loading skeleton list, used in place of `CircularProgressIndicator`
/// for table-style screens so the layout doesn't jump.
class AdminLoadingSkeleton extends StatelessWidget {
  const AdminLoadingSkeleton({
    super.key,
    this.itemCount = 6,
    this.itemHeight = 56,
  });

  final int itemCount;
  final double itemHeight;

  @override
  Widget build(BuildContext context) => Column(
        children: List.generate(itemCount, (index) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Container(
              height: itemHeight,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 80,
                    height: 14,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Color(0xFFD1D5DB)),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      );
}