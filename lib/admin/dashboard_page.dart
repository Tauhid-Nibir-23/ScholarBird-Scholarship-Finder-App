import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_ui.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, usersSnapshot) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('scholarships').snapshots(),
          builder: (context, scholarshipsSnapshot) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collectionGroup('applications').snapshots(),
            builder: (context, applicationsSnapshot) {
              if (usersSnapshot.hasError || scholarshipsSnapshot.hasError || applicationsSnapshot.hasError) {
                return const Center(child: Text('Unable to load dashboard data.'));
              }
              if (usersSnapshot.connectionState == ConnectionState.waiting || scholarshipsSnapshot.connectionState == ConnectionState.waiting || applicationsSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AdminPalette.primary));
              }

              final users = usersSnapshot.data?.docs ?? [];
              final scholarships = scholarshipsSnapshot.data?.docs ?? [];
              final applications = applicationsSnapshot.data?.docs ?? [];
              final usersById = <String, Map<String, dynamic>>{for (final user in users) user.id: user.data()};
              final pendingCount = applications.where((application) => application.data()['status']?.toString().toLowerCase() == 'pending').length;
              final recentApplications = [...applications]..sort((a, b) => _dateValue(b.data()['appliedAt']).compareTo(_dateValue(a.data()['appliedAt'])));
              final recentScholarships = [...scholarships]..sort((a, b) => _dateValue(b.data()['createdAt']).compareTo(_dateValue(a.data()['createdAt'])));

              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [AdminPalette.primary, AdminPalette.primaryDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [BoxShadow(color: AdminPalette.primary.withValues(alpha: .25), blurRadius: 18, offset: const Offset(0, 7))],
                      ),
                      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Welcome back, Admin', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                        SizedBox(height: 8),
                        Text('Here is a live view of the ScholarBird community.', style: TextStyle(color: Colors.white70, fontSize: 15)),
                      ]),
                    ),
                    const SizedBox(height: 28),
                    Wrap(spacing: 16, runSpacing: 16, children: [
                      _MetricCard(label: 'Total scholarships', value: scholarships.length.toString(), icon: Icons.school_outlined),
                      _MetricCard(label: 'Total applications', value: applications.length.toString(), icon: Icons.description_outlined),
                      _MetricCard(label: 'Total users', value: users.length.toString(), icon: Icons.people_outline),
                      _MetricCard(label: 'Pending applications', value: pendingCount.toString(), icon: Icons.schedule_outlined),
                    ]),
                    const SizedBox(height: 28),
                    LayoutBuilder(builder: (context, constraints) {
                      final applicationsPanel = _RecentApplications(
                        applications: recentApplications.take(4).toList(),
                        usersById: usersById,
                      );
                      final scholarshipsPanel = _RecentScholarships(
                        scholarships: recentScholarships.take(4).toList(),
                      );
                      if (constraints.maxWidth < 820) return Column(children: [applicationsPanel, const SizedBox(height: 16), scholarshipsPanel]);
                      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: applicationsPanel), const SizedBox(width: 16), Expanded(child: scholarshipsPanel)]);
                    }),
                  ]),
                ),
              );
            },
          ),
        ),
      );
}

DateTime _dateValue(dynamic value) => value is Timestamp ? value.toDate() : DateTime.fromMillisecondsSinceEpoch(0);

String _dateLabel(dynamic value) {
  if (value is! Timestamp) return '—';
  final date = value.toDate();
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String _applicationUserId(DocumentSnapshot<Map<String, dynamic>> application) => application.reference.parent.parent?.id ?? '';

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 250,
        child: AdminSurface(
          child: Row(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: AdminPalette.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: AdminPalette.primary)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AdminPalette.heading, fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(label, style: const TextStyle(color: AdminPalette.body))])),
          ]),
        ),
      );
}

class _RecentApplications extends StatelessWidget {
  const _RecentApplications({required this.applications, required this.usersById});

  final List<DocumentSnapshot<Map<String, dynamic>>> applications;
  final Map<String, Map<String, dynamic>> usersById;

  @override
  Widget build(BuildContext context) => _RecentSurface(
        title: 'Recent Applications',
        icon: Icons.description_outlined,
        child: applications.isEmpty
            ? const _EmptyRecent(text: 'No applications found.')
            : Column(
                children: applications.map((application) {
                  final data = application.data() ?? <String, dynamic>{};
                  final user = usersById[_applicationUserId(application)];
                  return _RecentTile(
                    icon: Icons.description_outlined,
                    title: user?['name']?.toString() ?? 'Unknown student',
                    subtitle: '${data['title']?.toString() ?? 'Untitled scholarship'} • ${_dateLabel(data['appliedAt'])}',
                    trailing: _StatusLabel(status: data['status']?.toString() ?? '—'),
                  );
                }).toList(),
              ),
      );
}

class _RecentScholarships extends StatelessWidget {
  const _RecentScholarships({required this.scholarships});

  final List<DocumentSnapshot<Map<String, dynamic>>> scholarships;

  @override
  Widget build(BuildContext context) => _RecentSurface(
        title: 'Recent Scholarships',
        icon: Icons.school_outlined,
        child: scholarships.isEmpty
            ? const _EmptyRecent(text: 'No scholarships found.')
            : Column(
                children: scholarships.map((scholarship) {
                  final data = scholarship.data() ?? <String, dynamic>{};;
                  return _RecentTile(
                    icon: Icons.school_outlined,
                    title: data['title']?.toString() ?? 'Untitled scholarship',
                    subtitle: '${data['country']?.toString() ?? '—'} • ${_dateLabel(data['createdAt'])}',
                  );
                }).toList(),
              ),
      );
}

class _RecentSurface extends StatelessWidget {
  const _RecentSurface({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => AdminSurface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, color: AdminPalette.primary), const SizedBox(width: 10), Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AdminPalette.heading, fontWeight: FontWeight.w700))]),
          const SizedBox(height: 12),
          child,
        ]),
      );
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.icon, required this.title, required this.subtitle, this.trailing});

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: AdminPalette.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 20, color: AdminPalette.primary)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AdminPalette.heading)),
        subtitle: Text(subtitle, style: const TextStyle(color: AdminPalette.body)),
        trailing: trailing,
      );
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text(text, style: const TextStyle(color: AdminPalette.body))),
      );
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) => Text(
        status,
        style: const TextStyle(color: AdminPalette.primary, fontWeight: FontWeight.w700, fontSize: 12),
      );
}
