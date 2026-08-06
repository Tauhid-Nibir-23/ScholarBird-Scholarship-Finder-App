import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_ui.dart';
import 'add_scholarship_page.dart';
import 'widgets/admin_badge.dart';
import 'widgets/admin_empty_state.dart';
import 'widgets/admin_section.dart';
import 'widgets/admin_stat_card.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, this.onNavigate});

  final ValueChanged<int>? onNavigate;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DashboardBanner(),
              const SizedBox(height: 24),
              _DashboardStats(),
              const SizedBox(height: 24),
              _QuickActions(onNavigate: onNavigate),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final applications = _RecentApplications();
                  final scholarships = _RecentScholarships();
                  if (constraints.maxWidth < 900) {
                    return Column(
                      children: [
                        applications,
                        const SizedBox(height: 16),
                        scholarships,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: applications),
                      const SizedBox(width: 16),
                      Expanded(child: scholarships),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
}

class _DashboardBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AdminPalette.primary, AdminPalette.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AdminPalette.primary.withValues(alpha: .25),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Welcome back, Admin',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                )),
            SizedBox(height: 8),
            Text(
              'Here is a live view of the ScholarBird community.',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ],
        ),
      );
}

class _DashboardStats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, usersSnap) =>
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance.collection('scholarships').snapshots(),
        builder: (context, scholarshipsSnap) =>
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collectionGroup('applications')
              .snapshots(),
          builder: (context, applicationsSnap) {
            final users = usersSnap.data?.docs ?? const [];
            final scholarships = scholarshipsSnap.data?.docs ?? const [];
            final applications = applicationsSnap.data?.docs ?? const [];

            final activeCount = scholarships.where((doc) {
              if (doc.data()['isHidden'] == true) return false;
              final deadline = _deadlineValue(doc.data()['deadline']);
              return deadline == null || !deadline.isBefore(DateTime.now());
            }).length;

            final expiredCount = scholarships.where((doc) {
              final deadline = _deadlineValue(doc.data()['deadline']);
              return deadline != null && deadline.isBefore(DateTime.now());
            }).length;

            final premiumCount =
                users.where((doc) => _isPremium(doc.data())).length;

            final pendingCount = applications.where((doc) {
              final data = doc.data();
              final status = data['status']?.toString().toLowerCase();
              // Legacy submissions were saved as `Applied`; only admin-marked
              // records with adminAppliedAt are actually in process.
              return status == null ||
                  status == 'pending' ||
                  (status == 'applied' && data['adminAppliedAt'] == null);
            }).length;

            final approvedCount = applications
                .where((doc) =>
                    doc.data()['status']?.toString().toLowerCase() ==
                    'approved')
                .length;

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream:
                  FirebaseFirestore.instance.collection('mentors').snapshots(),
              builder: (context, mentorsSnap) {
                final mentorCount = mentorsSnap.data?.docs.length ?? 0;
                return AdminStatGrid(
                  children: [
                    AdminStatCard(
                      label: 'Total scholarships',
                      value: scholarships.length.toString(),
                      icon: Icons.school_outlined,
                      trend: '${activeCount} active',
                    ),
                    AdminStatCard(
                      label: 'Active scholarships',
                      value: activeCount.toString(),
                      icon: Icons.verified_outlined,
                      iconColor: const Color(0xFF16A34A),
                    ),
                    AdminStatCard(
                      label: 'Expired scholarships',
                      value: expiredCount.toString(),
                      icon: Icons.history,
                      iconColor: const Color(0xFFDC2626),
                    ),
                    AdminStatCard(
                      label: 'Applications',
                      value: applications.length.toString(),
                      icon: Icons.description_outlined,
                      trend: '$pendingCount pending',
                      iconColor: const Color(0xFFD97706),
                    ),
                    AdminStatCard(
                      label: 'Approved applications',
                      value: approvedCount.toString(),
                      icon: Icons.check_circle_outline,
                      iconColor: const Color(0xFF16A34A),
                    ),
                    AdminStatCard(
                      label: 'Registered users',
                      value: users.length.toString(),
                      icon: Icons.people_outline,
                      trend: '$premiumCount premium',
                      iconColor: const Color(0xFF2563EB),
                    ),
                    AdminStatCard(
                      label: 'Premium users',
                      value: premiumCount.toString(),
                      icon: Icons.workspace_premium,
                      iconColor: const Color(0xFFCA8A04),
                    ),
                    AdminStatCard(
                      label: 'Mentors',
                      value: mentorCount.toString(),
                      icon: Icons.person_outline,
                      iconColor: const Color(0xFF7C3AED),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

bool _isPremium(Map<String, dynamic> data) {
  if (data['premium'] == true) return true; // legacy records
  if (data['subscriptionStatus']?.toString().toLowerCase() != 'premium') {
    return false;
  }
  final expiry = data['subscriptionExpiry'];
  final date = expiry is Timestamp
      ? expiry.toDate()
      : expiry is DateTime
          ? expiry
          : expiry is String
              ? DateTime.tryParse(expiry)
              : null;
  return date == null || date.isAfter(DateTime.now());
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({this.onNavigate});

  final ValueChanged<int>? onNavigate;
  @override
  Widget build(BuildContext context) {
    final actions = <_QuickAction>[
      _QuickAction(
        'Add scholarship',
        Icons.add_circle_outline,
        AdminPalette.primary,
        () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AddScholarshipPage()),
        ),
      ),
      _QuickAction(
        'Add mentor',
        Icons.person_add_outlined,
        const Color(0xFF7C3AED),
        () => onNavigate?.call(3),
      ),
      _QuickAction(
        'Add notification',
        Icons.notifications_active_outlined,
        const Color(0xFFEA580C),
        () => onNavigate?.call(5),
      ),
      _QuickAction(
        'View users',
        Icons.people_outline,
        const Color(0xFF2563EB),
        () => onNavigate?.call(2),
      ),
      _QuickAction(
        'Upload banner',
        Icons.image_outlined,
        const Color(0xFF0EA5E9),
        () {
          onNavigate?.call(1);
          _toast(context, 'Choose Add scholarship to upload its banner.');
        },
      ),
      _QuickAction(
        'Refresh database',
        Icons.refresh,
        const Color(0xFF16A34A),
        () => _toast(context, 'Live Firestore data is refreshed.'),
      ),
    ];

    return AdminSection(
      title: 'Quick actions',
      subtitle: 'Common admin tasks in one click.',
      icon: Icons.flash_on_outlined,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cross = constraints.maxWidth >= 1100
              ? 6
              : constraints.maxWidth >= 720
                  ? 4
                  : constraints.maxWidth >= 460
                      ? 3
                      : 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final action in actions)
                SizedBox(
                  width: (constraints.maxWidth - 12 * (cross - 1)) / cross,
                  child: _QuickActionButton(action: action),
                ),
            ],
          );
        },
      ),
    );
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _QuickAction {
  const _QuickAction(this.label, this.icon, this.color, this.onTap);
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _QuickActionButton extends StatefulWidget {
  const _QuickActionButton({required this.action});

  final _QuickAction action;

  @override
  State<_QuickActionButton> createState() => _QuickActionButtonState();
}

class _QuickActionButtonState extends State<_QuickActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: _hovered
              ? widget.action.color.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hovered ? widget.action.color : const Color(0xFFE5E7EB),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.action.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.action.icon, color: widget.action.color),
                const SizedBox(height: 8),
                Text(
                  widget.action.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentApplications extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collectionGroup('applications')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AdminSection(
            title: 'Recent applications',
            icon: Icons.description_outlined,
            child: const Text('Unable to load applications.'),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return AdminSection(
            title: 'Recent applications',
            icon: Icons.description_outlined,
            child: const AdminLoadingSkeleton(itemCount: 4, itemHeight: 48),
          );
        }
        final applications = [...?snapshot.data?.docs]..sort((a, b) =>
            _dateValue(b.data()['appliedAt'])
                .compareTo(_dateValue(a.data()['appliedAt'])));
        final top = applications.take(5).toList();
        return AdminSection(
          title: 'Recent applications',
          icon: Icons.description_outlined,
          child: top.isEmpty
              ? const AdminEmptyState(
                  icon: Icons.description_outlined,
                  title: 'No applications yet',
                  message: 'New submissions will appear here.',
                )
              : Column(
                  children: [
                    for (final app in top)
                      _RecentTile(
                        icon: Icons.description_outlined,
                        title: app.data()['title']?.toString() ??
                            'Untitled scholarship',
                        subtitle:
                            'Applied ${_formatDate(app.data()['appliedAt'])}',
                        trailing: StatusBadge(
                          status: app.data()['status']?.toString() ?? 'pending',
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _RecentScholarships extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('scholarships').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AdminSection(
            title: 'Recent scholarships',
            icon: Icons.school_outlined,
            child: const Text('Unable to load scholarships.'),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return AdminSection(
            title: 'Recent scholarships',
            icon: Icons.school_outlined,
            child: const AdminLoadingSkeleton(itemCount: 4, itemHeight: 48),
          );
        }
        final scholarships = [...?snapshot.data?.docs]..sort((a, b) =>
            _dateValue(b.data()['createdAt'])
                .compareTo(_dateValue(a.data()['createdAt'])));
        final top = scholarships.take(5).toList();
        return AdminSection(
          title: 'Recent scholarships',
          icon: Icons.school_outlined,
          child: top.isEmpty
              ? const AdminEmptyState(
                  icon: Icons.school_outlined,
                  title: 'No scholarships yet',
                  message: 'Tap "+ Add scholarship" to create one.',
                )
              : Column(
                  children: [
                    for (final s in top)
                      _RecentTile(
                        icon: Icons.school_outlined,
                        title: s.data()['title']?.toString() ??
                            'Untitled scholarship',
                        subtitle: _scholarshipSubtitle(s.data()),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AdminPalette.primary.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: AdminPalette.primary),
        ),
        title: Text(title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AdminPalette.heading,
            )),
        subtitle:
            Text(subtitle, style: const TextStyle(color: AdminPalette.body)),
        trailing: trailing,
      );
}

DateTime? _deadlineValue(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

DateTime _dateValue(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.fromMillisecondsSinceEpoch(0);
}

String _formatDate(dynamic value) {
  if (value is Timestamp) {
    final date = value.toDate();
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
  if (value is DateTime) {
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  }
  return 'Date not available';
}

String _scholarshipSubtitle(Map<String, dynamic> data) {
  final country = data['country']?.toString().trim();
  final countryLabel =
      country == null || country.isEmpty ? 'Unknown country' : country;
  return '$countryLabel - ${_formatDate(data['createdAt'])}';
}
