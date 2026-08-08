/// Reusable reference card used by the Reference Point screen
/// (formerly branded as the "Mentor Hub").
///
/// Visuals follow the ScholarBird style: white surface, 12px radius, thin
/// `#E5E7EB` border, soft shadow, gradient avatar fallback when the mentor
/// has no photo. Each card exposes Email / Call / Copy actions that integrate
/// with [url_launcher] and the Flutter clipboard without depending on any
/// external service layer.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/mentor.dart';
import '../theme/scholarbird_theme.dart';

/// Compact yet information-dense card rendering a single [Mentor].
class MentorCard extends StatelessWidget {
  const MentorCard({super.key, required this.mentor});

  final Mentor mentor;

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
            color: ScholarBirdColors.primary.withValues(alpha: isDark ? .08 : .05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(mentor: mentor, subtleTextColor: subtleTextColor),
          const SizedBox(height: ScholarBirdSpacing.small),
          if (mentor.researchInterests.isNotEmpty)
            _ResearchChips(interests: mentor.researchInterests),
          const SizedBox(height: ScholarBirdSpacing.small),
          Text(
            mentor.bio,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: subtleTextColor,
            ),
          ),
          const SizedBox(height: ScholarBirdSpacing.medium),
          _ContactRows(
            mentor: mentor,
            subtleTextColor: subtleTextColor,
          ),
          const SizedBox(height: ScholarBirdSpacing.medium),
          _ActionButtons(mentor: mentor),
        ],
      ),
    );
  }
}

// ─── Header ────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.mentor, required this.subtleTextColor});

  final Mentor mentor;
  final Color subtleTextColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Avatar(mentor: mentor),
        const SizedBox(width: ScholarBirdSpacing.small),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mentor.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: ScholarBirdColors.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: ScholarBirdColors.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  mentor.designation,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: ScholarBirdColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${mentor.department.label} · ${mentor.university}',
                style: TextStyle(
                  fontSize: 12,
                  color: subtleTextColor,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Avatar (photo with initials fallback) ──────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({required this.mentor});

  final Mentor mentor;

  @override
  Widget build(BuildContext context) {
    final url = mentor.photoUrl?.trim() ?? '';
    return SizedBox(
      width: 56,
      height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: url.isNotEmpty
            ? Image.network(
                url,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _AvatarFallback(name: mentor.name),
              )
            : _AvatarFallback(name: mentor.name),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
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
        _initials(name),
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: Colors.white,
        ),
      ),
    );
  }

  static String _initials(String raw) {
    final parts = raw.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

// ─── Research interest chips ───────────────────────────────────────────────

class _ResearchChips extends StatelessWidget {
  const _ResearchChips({required this.interests});

  final List<String> interests;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: interests
          .take(4)
          .map(
            (tag) => Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: ScholarBirdColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ScholarBirdColors.border),
              ),
              child: Text(
                tag,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: ScholarBirdColors.ink,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

// ─── Contact rows (icon + label/value) ─────────────────────────────────────

class _ContactRows extends StatelessWidget {
  const _ContactRows({
    required this.mentor,
    required this.subtleTextColor,
  });

  final Mentor mentor;
  final Color subtleTextColor;

  @override
  Widget build(BuildContext context) {
    final entries = <_ContactEntry>[
      _ContactEntry(
        icon: Icons.mail_outline_rounded,
        label: mentor.email,
      ),
      if ((mentor.phone ?? '').trim().isNotEmpty)
        _ContactEntry(
          icon: Icons.call_outlined,
          label: mentor.phone!,
        ),
      if ((mentor.officeRoom ?? '').trim().isNotEmpty)
        _ContactEntry(
          icon: Icons.location_on_outlined,
          label: 'Office: ${mentor.officeRoom}',
        ),
      if (mentor.availableDays.isNotEmpty)
        _ContactEntry(
          icon: Icons.calendar_today_outlined,
          label: _availableDaysLabel(mentor.availableDays),
        ),
      if ((mentor.availableTime ?? '').trim().isNotEmpty)
        _ContactEntry(
          icon: Icons.schedule_outlined,
          label: mentor.availableTime!,
        ),
    ];

    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries
          .map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(e.icon, size: 16, color: subtleTextColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.label,
                      style: TextStyle(fontSize: 12, color: subtleTextColor),
                      maxLines: 1,
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

  String _availableDaysLabel(List<String> days) {
    if (days.isEmpty) return '';
    if (days.length == 1) return days.first;
    return days.join(' · ');
  }
}

class _ContactEntry {
  const _ContactEntry({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

// ─── Action buttons (Email, Call, Copy) ────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.mentor});

  final Mentor mentor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FilledActionButton(
            icon: Icons.mail_outline_rounded,
            label: 'Email',
            onTap: () => _launchEmail(context),
          ),
        ),
        const SizedBox(width: 8),
        if ((mentor.phone ?? '').trim().isNotEmpty)
          Expanded(
            child: _OutlinedActionButton(
              icon: Icons.call_outlined,
              label: 'Call',
              onTap: () => _launchCall(context),
            ),
          )
        else
          Expanded(
            child: _OutlinedActionButton(
              icon: Icons.copy_all_outlined,
              label: 'Copy',
              onTap: () => _copyEmail(context),
            ),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: _OutlinedActionButton(
            icon: Icons.copy_all_outlined,
            label: 'Copy',
            onTap: () => _copyEmail(context),
          ),
        ),
      ],
    );
  }

  Future<void> _launchEmail(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uri = Uri(
        scheme: 'mailto',
        path: mentor.email,
        query: 'subject=Inquiry from ScholarBird',
      );
      final ok = await launchUrl(uri);
      if (!ok && context.mounted) {
        await _copyEmail(context);
        messenger.showSnackBar(
          const SnackBar(content: Text('No email app — email copied to clipboard.')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      await _copyEmail(context);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open email client: $e')),
      );
    }
  }

  Future<void> _launchCall(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final phone = mentor.phone ?? '';
    if (phone.trim().isEmpty) return;
    try {
      final uri = Uri(scheme: 'tel', path: _stripSpaces(phone));
      final ok = await launchUrl(uri);
      if (!ok && context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No dialer available on this device.')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open dialer: $e')),
      );
    }
  }

  Future<void> _copyEmail(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: mentor.email));
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('${mentor.email} copied to clipboard')),
    );
  }

  String _stripSpaces(String phone) => phone.replaceAll(RegExp(r'\s+'), '');
}

class _FilledActionButton extends StatelessWidget {
  const _FilledActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: ScholarBirdColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label),
      ),
    );
  }
}

class _OutlinedActionButton extends StatelessWidget {
  const _OutlinedActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: ScholarBirdColors.primary,
          side: const BorderSide(color: ScholarBirdColors.primary, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label),
      ),
    );
  }
}
