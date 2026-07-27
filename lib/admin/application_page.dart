import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_ui.dart';

class ApplicationPage extends StatelessWidget {
  const ApplicationPage({super.key});

  Future<void> _setStatus(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> application,
    String status,
  ) async {
    try {
      await application.reference.update({'status': status});
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update application status.')),
        );
      }
    }
  }

  Future<void> _delete(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> application,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete application?'),
        content: const Text('This permanently removes the application record from Firestore.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await application.reference.delete();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete application.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, usersSnapshot) {
          final users = <String, Map<String, dynamic>>{
            for (final user in usersSnapshot.data?.docs ?? []) user.id: user.data(),
          };
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collectionGroup('applications').snapshots(),
            builder: (context, applicationsSnapshot) {
              if (applicationsSnapshot.hasError || usersSnapshot.hasError) {
                return const Center(child: Text('Unable to load applications.'));
              }
              if (applicationsSnapshot.connectionState == ConnectionState.waiting || usersSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final applications = applicationsSnapshot.data?.docs ?? [];
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Applications', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text('Review and decide on student scholarship applications.'),
                    const SizedBox(height: 28),
                    AdminSurface(
                      padding: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: applications.isEmpty
                            ? const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No applications found.')))
                            : LayoutBuilder(
                                builder: (context, constraints) => constraints.maxWidth < 800
                                    ? Column(children: applications.map((application) => _ApplicationCard(application: application, user: users[_userId(application)], onApprove: () => _setStatus(context, application, 'approved'), onReject: () => _setStatus(context, application, 'rejected'), onDelete: () => _delete(context, application))).toList())
                                    : SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: DataTable(
                                          columns: const [
                                            DataColumn(label: Text('Student')),
                                            DataColumn(label: Text('Email')),
                                            DataColumn(label: Text('Scholarship')),
                                            DataColumn(label: Text('Applied date')),
                                            DataColumn(label: Text('Status')),
                                            DataColumn(label: Text('Actions')),
                                          ],
                                          rows: applications.map((application) {
                                            final data = application.data() ?? <String, dynamic> {}; 
                                            final user = users[_userId(application)];
                                            return DataRow(cells: [
                                              DataCell(Text(user?['name']?.toString() ?? 'Unknown student')),
                                              DataCell(Text(user?['email']?.toString() ?? '—')),
                                              DataCell(Text(data['title']?.toString() ?? 'Scholarship')),
                                              DataCell(Text(_formatDate(data['appliedAt']))),
                                              DataCell(_StatusChip(status: data['status']?.toString() ?? 'pending')),
                                              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                                                IconButton(onPressed: () => _setStatus(context, application, 'approved'), icon: const Icon(Icons.check_circle_outline), tooltip: 'Approve'),
                                                IconButton(onPressed: () => _setStatus(context, application, 'rejected'), icon: const Icon(Icons.cancel_outlined), tooltip: 'Reject'),
                                                IconButton(onPressed: () => _delete(context, application), icon: const Icon(Icons.delete_outline), tooltip: 'Delete'),
                                              ])),
                                            ]);
                                          }).toList(),
                                        ),
                                      ),
                              ),
                      ),
                    ),
                  ]),
                ),
              );
            },
          );
        },
      );
}

String _userId(DocumentSnapshot<Map<String, dynamic>> application) => application.reference.parent.parent?.id ?? '';

String _formatDate(dynamic value) {
  if (value is Timestamp) {
    final date = value.toDate();
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
  return value?.toString() ?? '—';
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.application, required this.user, required this.onApprove, required this.onReject, required this.onDelete});

  final DocumentSnapshot<Map<String, dynamic>> application;
  final Map<String, dynamic>? user;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final data = application.data() ?? <String, dynamic>{};
    return AdminSurface(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [AdminAvatar(name: user?['name']?.toString() ?? ''), const SizedBox(width: 12), Expanded(child: Text(user?['name']?.toString() ?? 'Unknown student', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AdminPalette.heading, fontWeight: FontWeight.w700)))]),
          const SizedBox(height: 8),
          Text(user?['email']?.toString() ?? '—', style: const TextStyle(color: AdminPalette.body)),
          const SizedBox(height: 12),
          Text(data['title']?.toString() ?? 'Scholarship'),
          Text('Applied: ${_formatDate(data['appliedAt'])}'),
          const SizedBox(height: 12),
          Row(children: [
            _StatusChip(status: data['status']?.toString() ?? 'pending'),
            const Spacer(),
            IconButton(onPressed: onApprove, icon: const Icon(Icons.check_circle_outline), tooltip: 'Approve'),
            IconButton(onPressed: onReject, icon: const Icon(Icons.cancel_outlined), tooltip: 'Reject'),
            IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline), tooltip: 'Delete'),
          ]),
        ]),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final color = normalized == 'approved' ? Colors.green : normalized == 'rejected' ? Colors.red : Colors.orange;
    return Chip(avatar: Icon(normalized == 'approved' ? Icons.check : normalized == 'rejected' ? Icons.close : Icons.schedule, color: color, size: 18), label: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w700)), backgroundColor: color.withValues(alpha: .1), side: BorderSide.none, padding: const EdgeInsets.symmetric(horizontal: 8));
  }
}
