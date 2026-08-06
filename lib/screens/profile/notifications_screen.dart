import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'profile_widgets.dart';

class UnreadNotificationBell extends StatelessWidget {
  const UnreadNotificationBell({required this.onPressed, super.key});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.notifications_none_outlined),
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notificationReads')
          .snapshots(),
      builder: (context, readsSnapshot) =>
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .limit(100)
            .snapshots(),
        builder: (context, notificationsSnapshot) {
          final readIds =
              readsSnapshot.data?.docs.map((doc) => doc.id).toSet() ??
                  <String>{};
          final unread = (notificationsSnapshot.data?.docs ?? const [])
              .where((doc) =>
                  doc.data()['status']?.toString().toLowerCase() == 'sent')
              .where((doc) => !readIds.contains(doc.id))
              .length;
          return IconButton(
            tooltip:
                unread == 0 ? 'Notifications' : '$unread unread notifications',
            onPressed: onPressed,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_none_outlined),
                if (unread > 0)
                  Positioned(
                    right: -9,
                    top: -8,
                    child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 18, minHeight: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: const BoxDecoration(
                          color: Color(0xFFE53935), shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: sbBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Notifications',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w600, color: sbText)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: sbText),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: user == null
          ? const Center(
              child: ProfileEmptyState(
                title: 'Sign in to view notifications',
                message: 'Your account notifications will appear here.',
                icon: Icons.notifications_none_outlined,
              ),
            )
          : _NotificationInbox(user: user),
    );
  }
}

class _NotificationInbox extends StatelessWidget {
  const _NotificationInbox({required this.user});
  final User user;

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, userSnapshot) {
          final profile =
              userSnapshot.data?.data() ?? const <String, dynamic>{};
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            // Client-side filtering keeps this feed compatible with Firestore
            // deployments that do not yet have a composite notification index.
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .limit(100)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Center(
                  child: ProfileEmptyState(
                    title: 'Could not load notifications',
                    message: 'Please try again in a moment.',
                    icon: Icons.error_outline,
                  ),
                );
              }
              final notifications = (snapshot.data?.docs ?? const [])
                  .where((doc) =>
                      _isSent(doc.data()) &&
                      _matchesAudience(doc.data(), profile, user))
                  .toList()
                ..sort((a, b) => _notificationDate(b.data())
                    .compareTo(_notificationDate(a.data())));
              if (notifications.isEmpty) {
                return const Center(
                  child: ProfileEmptyState(
                    title: 'No notifications yet',
                    message:
                        'You will see important updates and reminders here.',
                    icon: Icons.notifications_none_outlined,
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: notifications.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final notification = notifications[index];
                  return _NotificationCard(
                    data: notification.data(),
                    onOpen: () => _markRead(notification.id),
                  );
                },
              );
            },
          );
        },
      );

  Future<void> _markRead(String notificationId) => FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notificationReads')
          .doc(notificationId)
          .set({
        'readAt': FieldValue.serverTimestamp(),
      });
  bool _isSent(Map<String, dynamic> notification) =>
      notification['status']?.toString().toLowerCase() == 'sent';

  DateTime _notificationDate(Map<String, dynamic> notification) {
    final value = notification['sentAt'] ?? notification['createdAt'];
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.tryParse(value?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool _matchesAudience(
    Map<String, dynamic> notification,
    Map<String, dynamic> profile,
    User user,
  ) {
    final audience = notification['audience'];
    if (audience is! Map) {
      return true;
    }
    final type = audience['type']?.toString().toLowerCase() ?? 'all';
    final query = audience['query'] is Map
        ? Map<String, dynamic>.from(audience['query'] as Map)
        : const <String, dynamic>{};
    switch (type) {
      case 'premium':
        return profile['premium'] == true;
      case 'free':
        return profile['premium'] != true;
      case 'country':
        return _sameText(profile['country'], query['country']);
      case 'user':
        final target = query['userId']?.toString().trim().toLowerCase();
        return target != null &&
            target.isNotEmpty &&
            (target == user.uid.toLowerCase() ||
                target == (user.email ?? '').trim().toLowerCase());
      case 'all':
      default:
        return true;
    }
  }

  bool _sameText(Object? left, Object? right) =>
      left?.toString().trim().toLowerCase() ==
      right?.toString().trim().toLowerCase();
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.data, required this.onOpen});
  final Map<String, dynamic> data;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final sentAt = data['sentAt'];
    final date = sentAt is Timestamp ? sentAt.toDate() : null;
    final imageUrl = data['imageUrl']?.toString().trim() ?? '';
    final body = data['body']?.toString() ?? '';
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      imageUrl,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _iconPreview(),
                    ),
                  )
                else
                  _iconPreview(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['title']?.toString() ?? 'Notification',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: sbText,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: sbText.withValues(alpha: 0.72)),
                        ),
                      ],
                      if (date != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _formatNotificationDate(date),
                          style: TextStyle(
                            fontSize: 12,
                            color: sbText.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  onOpen();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => NotificationDetailsScreen(data: data),
                    ),
                  );
                },
                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                label: const Text('View details'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconPreview() => const SizedBox(
        width: 72,
        height: 72,
        child: CircleAvatar(
          backgroundColor: Color(0xFFE8F3FF),
          child: Icon(Icons.notifications_outlined, color: Color(0xFF1769AA)),
        ),
      );
}

class NotificationDetailsScreen extends StatelessWidget {
  const NotificationDetailsScreen({required this.data, super.key});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final sentAt = data['sentAt'];
    final date = sentAt is Timestamp ? sentAt.toDate() : null;
    final imageUrl = data['imageUrl']?.toString().trim() ?? '';
    final linkUrl = data['linkUrl']?.toString().trim() ?? '';
    return Scaffold(
      backgroundColor: sbBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: sbText),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Notification details',
            style: TextStyle(color: sbText, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                imageUrl,
                height: 220,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          if (imageUrl.isNotEmpty) const SizedBox(height: 18),
          Text(
            data['title']?.toString() ?? 'Notification',
            style: const TextStyle(
              color: sbText,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (date != null) ...[
            const SizedBox(height: 6),
            Text(_formatNotificationDate(date),
                style: TextStyle(color: sbText.withValues(alpha: 0.58))),
          ],
          const SizedBox(height: 16),
          SelectableText(
            data['body']?.toString() ?? '',
            style: const TextStyle(color: sbText, fontSize: 16, height: 1.5),
          ),
          if (linkUrl.isNotEmpty) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _openNotificationLink(context, linkUrl),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open details link'),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _openNotificationLink(BuildContext context, String rawUrl) async {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This notification link is invalid.')),
    );
    return;
  }
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
      context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open the notification link.')),
    );
  }
}

String _formatNotificationDate(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  return '${local.day}/${local.month}/${local.year} at $hour:${local.minute.toString().padLeft(2, '0')} ${local.hour >= 12 ? 'PM' : 'AM'}';
}
