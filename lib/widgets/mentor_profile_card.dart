/// Premium card used by the Mentor Hub listing screen.
///
/// Each card surfaces only what a student needs to decide whether to
/// open the detail page:
///   * portrait (with initials fallback)
///   * name, country, expertise, university
///   * rating + success rate
///   * a one-line bio
///   * quick contact icons (WhatsApp / email)
///   * "View Details" CTA
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/mentor_profile.dart';
import '../theme/scholarbird_theme.dart';

class MentorProfileCard extends StatelessWidget {
  const MentorProfileCard({
    required this.mentor,
    required this.onViewDetails,
    super.key,
    this.onWhatsApp,
    this.onEmail,
  });

  final MentorProfile mentor;

  /// Triggered when the user taps "View Details".
  final VoidCallback onViewDetails;

  /// Optional overrides for the contact icons. When null, the card tries
  /// to launch the contact via `url_launcher` directly.
  final VoidCallback? onWhatsApp;
  final VoidCallback? onEmail;

  Future<void> _launchWhatsApp(BuildContext context) async {
    if (onWhatsApp != null) {
      onWhatsApp!();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final digits = mentor.whatsapp.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('WhatsApp number not available.')),
      );
      return;
    }
    final uri = Uri.parse('https://wa.me/$digits');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp.')),
      );
    }
  }

  Future<void> _launchEmail(BuildContext context) async {
    if (onEmail != null) {
      onEmail!();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    if (mentor.email.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Email not available.')),
      );
      return;
    }
    final uri = Uri(
      scheme: 'mailto',
      path: mentor.email,
      query: 'subject=Mentorship inquiry from ScholarBird',
    );
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No email app found.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? Theme.of(context).colorScheme.surface
        : ScholarBirdColors.surface;
    final borderColor = isDark
        ? Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .6)
        : ScholarBirdColors.border;
    final subtleTextColor =
        isDark ? Theme.of(context).colorScheme.onSurfaceVariant : ScholarBirdColors.body;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color:
                ScholarBirdColors.primary.withValues(alpha: isDark ? .10 : .06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(mentor: mentor, subtleTextColor: subtleTextColor),
          const SizedBox(height: ScholarBirdSpacing.small),
          if (mentor.expertise.isNotEmpty)
            _ExpertiseChips(items: mentor.expertise),
          const SizedBox(height: ScholarBirdSpacing.small),
          Text(
            mentor.bio,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, height: 1.45, color: subtleTextColor),
          ),
          const SizedBox(height: ScholarBirdSpacing.medium),
          _StatsRow(mentor: mentor),
          const SizedBox(height: ScholarBirdSpacing.medium),
          Row(
            children: [
              _CircleAction(
                icon: Icons.chat_bubble_outline_rounded,
                tooltip: 'WhatsApp',
                onTap: () => _launchWhatsApp(context),
              ),
              const SizedBox(width: 8),
              _CircleAction(
                icon: Icons.mail_outline_rounded,
                tooltip: 'Email',
                onTap: () => _launchEmail(context),
              ),
              const Spacer(),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: onViewDetails,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ScholarBirdColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text('View Details'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.mentor, required this.subtleTextColor});

  final MentorProfile mentor;
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
              Row(
                children: [
                  Flexible(
                    child: Text(
                      mentor.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: ScholarBirdColors.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (mentor.verified) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.verified_rounded,
                      color: ScholarBirdColors.primary,
                      size: 16,
                    ),
                  ],
                ],
              ),
              if (mentor.designation.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    mentor.designation,
                    style: TextStyle(fontSize: 12, color: subtleTextColor),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (mentor.country.isNotEmpty || mentor.university.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: ScholarBirdColors.body,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          [mentor.university, mentor.country]
                              .where((s) => s.trim().isNotEmpty)
                              .join(' · '),
                          style: TextStyle(
                            fontSize: 12,
                            color: subtleTextColor,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.mentor});

  final MentorProfile mentor;

  @override
  Widget build(BuildContext context) {
    final url = mentor.profilePhoto?.trim() ?? '';
    return SizedBox(
      width: 60,
      height: 60,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: url.isNotEmpty
            ? Image.network(
                url,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _AvatarFallback(name: mentor.name),
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
      width: 60,
      height: 60,
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
          fontWeight: FontWeight.w800,
          fontSize: 20,
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

class _ExpertiseChips extends StatelessWidget {
  const _ExpertiseChips({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items
          .take(3)
          .map(
            (tag) => Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: ScholarBirdColors.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                tag,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ScholarBirdColors.primaryDark,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.mentor});

  final MentorProfile mentor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatPill(
          icon: Icons.star_rounded,
          color: const Color(0xFFF59E0B),
          label: mentor.rating > 0
              ? '${mentor.rating.toStringAsFixed(1)} · ${mentor.totalReviews}'
              : 'New',
        ),
        const SizedBox(width: 6),
        _StatPill(
          icon: Icons.emoji_events_outlined,
          color: ScholarBirdColors.primary,
          label: mentor.successRate > 0
              ? '${mentor.successRate}% success'
              : '—',
        ),
        const SizedBox(width: 6),
        _StatPill(
          icon: Icons.bolt_outlined,
          color: ScholarBirdColors.primaryDark,
          label: mentor.responseTime.isEmpty ? '—' : mentor.responseTime,
        ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: ScholarBirdColors.background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ScholarBirdColors.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: ScholarBirdColors.primary.withValues(alpha: .08),
            shape: BoxShape.circle,
            border: Border.all(
              color: ScholarBirdColors.primary.withValues(alpha: .25),
            ),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: ScholarBirdColors.primary, size: 18),
        ),
      ),
    );
  }
}
