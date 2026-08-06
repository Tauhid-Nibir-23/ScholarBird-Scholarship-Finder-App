import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_ui.dart';

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, usersSnapshot) =>
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream:
              FirebaseFirestore.instance.collection('scholarships').snapshots(),
          builder: (context, scholarshipsSnapshot) =>
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collectionGroup('applications')
                .snapshots(),
            builder: (context, applicationsSnapshot) {
              if (usersSnapshot.hasError ||
                  scholarshipsSnapshot.hasError ||
                  applicationsSnapshot.hasError) {
                return const Center(child: Text('Unable to load analytics.'));
              }
              if (usersSnapshot.connectionState == ConnectionState.waiting ||
                  scholarshipsSnapshot.connectionState ==
                      ConnectionState.waiting ||
                  applicationsSnapshot.connectionState ==
                      ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final users = usersSnapshot.data?.docs ?? [];
              final scholarships = scholarshipsSnapshot.data?.docs ?? [];
              final applications = applicationsSnapshot.data?.docs ?? [];
              final statusCounts = <String, int>{
                'pending': 0,
                'applied': 0,
                'accepted': 0,
                'rejected': 0,
              };
              final scholarshipCounts = <String, int>{};

              for (final application in applications) {
                final data = application.data();
                var status =
                    data['status']?.toString().toLowerCase() ?? 'pending';
                if (status == 'approved') status = 'accepted';
                if (statusCounts.containsKey(status)) {
                  statusCounts[status] = statusCounts[status]! + 1;
                } else {
                  statusCounts['pending'] = statusCounts['pending']! + 1;
                }
                final title = data['title']?.toString().trim();
                if (title != null && title.isNotEmpty) {
                  scholarshipCounts[title] =
                      (scholarshipCounts[title] ?? 0) + 1;
                }
              }

              final mostApplied = scholarshipCounts.entries.isEmpty
                  ? 'No applications yet'
                  : scholarshipCounts.entries
                      .reduce((a, b) => a.value >= b.value ? a : b)
                      .key;
              final recentUsers = [...users]..sort((a, b) =>
                  _createdAt(b.data()).compareTo(_createdAt(a.data())));

              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Analytics',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        const Text('A live overview of ScholarBird activity.'),
                        const SizedBox(height: 28),
                        LayoutBuilder(builder: (context, constraints) {
                          return GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio:
                                constraints.maxWidth < 500 ? 1.7 : 2.25,
                            children: [
                              _MetricCard(
                                  label: 'Total Users',
                                  value: users.length.toString(),
                                  icon: Icons.people_outline),
                              _MetricCard(
                                  label: 'Total Scholarships',
                                  value: scholarships.length.toString(),
                                  icon: Icons.school_outlined),
                              _MetricCard(
                                  label: 'Total Applications',
                                  value: applications.length.toString(),
                                  icon: Icons.description_outlined),
                              _MetricCard(
                                  label: 'Pending Applications',
                                  value: statusCounts['pending'].toString(),
                                  icon: Icons.schedule_outlined),
                              _MetricCard(
                                  label: 'Applied Applications',
                                  value: statusCounts['applied'].toString(),
                                  icon: Icons.assignment_turned_in_outlined),
                              _MetricCard(
                                  label: 'Accepted Applications',
                                  value: statusCounts['accepted'].toString(),
                                  icon: Icons.check_circle_outline),
                              _MetricCard(
                                  label: 'Rejected Applications',
                                  value: statusCounts['rejected'].toString(),
                                  icon: Icons.cancel_outlined),
                            ],
                          );
                        }),
                        const SizedBox(height: 28),
                        _Panel(
                          title: 'Application Status',
                          child: _StatusDonutChart(counts: statusCounts),
                        ),
                        const SizedBox(height: 28),
                        LayoutBuilder(builder: (context, constraints) {
                          final mostAppliedPanel = _Panel(
                            title: 'Most Applied Scholarship',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(
                                  child: Icon(Icons.star_outline)),
                              title: Text(mostApplied),
                              subtitle: Text(
                                  '${scholarshipCounts[mostApplied] ?? 0} application(s)'),
                            ),
                          );
                          final recentUsersPanel = _Panel(
                            title: 'Recent Users',
                            child: recentUsers.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 20),
                                    child: Text('No users found.'))
                                : Column(
                                    children: recentUsers.take(5).map((user) {
                                      final data = user.data();
                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: CircleAvatar(
                                            child:
                                                Text(_initial(data['name']))),
                                        title: Text(data['name']?.toString() ??
                                            'Unnamed user'),
                                        subtitle: Text(
                                            data['email']?.toString() ??
                                                'Ã¢â‚¬â€'),
                                        trailing:
                                            Text(_dateLabel(data['createdAt'])),
                                      );
                                    }).toList(),
                                  ),
                          );
                          if (constraints.maxWidth < 800) {
                            return Column(children: [
                              mostAppliedPanel,
                              const SizedBox(height: 16),
                              recentUsersPanel
                            ]);
                          }
                          return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: mostAppliedPanel),
                                const SizedBox(width: 16),
                                Expanded(child: recentUsersPanel)
                              ]);
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
  return value is Timestamp
      ? value.toDate()
      : DateTime.fromMillisecondsSinceEpoch(0);
}

String _dateLabel(dynamic value) {
  if (value is! Timestamp) return 'Ã¢â‚¬â€';
  final date = value.toDate();
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String _initial(dynamic value) {
  final name = value?.toString().trim() ?? '';
  return name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        child: AdminSurface(
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(icon)),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(value,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text(label, maxLines: 2, overflow: TextOverflow.ellipsis)
                  ])),
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            child
          ]),
        ),
      );
}

class _StatusDonutChart extends StatelessWidget {
  const _StatusDonutChart({required this.counts});

  final Map<String, int> counts;

  static const _items = <({String key, String label, Color color})>[
    (key: 'pending', label: 'Pending', color: Color(0xFF64748B)),
    (key: 'applied', label: 'Applied', color: Color(0xFFD97706)),
    (key: 'accepted', label: 'Accepted', color: Color(0xFF16A34A)),
    (key: 'rejected', label: 'Rejected', color: Color(0xFFDC2626)),
  ];

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (sum, value) => sum + value);
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 24,
        runSpacing: 20,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 180,
            height: 180,
            child: CustomPaint(
              painter: _DonutPainter(
                values: [for (final item in _items) counts[item.key] ?? 0],
                colors: [for (final item in _items) item.color],
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$total',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Text('Applications'),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: math.max(180, constraints.maxWidth - 220),
            child: Column(
              children: [
                for (final item in _items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                                color: item.color, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(item.label)),
                        Text('${counts[item.key] ?? 0}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ],
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

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.values, required this.colors});

  final List<int> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<int>(0, (sum, value) => sum + value);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 12;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.butt;
    if (total == 0) {
      paint.color = const Color(0xFFE2E8F0);
      canvas.drawCircle(center, radius, paint);
      return;
    }
    var startAngle = -math.pi / 2;
    for (var index = 0; index < values.length; index++) {
      final sweep = values[index] / total * math.pi * 2;
      if (sweep > 0) {
        paint.color = colors[index];
        canvas.drawArc(rect, startAngle, sweep, false, paint);
      }
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.colors != colors;
}
