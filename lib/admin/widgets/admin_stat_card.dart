/// Reusable summary card for the admin dashboard.
///
/// Displays a label, a count, a leading icon, and an optional
/// trend indicator (e.g. "+12% this week"). The card animates
/// elevation on hover to feel responsive on desktop.
library;

import 'package:flutter/material.dart';

import 'admin_section.dart';

class AdminStatCard extends StatefulWidget {
  const AdminStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.trend,
    this.iconColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? trend;
  final Color? iconColor;

  @override
  State<AdminStatCard> createState() => _AdminStatCardState();
}

class _AdminStatCardState extends State<AdminStatCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.iconColor ?? Theme.of(context).colorScheme.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hovered ? 0.08 : 0.02),
              blurRadius: _hovered ? 18 : 6,
              offset: Offset(0, _hovered ? 8 : 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(widget.icon, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.value,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7A95),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.trend != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.trend!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: widget.trend!.startsWith('-')
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF16A34A),
                        ),
                      ),
                    ],
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

class AdminStatGrid extends StatelessWidget {
  const AdminStatGrid(
      {super.key, required this.children, this.maxWidth = 1200});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.clamp(0, maxWidth);
          final crossAxisCount = width >= 1100 ? 4 : (width >= 720 ? 3 : 2);
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final child in children)
                SizedBox(
                  width: (width - 16 * (crossAxisCount - 1)) / crossAxisCount,
                  child: child,
                ),
            ],
          );
        },
      );
}

/// Section wrapper used by every admin page to keep titles,
/// subtitles and card padding consistent.
class AdminStatCardSection extends StatelessWidget {
  const AdminStatCardSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.icon,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => AdminSection(
        title: title,
        subtitle: subtitle,
        icon: icon,
        action: action,
        child: child,
      );
}
