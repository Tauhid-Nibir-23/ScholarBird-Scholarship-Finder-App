/// Reusable card that renders a single academic reference.
///
/// Matches the ScholarBird visual language: white surface, 12px radius,
/// thin border, soft shadow, primary accent. Edit and Delete actions are
/// surfaced via small icon buttons; Add is rendered as a primary button
/// when the slot is empty.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/reference_model.dart';
import '../theme/scholarbird_theme.dart';

/// Compact card rendering a single [ReferenceModel].
class ReferenceCard extends StatelessWidget {
  const ReferenceCard({
    super.key,
    required this.reference,
    required this.slotLabel,
    required this.onEdit,
    required this.onDelete,
    this.onAdd,
    this.isBusy = false,
  });

  final ReferenceModel reference;
  final String slotLabel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onAdd;
  final bool isBusy;

  bool get _isEmpty => !reference.isComplete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? scheme.surface : ScholarBirdColors.surface;
    final borderColor = isDark
        ? scheme.outlineVariant.withValues(alpha: .6)
        : ScholarBirdColors.border;
    final subtleTextColor =
        isDark ? scheme.onSurfaceVariant : ScholarBirdColors.body;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: ScholarBirdColors.primary.withValues(alpha: isDark ? .08 : .04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
      child: _isEmpty
          ? _EmptyState(slotLabel: slotLabel, onAdd: onAdd)
          : _FilledState(
              reference: reference,
              slotLabel: slotLabel,
              subtleTextColor: subtleTextColor,
              onEdit: isBusy ? null : onEdit,
              onDelete: isBusy ? null : onDelete,
            ),
    );
  }
}

// ─── Empty state ───────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.slotLabel, required this.onAdd});

  final String slotLabel;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: ScholarBirdColors.primary.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.person_add_alt_1_outlined,
                color: ScholarBirdColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: ScholarBirdSpacing.small),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slotLabel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: ScholarBirdColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'No reference added yet.',
                    style: TextStyle(
                      fontSize: 12,
                      color: ScholarBirdColors.body,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: ScholarBirdSpacing.small),
        SizedBox(
          height: 40,
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Reference'),
          ),
        ),
      ],
    );
  }
}

// ─── Filled state ─────────────────────────────────────────────────────────

class _FilledState extends StatelessWidget {
  const _FilledState({
    required this.reference,
    required this.slotLabel,
    required this.subtleTextColor,
    required this.onEdit,
    required this.onDelete,
  });

  final ReferenceModel reference;
  final String slotLabel;
  final Color subtleTextColor;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          reference: reference,
          slotLabel: slotLabel,
          onEdit: onEdit,
          onDelete: onDelete,
        ),
        const SizedBox(height: ScholarBirdSpacing.small),
        _RelationshipChip(reference: reference),
        const SizedBox(height: ScholarBirdSpacing.small),
        _DetailRows(reference: reference, subtleTextColor: subtleTextColor),
        const SizedBox(height: ScholarBirdSpacing.small),
        _ContactActions(reference: reference),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.reference,
    required this.slotLabel,
    required this.onEdit,
    required this.onDelete,
  });

  final ReferenceModel reference;
  final String slotLabel;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(reference.fullName);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                ScholarBirdColors.primary,
                ScholarBirdColors.primaryDark,
              ],
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: ScholarBirdSpacing.small),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reference.fullName.isEmpty ? slotLabel : reference.fullName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: ScholarBirdColors.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                reference.designation.isEmpty
                    ? 'Reference'
                    : reference.designation,
                style: TextStyle(fontSize: 12, color: ScholarBirdColors.body),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: ScholarBirdSpacing.small),
        _IconAction(
          icon: Icons.edit_outlined,
          tooltip: 'Edit reference',
          onTap: onEdit,
        ),
        const SizedBox(width: 4),
        _IconAction(
          icon: Icons.delete_outline_rounded,
          tooltip: 'Delete reference',
          onTap: onDelete,
          color: const Color(0xFFDC2626),
        ),
      ],
    );
  }

  static String _initials(String raw) {
    final parts = raw.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _RelationshipChip extends StatelessWidget {
  const _RelationshipChip({required this.reference});

  final ReferenceModel reference;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: ScholarBirdColors.primary.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          reference.relationshipLabel,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: ScholarBirdColors.primaryDark,
          ),
        ),
      ),
    );
  }
}

class _DetailRows extends StatelessWidget {
  const _DetailRows({required this.reference, required this.subtleTextColor});

  final ReferenceModel reference;
  final Color subtleTextColor;

  @override
  Widget build(BuildContext context) {
    final entries = <_Entry>[
      if (reference.department.trim().isNotEmpty)
        _Entry(icon: Icons.school_outlined, text: reference.department),
      if (reference.university.trim().isNotEmpty)
        _Entry(icon: Icons.account_balance_outlined, text: reference.university),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries
          .map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(e.icon, size: 14, color: subtleTextColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      e.text,
                      style: TextStyle(fontSize: 12, color: subtleTextColor),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _Entry {
  const _Entry({required this.icon, required this.text});
  final IconData icon;
  final String text;
}

class _ContactActions extends StatelessWidget {
  const _ContactActions({required this.reference});

  final ReferenceModel reference;

  @override
  Widget build(BuildContext context) {
    final email = reference.email.trim();
    final phone = reference.phone.trim();
    if (email.isEmpty && phone.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        if (email.isNotEmpty)
          Expanded(
            child: _OutlinedAction(
              icon: Icons.mail_outline_rounded,
              label: 'Email',
              onTap: () => _launchEmail(email),
            ),
          ),
        if (email.isNotEmpty && phone.isNotEmpty) const SizedBox(width: 8),
        if (phone.isNotEmpty)
          Expanded(
            child: _OutlinedAction(
              icon: Icons.call_outlined,
              label: 'Call',
              onTap: () => _launchCall(phone),
            ),
          ),
      ],
    );
  }

  Future<void> _launchEmail(String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    await launchUrl(uri);
  }

  Future<void> _launchCall(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri(scheme: 'tel', path: cleaned);
    await launchUrl(uri);
  }
}

class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 38,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 16),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      );
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => InkResponse(
        onTap: onTap,
        radius: 24,
        child: Tooltip(
          message: tooltip,
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ScholarBirdColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: color ?? ScholarBirdColors.primary,
            ),
          ),
        ),
      );
}
