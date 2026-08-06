/// Admin Activity Logs page.
///
/// Streams the `activity_logs` collection from Firestore (when present) and
/// surfaces a clean list of recent admin actions. The page is read-only:
/// entries are written by the Phase A/B admin actions, the Phase C admin
/// profile/scholarship flows, and (future) background jobs.
///
/// The widget renders gracefully even when no logs exist yet, so it can
/// ship alongside Phase C without requiring an existing log collection.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_ui.dart';
import 'widgets/admin_empty_state.dart';
import 'widgets/admin_section.dart';

class ActivityLogsPage extends StatelessWidget {
  const ActivityLogsPage({super.key});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AdminPageHeader(
                title: 'Activity logs',
                subtitle:
                    'Recent admin actions and system events, streamed from Firestore.',
              ),
              const SizedBox(height: 24),
              AdminSection(
                title: 'Recent activity',
                icon: Icons.history_toggle_off_outlined,
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('activity_logs')
                      .orderBy('createdAt', descending: true)
                      .limit(100)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Could not load activity logs: ${snapshot.error}',
                          style: const TextStyle(color: Color(0xFFDC2626)),
                        ),
                      );
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final docs = snapshot.data?.docs ?? const [];
                    if (docs.isEmpty) {
                      return const AdminEmptyState(
                        icon: Icons.notes_outlined,
                        title: 'No activity logs yet',
                        message:
                            'Admin actions will appear here as soon as the activity_logs collection receives its first entry.',
                      );
                    }
                    return Column(
                      children: [
                        for (final doc in docs)
                          _ActivityLogTile(data: doc.data(), id: doc.id),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
}

class _ActivityLogTile extends StatelessWidget {
  const _ActivityLogTile({required this.data, required this.id});

  final Map<String, dynamic> data;
  final String id;

  @override
  Widget build(BuildContext context) {
    final action = data['action']?.toString() ?? 'Unknown action';
    final actor = data['actor']?.toString() ?? data['adminEmail']?.toString() ?? 'Unknown admin';
    final target = data['target']?.toString();
    final detail = data['detail']?.toString();
    final createdAt = data['createdAt'];
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AdminPalette.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.bolt_outlined,
              color: AdminPalette.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AdminPalette.heading,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    'by $actor',
                    if (target != null && target.isNotEmpty) 'on $target',
                  ].join(' '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminPalette.body,
                  ),
                ),
                if (detail != null && detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminPalette.body,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatTimestamp(createdAt),
            style: const TextStyle(
              fontSize: 11,
              color: AdminPalette.body,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate();
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}';
    }
    return '—';
  }
}
