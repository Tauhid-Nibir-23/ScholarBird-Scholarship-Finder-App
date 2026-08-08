/// Admin screen for managing the Mentor Hub marketplace.
///
/// Streams paid mentors from the `mentors_marketplace` collection,
/// supports search, add / edit / disable / feature, and exposes
/// per-mentor bookings, ratings, and earnings from the
/// `mentor_bookings` and `mentor_reviews` collections.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/mentor_profile.dart';
import '../services/mentor_image_service.dart';
import '../theme/scholarbird_theme.dart';
import 'admin_ui.dart';
import 'widgets/admin_badge.dart';
import 'widgets/admin_data_table.dart';
import 'widgets/admin_dialogs.dart';
import 'widgets/admin_empty_state.dart';
import 'widgets/admin_image_picker.dart';
import 'widgets/admin_search_bar.dart';
import 'widgets/admin_section.dart';
import 'widgets/admin_stat_card.dart';

class MentorManagementScreen extends StatefulWidget {
  const MentorManagementScreen({super.key});

  static const String routeName = 'admin_mentor_management';

  @override
  State<MentorManagementScreen> createState() => _MentorManagementScreenState();
}

class _MentorManagementScreenState extends State<MentorManagementScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  static const String _collectionName = 'mentors_marketplace';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MentorProfile> _applyFilters(List<MentorProfile> input) {
    final lowered = _query.trim().toLowerCase();
    return input.where((mentor) {
      if (lowered.isEmpty) return true;
      return mentor.matchesQuery(lowered);
    }).toList();
  }

  Future<void> _toggleDisabled(MentorProfile mentor) async {
    try {
      await FirebaseFirestore.instance
          .collection(_collectionName)
          .doc(mentor.id)
          .update({'disabled': !mentor.disabled});
      if (mounted) {
        AdminDialogs.success(
          context,
          mentor.disabled ? 'Mentor enabled' : 'Mentor disabled',
        );
      }
    } catch (e) {
      if (mounted) {
        AdminDialogs.error(context, 'Could not update mentor: $e');
      }
    }
  }

  Future<void> _toggleFeatured(MentorProfile mentor) async {
    try {
      await FirebaseFirestore.instance
          .collection(_collectionName)
          .doc(mentor.id)
          .update({'featured': !mentor.featured});
      if (mounted) {
        AdminDialogs.success(
          context,
          mentor.featured ? 'Removed from featured' : 'Marked as featured',
        );
      }
    } catch (e) {
      if (mounted) {
        AdminDialogs.error(context, 'Could not update mentor: $e');
      }
    }
  }

  Future<void> _confirmDelete(MentorProfile mentor) async {
    final confirmed = await AdminDialogs.confirm(
      context: context,
      title: 'Delete mentor?',
      message:
          'This will permanently remove ${mentor.name} from the Mentor Hub. '
          'Existing bookings and reviews will remain.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    try {
      await FirebaseFirestore.instance
          .collection(_collectionName)
          .doc(mentor.id)
          .delete();
      if (mounted) {
        AdminDialogs.success(context, 'Mentor deleted');
      }
    } catch (e) {
      if (mounted) {
        AdminDialogs.error(context, 'Could not delete mentor: $e');
      }
    }
  }

  Future<void> _openForm({MentorProfile? mentor}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _MentorManagementForm(mentor: mentor),
      ),
    );
  }

  Future<void> _openMentorDetail(MentorProfile mentor) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _MentorAdminOverview(mentor: mentor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ScholarBirdColors.background,
      appBar: AppBar(
        backgroundColor: ScholarBirdColors.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'Mentor Hub · Admin',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: ScholarBirdColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add mentor'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection(_collectionName)
            .orderBy('name')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load mentors: ${snapshot.error}',
                style: const TextStyle(color: Colors.redAccent),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: ScholarBirdColors.primary,
              ),
            );
          }
          final docs = snapshot.data?.docs ?? const [];
          final mentors = docs
              .map((d) => MentorProfile.fromMap(
                    {...d.data() as Map<String, dynamic>, 'id': d.id},
                  ))
              .toList();
          final filtered = _applyFilters(mentors);

          return ListView(
            padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
            children: [
              AdminSection(
                title: 'Mentor roster',
                subtitle: '${mentors.length} mentors in the marketplace',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AdminSearchBar(
                      controller: _searchCtrl,
                      hintText: 'Search by name, university, expertise',
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 12),
                    if (filtered.isEmpty)
                      AdminEmptyState(
                        icon: Icons.school_outlined,
                        title: mentors.isEmpty
                            ? 'No mentors yet'
                            : 'No mentors match your search',
                        message: mentors.isEmpty
                            ? 'Tap “Add mentor” to add the first paid mentor.'
                            : 'Try a different search term.',
                      )
                    else
                      AdminDataTable<MentorProfile>(
                        columns: const [
                          AdminTableColumn(label: 'Mentor'),
                          AdminTableColumn(label: 'Pricing'),
                          AdminTableColumn(label: 'Rating'),
                          AdminTableColumn(label: 'Status'),
                          AdminTableColumn(label: 'Actions'),
                        ],
                        cardBuilder: (mentor) => _MentorCard(
                          mentor: mentor,
                          onTap: () => _openMentorDetail(mentor),
                          onEdit: () => _openForm(mentor: mentor),
                          onToggle: () => _toggleDisabled(mentor),
                          onFeature: () => _toggleFeatured(mentor),
                          onDelete: () => _confirmDelete(mentor),
                        ),
                        rowBuilder: (mentor) => [
                          DataCell(
                            InkWell(
                              onTap: () => _openMentorDetail(mentor),
                              child: Row(
                                children: [
                                  AdminAvatar(
                                    name: mentor.name,
                                    photoUrl: mentor.profilePhoto,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          mentor.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          mentor.university,
                                          style: const TextStyle(
                                            color: AdminPalette.body,
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${mentor.currency.isEmpty ? '\$' : mentor.currency} '
                              '${mentor.hourlyPrice.toStringAsFixed(0)} / hr',
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: Color(0xFFF59E0B),
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  mentor.rating > 0
                                      ? '${mentor.rating.toStringAsFixed(1)} '
                                          '(${mentor.totalReviews})'
                                      : '—',
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (mentor.featured)
                                  const AdminBadge(
                                    label: 'Featured',
                                    color: Color(0xFFF59E0B),
                                  ),
                                if (mentor.disabled) ...[
                                  if (mentor.featured) const SizedBox(width: 6),
                                  const AdminBadge(
                                    label: 'Disabled',
                                    color: Colors.redAccent,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  tooltip: 'Edit',
                                  onPressed: () => _openForm(mentor: mentor),
                                ),
                                IconButton(
                                  icon: Icon(
                                    mentor.featured
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                  ),
                                  tooltip: mentor.featured
                                      ? 'Unmark featured'
                                      : 'Mark featured',
                                  onPressed: () => _toggleFeatured(mentor),
                                ),
                                IconButton(
                                  icon: Icon(
                                    mentor.disabled
                                        ? Icons.lock_open_outlined
                                        : Icons.lock_outline,
                                  ),
                                  tooltip: mentor.disabled
                                      ? 'Enable mentor'
                                      : 'Disable mentor',
                                  onPressed: () => _toggleDisabled(mentor),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.redAccent,
                                  ),
                                  tooltip: 'Delete',
                                  onPressed: () => _confirmDelete(mentor),
                                ),
                              ],
                            ),
                          ),
                        ],
                        rows: filtered,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MentorCard extends StatelessWidget {
  const _MentorCard({
    required this.mentor,
    required this.onTap,
    required this.onEdit,
    required this.onToggle,
    required this.onFeature,
    required this.onDelete,
  });

  final MentorProfile mentor;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onFeature;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AdminAvatar(
                name: mentor.name,
                photoUrl: mentor.profilePhoto,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mentor.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AdminPalette.heading,
                      ),
                    ),
                    Text(
                      mentor.university,
                      style: const TextStyle(
                        color: AdminPalette.body,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (mentor.featured)
                const AdminBadge(
                  label: 'Featured',
                  color: Color(0xFFF59E0B),
                ),
              if (mentor.disabled) ...[
                const SizedBox(width: 6),
                const AdminBadge(
                  label: 'Disabled',
                  color: Colors.redAccent,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _InfoTile(
                icon: Icons.payments_outlined,
                label: '${mentor.currency.isEmpty ? '\$' : mentor.currency} '
                    '${mentor.hourlyPrice.toStringAsFixed(0)} / hr',
              ),
              _InfoTile(
                icon: Icons.star_rounded,
                color: const Color(0xFFF59E0B),
                label: mentor.rating > 0
                    ? '${mentor.rating.toStringAsFixed(1)} '
                        '(${mentor.totalReviews})'
                    : 'No reviews',
              ),
              _InfoTile(
                icon: Icons.bolt_outlined,
                label: mentor.responseTime.isEmpty ? '—' : mentor.responseTime,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Overview'),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
                tooltip: 'Edit',
              ),
              IconButton(
                icon: Icon(
                  mentor.featured
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                ),
                onPressed: onFeature,
                tooltip: 'Feature',
              ),
              IconButton(
                icon: Icon(
                  mentor.disabled
                      ? Icons.lock_open_outlined
                      : Icons.lock_outline,
                ),
                onPressed: onToggle,
                tooltip: mentor.disabled ? 'Enable' : 'Disable',
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                ),
                onPressed: onDelete,
                tooltip: 'Delete',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    this.color = AdminPalette.primary,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: AdminPalette.body, fontSize: 12),
        ),
      ],
    );
  }
}

class _MentorAdminOverview extends StatelessWidget {
  const _MentorAdminOverview({required this.mentor});

  final MentorProfile mentor;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      symbol: mentor.currency.isEmpty ? '\$' : mentor.currency,
      decimalDigits: 0,
    );

    return Scaffold(
      backgroundColor: ScholarBirdColors.background,
      appBar: AppBar(
        backgroundColor: ScholarBirdColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          mentor.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('mentor_bookings')
            .where('mentorId', isEqualTo: mentor.id)
            .snapshots(),
        builder: (context, bookingsSnapshot) {
          if (bookingsSnapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load bookings: ${bookingsSnapshot.error}',
              ),
            );
          }
          final bookings = bookingsSnapshot.data?.docs ?? const [];
          final completed = bookings.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['status'] == 'completed';
          }).toList();
          final earnings = completed.fold<double>(0, (sum, doc) {
            final data = doc.data() as Map<String, dynamic>;
            final price = (data['price'] as num?)?.toDouble() ?? 0;
            return sum + price;
          });

          return ListView(
            padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
            children: [
              AdminSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AdminAvatar(
                          name: mentor.name,
                          radius: 28,
                          photoUrl: mentor.profilePhoto,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mentor.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                  color: AdminPalette.heading,
                                ),
                              ),
                              Text(
                                mentor.designation,
                                style:
                                    const TextStyle(color: AdminPalette.body),
                              ),
                              Text(
                                mentor.university,
                                style: const TextStyle(
                                  color: AdminPalette.body,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (mentor.country.isNotEmpty ||
                        mentor.email.isNotEmpty ||
                        mentor.whatsapp.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          if (mentor.country.isNotEmpty)
                            _OverviewMeta(
                              icon: Icons.public_rounded,
                              label: mentor.country,
                            ),
                          if (mentor.email.isNotEmpty)
                            _OverviewMeta(
                              icon: Icons.mail_outline_rounded,
                              label: mentor.email,
                            ),
                          if (mentor.whatsapp.isNotEmpty)
                            _OverviewMeta(
                              icon: Icons.chat_bubble_outline_rounded,
                              label: mentor.whatsapp,
                            ),
                        ],
                      ),
                    ],
                    if (mentor.expertise.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tag in mentor.expertise)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AdminPalette.primary
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                tag,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AdminPalette.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (mentor.bio.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        mentor.bio,
                        style: const TextStyle(
                          color: AdminPalette.body,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AdminStatCard(
                      icon: Icons.calendar_month_rounded,
                      label: 'Bookings',
                      value: bookings.length.toString(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AdminStatCard(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'Completed',
                      value: completed.length.toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AdminStatCard(
                      icon: Icons.payments_outlined,
                      label: 'Earnings',
                      value: money.format(earnings),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AdminStatCard(
                      icon: Icons.star_rounded,
                      label: 'Rating',
                      value: mentor.rating > 0
                          ? '${mentor.rating.toStringAsFixed(1)} '
                              '(${mentor.totalReviews})'
                          : '—',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AdminSection(
                title: 'Recent bookings',
                subtitle: 'Last 5 sessions',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: bookings.isEmpty
                      ? [
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'No bookings yet.',
                              style: TextStyle(color: AdminPalette.body),
                            ),
                          ),
                        ]
                      : bookings.take(5).map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return _BookingTile(data: data);
                        }).toList(),
                ),
              ),
              const SizedBox(height: 16),
              AdminSection(
                title: 'Recent reviews',
                subtitle: 'Latest student feedback',
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('mentor_reviews')
                      .where('mentorId', isEqualTo: mentor.id)
                      .orderBy('createdAt', descending: true)
                      .limit(5)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: LinearProgressIndicator(),
                      );
                    }
                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No reviews yet.',
                          style: TextStyle(color: AdminPalette.body),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: docs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final rating =
                            (data['rating'] as num?)?.toDouble() ?? 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  for (var i = 0; i < 5; i++)
                                    Icon(
                                      i < rating.round()
                                          ? Icons.star_rounded
                                          : Icons.star_outline_rounded,
                                      size: 14,
                                      color: const Color(0xFFF59E0B),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      data['userName']?.toString() ?? 'Student',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      data['comment']?.toString() ?? '',
                                      style: const TextStyle(
                                        color: AdminPalette.body,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OverviewMeta extends StatelessWidget {
  const _OverviewMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AdminPalette.body),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              color: AdminPalette.body,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _BookingTile extends StatelessWidget {
  const _BookingTile({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      symbol: (data['currency']?.toString() ?? '').isEmpty
          ? '\$'
          : data['currency'].toString(),
      decimalDigits: 0,
    );
    final price = (data['price'] as num?)?.toDouble() ?? 0;
    final status = data['status']?.toString() ?? 'pending';
    final type = data['type']?.toString() ?? 'booking';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: ScholarBirdColors.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              type == 'free_call'
                  ? Icons.support_agent_rounded
                  : Icons.calendar_month_rounded,
              color: ScholarBirdColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['userName']?.toString() ?? 'Student',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  type == 'free_call'
                      ? 'Free call request'
                      : data['packageTitle']?.toString() ?? 'Booking',
                  style: const TextStyle(
                    color: AdminPalette.body,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                type == 'free_call' ? 'Free' : money.format(price),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              AdminBadge(
                label: status,
                color: _statusColor(status),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
      case 'declined':
        return Colors.redAccent;
      case 'confirmed':
      case 'accepted':
        return Colors.indigo;
      default:
        return AdminPalette.primary;
    }
  }
}

class _MentorManagementForm extends StatefulWidget {
  const _MentorManagementForm({this.mentor});

  final MentorProfile? mentor;

  @override
  State<_MentorManagementForm> createState() => _MentorManagementFormState();
}

class _MentorManagementFormState extends State<_MentorManagementForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _designation;
  late final TextEditingController _university;
  late final TextEditingController _country;
  late final TextEditingController _email;
  late final TextEditingController _whatsapp;
  late final TextEditingController _bio;
  late final TextEditingController _expertise;
  late final TextEditingController _hourlyPrice;
  late final TextEditingController _packagePrice;
  late final TextEditingController _currency;
  late final TextEditingController _responseTime;
  late final TextEditingController _yearsExperience;
  late final TextEditingController _languages;
  late final TextEditingController _successRate;
  late final TextEditingController _studentsHelped;
  late final TextEditingController _profilePhoto;
  late final TextEditingController _availability;
  bool _verified = false;
  bool _featured = false;
  bool _premiumOnly = false;
  bool _saving = false;
  bool _photoUploading = false;

  /// Stable doc id for the marketplace mentor. Generated up-front so
  /// the Supabase object path (`mentors-marketplace/{id}.jpg`) is fixed
  /// before the user clicks Save.
  late final String _mentorId;

  static const String _collectionName = 'mentors_marketplace';

  @override
  void initState() {
    super.initState();
    final m = widget.mentor;
    _mentorId = m?.id ??
        FirebaseFirestore.instance.collection(_collectionName).doc().id;
    _name = TextEditingController(text: m?.name ?? '');
    _designation = TextEditingController(text: m?.designation ?? '');
    _university = TextEditingController(text: m?.university ?? '');
    _country = TextEditingController(text: m?.country ?? '');
    _email = TextEditingController(text: m?.email ?? '');
    _whatsapp = TextEditingController(text: m?.whatsapp ?? '');
    _bio = TextEditingController(text: m?.bio ?? '');
    _expertise = TextEditingController(text: m?.expertise.join(', ') ?? '');
    _hourlyPrice =
        TextEditingController(text: m?.hourlyPrice.toStringAsFixed(0) ?? '0');
    _packagePrice =
        TextEditingController(text: m?.packagePrice.toStringAsFixed(0) ?? '0');
    _currency = TextEditingController(text: m?.currency ?? '\$');
    _responseTime = TextEditingController(text: m?.responseTime ?? '');
    _yearsExperience = TextEditingController(
      text: m?.yearsExperience.toString() ?? '0',
    );
    _languages = TextEditingController(text: m?.languages.join(', ') ?? '');
    _successRate = TextEditingController(
      text: m?.successRate.toString() ?? '0',
    );
    _studentsHelped = TextEditingController(
      text: m?.studentsHelped.toString() ?? '0',
    );
    _profilePhoto = TextEditingController(text: m?.profilePhoto ?? '');
    // Rebuild when the portrait URL changes so AdminImagePicker shows
    // the freshly uploaded image and the Remove option appears.
    _profilePhoto.addListener(_onProfilePhotoChanged);
    _availability = TextEditingController(text: m?.availability ?? '');
    _verified = m?.verified ?? false;
    _featured = m?.featured ?? false;
    _premiumOnly = m?.premiumOnly ?? false;
  }

  @override
  void dispose() {
    _profilePhoto.removeListener(_onProfilePhotoChanged);
    for (final c in [
      _name,
      _designation,
      _university,
      _country,
      _email,
      _whatsapp,
      _bio,
      _expertise,
      _hourlyPrice,
      _packagePrice,
      _currency,
      _responseTime,
      _yearsExperience,
      _languages,
      _successRate,
      _studentsHelped,
      _profilePhoto,
      _availability,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Triggered whenever `_profilePhoto` text changes (uploads, edits,
  /// removals) so the portrait preview rebuilds.
  void _onProfilePhotoChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final data = {
        'name': _name.text.trim(),
        'designation': _designation.text.trim(),
        'university': _university.text.trim(),
        'country': _country.text.trim(),
        'email': _email.text.trim(),
        'whatsapp': _whatsapp.text.trim(),
        'bio': _bio.text.trim(),
        'expertise': _expertise.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        'hourlyPrice': double.tryParse(_hourlyPrice.text.trim()) ?? 0,
        'packagePrice': double.tryParse(_packagePrice.text.trim()) ?? 0,
        'currency': _currency.text.trim(),
        'responseTime': _responseTime.text.trim(),
        'yearsExperience': int.tryParse(_yearsExperience.text.trim()) ?? 0,
        'languages': _languages.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        'successRate': int.tryParse(_successRate.text.trim()) ?? 0,
        'studentsHelped': int.tryParse(_studentsHelped.text.trim()) ?? 0,
        'profilePhoto': _profilePhoto.text.trim(),
        'availability': _availability.text.trim(),
        'verified': _verified,
        'featured': _featured,
        'premiumOnly': _premiumOnly,
        'disabled': widget.mentor?.disabled ?? false,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.mentor == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
        data['rating'] = 0.0;
        data['totalReviews'] = 0;
        // Use the pre-generated _mentorId so the Firestore doc id matches
        // the Supabase object path used for any portrait uploaded above.
        await FirebaseFirestore.instance
            .collection(_collectionName)
            .doc(_mentorId)
            .set(data);
      } else {
        await FirebaseFirestore.instance
            .collection(_collectionName)
            .doc(widget.mentor!.id)
            .update(data);
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Mentor saved.')),
      );
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save mentor: $e')),
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Uploads a marketplace portrait (gallery) to Supabase and mirrors
  /// the resulting URL into the `_profilePhoto` text controller so the
  /// rest of the form / save logic picks it up automatically.
  Future<String?> _uploadMarketplacePortrait({
    required ImageSource source,
  }) async {
    setState(() => _photoUploading = true);
    try {
      final url = await MentorImageService.instance
          .pickAndUploadMarketplacePortrait(_mentorId, source: source);
      if (url != null) {
        _profilePhoto.text = url;
        // Trigger listeners (e.g. any widget bound to the controller).
        _profilePhoto.selection =
            TextSelection.collapsed(offset: _profilePhoto.text.length);
      }
      return url;
    } finally {
      if (mounted) setState(() => _photoUploading = false);
    }
  }

  /// Removes the marketplace portrait from Supabase and clears the
  /// text controller.
  Future<void> _removeMarketplacePortrait() async {
    setState(() => _photoUploading = true);
    try {
      await MentorImageService.instance.removeMarketplacePortrait(_mentorId);
      _profilePhoto.clear();
    } finally {
      if (mounted) setState(() => _photoUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ScholarBirdColors.background,
      appBar: AppBar(
        backgroundColor: ScholarBirdColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          widget.mentor == null ? 'Add mentor' : 'Edit mentor',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text(
              'Save',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
          children: [
            _Section(
              title: 'Portrait',
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: ScholarBirdSpacing.small,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AdminImagePicker(
                        photoUrl: _profilePhoto.text,
                        title: 'Marketplace portrait',
                        subtitle: 'Tap to upload or take a photo. Stored in '
                            'Supabase at mentors-marketplace/{id}.jpg.',
                        fallbackLabel: _name.text.isNotEmpty
                            ? _name.text.characters.first.toUpperCase()
                            : '?',
                        shape: AdminImagePickerShape.circle,
                        size: 140,
                        onUploadFromGallery: () => _uploadMarketplacePortrait(
                          source: ImageSource.gallery,
                        ),
                        onUploadFromCamera: () => _uploadMarketplacePortrait(
                          source: ImageSource.camera,
                        ),
                        onRemove: _profilePhoto.text.isNotEmpty
                            ? _removeMarketplacePortrait
                            : null,
                      ),
                      if (_photoUploading) ...[
                        const SizedBox(height: 8),
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            _Section(
              title: 'Identity',
              children: [
                _Field(controller: _name, label: 'Full name', required: true),
                _Field(
                  controller: _designation,
                  label: 'Designation',
                  hintText: 'PhD Candidate, Senior Researcher, etc.',
                ),
                _Field(
                  controller: _university,
                  label: 'University / Institution',
                ),
                _Field(controller: _country, label: 'Country'),
                _Field(
                  controller: _profilePhoto,
                  label: 'Portrait URL (auto-filled)',
                  hintText: 'Filled by uploader above, or paste a URL',
                ),
              ],
            ),
            _Section(
              title: 'Contact',
              children: [
                _Field(
                  controller: _email,
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                ),
                _Field(
                  controller: _whatsapp,
                  label: 'WhatsApp number',
                  hintText: 'With country code, digits only',
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
            _Section(
              title: 'Profile',
              children: [
                _Field(
                  controller: _bio,
                  label: 'About',
                  maxLines: 5,
                  required: true,
                ),
                _Field(
                  controller: _expertise,
                  label: 'Expertise (comma-separated)',
                  hintText: 'SOP review, CV editing, Interview prep',
                ),
                _Field(
                  controller: _languages,
                  label: 'Languages (comma-separated)',
                  hintText: 'English, French',
                ),
                _Field(
                  controller: _availability,
                  label: 'Availability',
                  hintText: 'Weekends 10:00 — 14:00 GMT',
                ),
              ],
            ),
            _Section(
              title: 'Stats & pricing',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        controller: _currency,
                        label: 'Currency',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Field(
                        controller: _hourlyPrice,
                        label: 'Hourly price',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Field(
                        controller: _packagePrice,
                        label: 'Full package',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        controller: _responseTime,
                        label: 'Response time',
                        hintText: '< 2 hrs',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Field(
                        controller: _yearsExperience,
                        label: 'Years experience',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _Field(
                        controller: _successRate,
                        label: 'Success rate %',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Field(
                        controller: _studentsHelped,
                        label: 'Students helped',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            _Section(
              title: 'Visibility',
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Verified'),
                  subtitle: const Text('Show a verified badge on the card.'),
                  value: _verified,
                  onChanged: (v) => setState(() => _verified = v),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Featured'),
                  subtitle: const Text(
                    'Highlight at the top of the Mentor Hub.',
                  ),
                  value: _featured,
                  onChanged: (v) => setState(() => _featured = v),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Premium only'),
                  subtitle: const Text(
                    'Only Premium subscribers can view full profile.',
                  ),
                  value: _premiumOnly,
                  onChanged: (v) => setState(() => _premiumOnly = v),
                ),
              ],
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
        decoration: BoxDecoration(
          color: ScholarBirdColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ScholarBirdColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: ScholarBirdColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hintText,
    this.keyboardType,
    this.maxLines = 1,
    this.required = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hintText;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: required
            ? (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Required';
                }
                return null;
              }
            : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
