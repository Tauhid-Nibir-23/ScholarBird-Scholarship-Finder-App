/// Mentor Detail — the in-depth view of a single paid mentor.
///
/// Composes the static profile with the live Firestore `mentor_reviews`
/// collection and routes the user to the booking / free-call / review
/// actions.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/mentor_package.dart';
import '../../models/mentor_profile.dart';
import '../../models/mentor_review.dart';
import '../../theme/scholarbird_theme.dart';
import 'mentor_booking_screen.dart';
import 'mentor_free_call_screen.dart';
import 'mentor_reviews_screen.dart';

class MentorDetailScreen extends StatelessWidget {
  const MentorDetailScreen({required this.mentor, super.key});

  final MentorProfile mentor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark
        ? Theme.of(context).colorScheme.surface
        : ScholarBirdColors.surface;
    final subtleTextColor =
        isDark ? Theme.of(context).colorScheme.onSurfaceVariant : ScholarBirdColors.body;

    return Scaffold(
      backgroundColor: isDark
          ? Theme.of(context).colorScheme.surface
          : ScholarBirdColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: ScholarBirdColors.primary,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: _Hero(mentor: mentor),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                ScholarBirdSpacing.medium,
                ScholarBirdSpacing.medium,
                ScholarBirdSpacing.medium,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProfileHeader(mentor: mentor, subtleTextColor: subtleTextColor),
                  const SizedBox(height: ScholarBirdSpacing.medium),
                  _StatsGrid(mentor: mentor),
                  const SizedBox(height: ScholarBirdSpacing.medium),
                  _SectionTitle(title: 'About'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
                    decoration: _cardBox(surfaceColor),
                    child: Text(
                      mentor.bio,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: subtleTextColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: ScholarBirdSpacing.medium),
                  _SectionTitle(title: 'Education'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
                    decoration: _cardBox(surfaceColor),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (mentor.education.isNotEmpty)
                          ...mentor.education.map(
                            (e) => _BulletRow(icon: Icons.school_outlined, text: e),
                          )
                        else
                          Text(
                            'Education details will be shared on request.',
                            style: TextStyle(color: subtleTextColor),
                          ),
                        if (mentor.university.isNotEmpty)
                          _BulletRow(
                            icon: Icons.account_balance_outlined,
                            text: mentor.university,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: ScholarBirdSpacing.medium),
                  _SectionTitle(title: 'Expertise'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
                    decoration: _cardBox(surfaceColor),
                    child: mentor.expertise.isEmpty
                        ? Text(
                            'Will be shared during the first call.',
                            style: TextStyle(color: subtleTextColor),
                          )
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: mentor.expertise
                                .map(
                                  (e) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: ScholarBirdColors.primary
                                          .withValues(alpha: .08),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      e,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: ScholarBirdColors.primaryDark,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                  const SizedBox(height: ScholarBirdSpacing.medium),
                  _SectionTitle(title: 'Languages'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
                    decoration: _cardBox(surfaceColor),
                    child: mentor.languages.isEmpty
                        ? Text(
                            'English (working language).',
                            style: TextStyle(color: subtleTextColor),
                          )
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: mentor.languages
                                .map(
                                  (l) => Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.translate_rounded,
                                        size: 14,
                                        color: ScholarBirdColors.primary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        l,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: ScholarBirdColors.ink,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                  const SizedBox(height: ScholarBirdSpacing.medium),
                  _SectionTitle(
                    title: 'Pricing',
                    trailing: Text(
                      'per ${mentor.currency}',
                      style: TextStyle(
                        color: subtleTextColor,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _PricingCard(mentor: mentor),
                  const SizedBox(height: ScholarBirdSpacing.medium),
                  _SectionTitle(title: 'Reviews'),
                  const SizedBox(height: 8),
                  _ReviewsSummary(mentor: mentor),
                  const SizedBox(height: ScholarBirdSpacing.medium),
                  if (mentor.availability.isNotEmpty) ...[
                    _SectionTitle(title: 'Availability'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
                      decoration: _cardBox(surfaceColor),
                      child: Text(
                        mentor.availability,
                        style: TextStyle(color: subtleTextColor),
                      ),
                    ),
                    const SizedBox(height: ScholarBirdSpacing.medium),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomActionBar(mentor: mentor),
    );
  }

  BoxDecoration _cardBox(Color surface) {
    return BoxDecoration(
      color: surface,
      border: Border.all(color: ScholarBirdColors.border),
      borderRadius: BorderRadius.circular(14),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.mentor});

  final MentorProfile mentor;

  @override
  Widget build(BuildContext context) {
    final url = mentor.profilePhoto?.trim() ?? '';
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [ScholarBirdColors.primary, ScholarBirdColors.primaryDark],
            ),
          ),
        ),
        if (url.isNotEmpty)
          Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: .0),
                Colors.black.withValues(alpha: .55),
              ],
              stops: const [.4, 1],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: Colors.white,
                backgroundImage:
                    url.isNotEmpty ? NetworkImage(url) : null,
                child: url.isEmpty
                    ? Text(
                        _initials(mentor.name),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: ScholarBirdColors.primary,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mentor.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (mentor.designation.isNotEmpty)
                      Text(
                        mentor.designation,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .92),
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (mentor.country.isNotEmpty)
                      Text(
                        mentor.country,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .85),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (mentor.verified)
                const Icon(
                  Icons.verified_rounded,
                  color: Colors.white,
                  size: 22,
                ),
            ],
          ),
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

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.mentor, required this.subtleTextColor});

  final MentorProfile mentor;
  final Color subtleTextColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
      decoration: BoxDecoration(
        color: ScholarBirdColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ScholarBirdColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.school_rounded,
                color: ScholarBirdColors.primary,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mentor.university.isNotEmpty
                      ? mentor.university
                      : 'University not listed',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ScholarBirdColors.ink,
                  ),
                ),
              ),
              if (mentor.premiumOnly)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Premium',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.star_rounded,
                size: 18,
                color: Color(0xFFF59E0B),
              ),
              const SizedBox(width: 4),
              Text(
                mentor.rating > 0
                    ? '${mentor.rating.toStringAsFixed(1)}'
                    : '—',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: ScholarBirdColors.ink,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '(${mentor.totalReviews} reviews)',
                style: TextStyle(color: subtleTextColor, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.mentor});

  final MentorProfile mentor;

  @override
  Widget build(BuildContext context) {
    final stats = <_Stat>[
      _Stat(
        icon: Icons.emoji_events_outlined,
        value: '${mentor.successRate}%',
        label: 'Success rate',
      ),
      _Stat(
        icon: Icons.groups_2_outlined,
        value: '${mentor.studentsHelped}+',
        label: 'Students helped',
      ),
      _Stat(
        icon: Icons.bolt_outlined,
        value: mentor.responseTime,
        label: 'Response time',
      ),
      _Stat(
        icon: Icons.workspace_premium_outlined,
        value: '${mentor.yearsExperience}+',
        label: 'Years exp.',
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 2.4,
      ),
      itemCount: stats.length,
      itemBuilder: (context, index) {
        final s = stats[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: ScholarBirdColors.surface,
            border: Border.all(color: ScholarBirdColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: ScholarBirdColors.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(s.icon, color: ScholarBirdColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      s.value,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: ScholarBirdColors.ink,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      s.label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: ScholarBirdColors.body,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Stat {
  final IconData icon;
  final String value;
  final String label;
  const _Stat({required this.icon, required this.value, required this.label});
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: ScholarBirdColors.ink,
          ),
        ),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: ScholarBirdColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: ScholarBirdColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _PricingCard extends StatelessWidget {
  const _PricingCard({required this.mentor});

  final MentorProfile mentor;

  @override
  Widget build(BuildContext context) {
    final packages = defaultMentorPackages(mentor.id);
    return Container(
      padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
      decoration: BoxDecoration(
        color: ScholarBirdColors.surface,
        border: Border.all(color: ScholarBirdColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _PriceTile(
                  title: 'Hourly',
                  value: mentor.hourlyPrice,
                  currency: mentor.currency,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PriceTile(
                  title: 'Full Package',
                  value: mentor.packagePrice,
                  currency: mentor.currency,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          const Text(
            'Common packages',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: ScholarBirdColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          for (final pkg in packages.take(4))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: ScholarBirdColors.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pkg.name,
                      style: const TextStyle(color: ScholarBirdColors.ink),
                    ),
                  ),
                  Text(
                    pkg.durationLabel,
                    style: const TextStyle(
                      color: ScholarBirdColors.body,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PriceTile extends StatelessWidget {
  const _PriceTile({
    required this.title,
    required this.value,
    required this.currency,
  });

  final String title;
  final double value;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
      symbol: currency.isEmpty ? '\$' : currency,
      decimalDigits: 0,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: ScholarBirdColors.primary.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: ScholarBirdColors.body,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value > 0 ? fmt.format(value) : '—',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: ScholarBirdColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewsSummary extends StatelessWidget {
  const _ReviewsSummary({required this.mentor});

  final MentorProfile mentor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
      decoration: BoxDecoration(
        color: ScholarBirdColors.surface,
        border: Border.all(color: ScholarBirdColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.star_rounded,
                color: Color(0xFFF59E0B),
                size: 24,
              ),
              const SizedBox(width: 6),
              Text(
                mentor.rating > 0
                    ? mentor.rating.toStringAsFixed(1)
                    : 'No reviews yet',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: ScholarBirdColors.ink,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '(${mentor.totalReviews})',
                style: const TextStyle(color: ScholarBirdColors.body),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MentorReviewsScreen(mentor: mentor),
                    ),
                  );
                },
                child: const Text('See all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('mentor_reviews')
                .where('mentorId', isEqualTo: mentor.id)
                .orderBy('createdAt', descending: true)
                .limit(2)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(
                    color: ScholarBirdColors.primary,
                    backgroundColor: Color(0xFFE3EAF8),
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Be the first to share your experience after a session.',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : ScholarBirdColors.body,
                    ),
                  ),
                );
              }
              final docs = snapshot.data!.docs
                  .map((d) => MentorReview.fromMap(
                        {...d.data() as Map<String, dynamic>, 'id': d.id},
                      ))
                  .toList();
              return Column(
                children: [
                  for (final review in docs) _ReviewTile(review: review),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final MentorReview review;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < 5; i++)
                Icon(
                  i < review.rating.round()
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 16,
                  color: const Color(0xFFF59E0B),
                ),
              const SizedBox(width: 8),
              Text(
                review.userName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: ScholarBirdColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            review.review,
            style: const TextStyle(color: ScholarBirdColors.body),
          ),
        ],
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({required this.mentor});

  final MentorProfile mentor;

  Future<void> _whatsapp(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final digits = mentor.whatsapp.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No WhatsApp number on file.')),
      );
      return;
    }
    if (!await launchUrl(
      Uri.parse('https://wa.me/$digits'),
      mode: LaunchMode.externalApplication,
    )) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp.')),
      );
    }
  }

  Future<void> _email(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (mentor.email.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No email on file.')),
      );
      return;
    }
    final uri = Uri(
      scheme: 'mailto',
      path: mentor.email,
      query: 'subject=Mentorship inquiry from ScholarBird',
    );
    if (!await launchUrl(uri)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No email app found.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: ScholarBirdColors.surface,
        boxShadow: [
          BoxShadow(
            color: ScholarBirdColors.primary.withValues(alpha: .08),
            blurRadius: 14,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Row(
        children: [
          _MiniIcon(
            icon: Icons.chat_bubble_rounded,
            tooltip: 'WhatsApp',
            onTap: () => _whatsapp(context),
          ),
          const SizedBox(width: 8),
          _MiniIcon(
            icon: Icons.mail_outline_rounded,
            tooltip: 'Email',
            onTap: () => _email(context),
          ),
          const SizedBox(width: 8),
          _MiniIcon(
            icon: Icons.support_agent_rounded,
            tooltip: 'Request free 5-min call',
            onTap: () {
              if (user == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sign in to request a free call.'),
                  ),
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MentorFreeCallScreen(mentor: mentor),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                if (user == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Sign in to book a mentor.'),
                    ),
                  );
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MentorBookingScreen(mentor: mentor),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: ScholarBirdColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.calendar_month_rounded),
              label: const Text(
                'Book Mentor',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniIcon extends StatelessWidget {
  const _MiniIcon({
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
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: ScholarBirdColors.primary.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: ScholarBirdColors.primary.withValues(alpha: .25),
            ),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: ScholarBirdColors.primary, size: 20),
        ),
      ),
    );
  }
}
