import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_ui.dart';

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, usersSnapshot) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('scholarships').snapshots(),
          builder: (context, scholarshipsSnapshot) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collectionGroup('applications').snapshots(),
            builder: (context, applicationsSnapshot) {
              if (usersSnapshot.hasError || scholarshipsSnapshot.hasError || applicationsSnapshot.hasError) {
                return const Center(child: Text('Unable to load analytics.'));
              }
              if (usersSnapshot.connectionState == ConnectionState.waiting || scholarshipsSnapshot.connectionState == ConnectionState.waiting || applicationsSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final users = usersSnapshot.data?.docs ?? [];
              final scholarships = scholarshipsSnapshot.data?.docs ?? [];
              final applications = applicationsSnapshot.data?.docs ?? [];
              final statusCounts = <String, int>{'pending': 0, 'approved': 0, 'rejected': 0};
              final scholarshipCounts = <String, int>{};

              for (final application in applications) {
                final data = application.data();
                final status = data['status']?.toString().toLowerCase() ?? 'pending';
                if (statusCounts.containsKey(status)) {
                  statusCounts[status] = statusCounts[status]! + 1;
                } else {
                  statusCounts['pending'] = statusCounts['pending']! + 1;
                }
                final title = data['title']?.toString().trim();
                if (title != null && title.isNotEmpty) {
                  scholarshipCounts[title] = (scholarshipCounts[title] ?? 0) + 1;
                }
              }

              final mostApplied = scholarshipCounts.entries.isEmpty
                  ? 'No applications yet'
                  : scholarshipCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
              final recentUsers = [...users]..sort((a, b) => _createdAt(b.data()).compareTo(_createdAt(a.data())));

              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Analytics', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text('A live overview of ScholarBird activity.'),
                    const SizedBox(height: 28),
                    Wrap(spacing: 16, runSpacing: 16, children: [
                      _MetricCard(label: 'Total Users', value: users.length.toString(), icon: Icons.people_outline),
                      _MetricCard(label: 'Total Scholarships', value: scholarships.length.toString(), icon: Icons.school_outlined),
                      _MetricCard(label: 'Total Applications', value: applications.length.toString(), icon: Icons.description_outlined),
                      _MetricCard(label: 'Pending Applications', value: statusCounts['pending'].toString(), icon: Icons.schedule_outlined),
                      _MetricCard(label: 'Approved Applications', value: statusCounts['approved'].toString(), icon: Icons.check_circle_outline),
                      _MetricCard(label: 'Rejected Applications', value: statusCounts['rejected'].toString(), icon: Icons.cancel_outlined),
                    ]),
                    const SizedBox(height: 28),
                    LayoutBuilder(builder: (context, constraints) {
                      final mostAppliedPanel = _Panel(
                        title: 'Most Applied Scholarship',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(child: const Icon(Icons.star_outline)),
                          title: Text(mostApplied),
                          subtitle: Text('${scholarshipCounts[mostApplied] ?? 0} application(s)'),
                        ),
                      );
                      final recentUsersPanel = _Panel(
                        title: 'Recent Users',
                        child: recentUsers.isEmpty
                            ? const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('No users found.'))
                            : Column(
                                children: recentUsers.take(5).map((user) {
                                  final data = user.data();
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(child: Text(_initial(data['name']))),
                                    title: Text(data['name']?.toString() ?? 'Unnamed user'),
                                    subtitle: Text(data['email']?.toString() ?? '—'),
                                    trailing: Text(_dateLabel(data['createdAt'])),
                                  );
                                }).toList(),
                              ),
                      );
                      if (constraints.maxWidth < 800) {
                        return Column(children: [mostAppliedPanel, const SizedBox(height: 16), recentUsersPanel]);
                      }
                      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: mostAppliedPanel), const SizedBox(width: 16), Expanded(child: recentUsersPanel)]);
                    }),
                  ]),
                ),
              );
            },
          ),
        ),
      );
}

DateTime _createdAt(Map<String, dynamic> data) {
  final value = data['createdAt'];
  return value is Timestamp ? value.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
}

String _dateLabel(dynamic value) {
  if (value is! Timestamp) return '—';
  final date = value.toDate();
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String _initial(dynamic value) {
  final name = value?.toString().trim() ?? '';
  return name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 220,
        child: AdminSurface(
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: Icon(icon)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)), Text(label, maxLines: 2, overflow: TextOverflow.ellipsis)])),
            ]),
          ),
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => AdminSurface(
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 12), child]),
        ),
      );
}
