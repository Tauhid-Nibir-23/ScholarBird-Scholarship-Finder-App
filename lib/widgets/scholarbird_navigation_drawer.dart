/// Navigation drawer that routes between the main end-user screens.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/scholarbird_theme.dart';
import 'premium_guard.dart';

/// Displays account-aware navigation options and logout actions.
class ScholarBirdNavigationDrawer extends StatelessWidget {
  const ScholarBirdNavigationDrawer({
    required this.selectedIndex,
    required this.onTabSelected,
    required this.onSaved,
    required this.onMyApplications,
    required this.onNotifications,
    required this.onPremium,
    required this.onMentorHub,
    required this.onLogout,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onSaved;
  final VoidCallback onMyApplications;
  final VoidCallback onNotifications;
  final VoidCallback onPremium;
  final VoidCallback onMentorHub;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => NavigationDrawer(
        selectedIndex: _selectedDestinationIndex,
        onDestinationSelected: (index) {
          Navigator.of(context).pop();
          onTabSelected(switch (index) {
            0 => 0,
            1 => 1,
            2 => 2,
            3 => 3,
            _ => 4,
          });
        },
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        children: [
          _DrawerProfileHeader(onPremium: onPremium),
          _destination(Icons.home_outlined, 'Home'),
          _destination(Icons.school_outlined, 'All Scholarships'),
          _destination(Icons.auto_awesome_outlined, 'AI Advisor'),
          _destination(Icons.groups_outlined, 'Community'),
          _action(
              context, Icons.favorite_border, 'Saved Scholarships', onSaved),
          _action(context, Icons.assignment_outlined, 'My Applications',
              onMyApplications),
          _action(context, Icons.notifications_none_outlined, 'Notifications',
              onNotifications),
          _action(context, Icons.workspace_premium_outlined, 'Premium', onPremium),
          _action(context, Icons.school_outlined, 'Mentor Hub', onMentorHub),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 10),
            child: Divider(height: 1),
          ),
          _action(
              context,
              Icons.info_outline,
              'About ScholarBird',
              () => showAboutDialog(
                    context: context,
                    applicationName: 'ScholarBird',
                    applicationVersion: '1.0.0',
                    applicationLegalese: 'Fly Towards Your Future',
                  )),
          _action(context, Icons.logout, 'Logout', onLogout, destructive: true),
          const SizedBox(height: 16),
        ],
      );

  int? get _selectedDestinationIndex => switch (selectedIndex) {
        0 => 0,
        1 => 1,
        2 => 2,
        3 => 3,
        _ => null,
      };

  Widget _destination(IconData icon, String label) =>
      NavigationDrawerDestination(
          icon: Icon(icon), selectedIcon: Icon(icon), label: Text(label));

  Widget _action(BuildContext context, IconData icon, String label,
          VoidCallback action,
          {bool destructive = false}) =>
      ListTile(
        leading: Icon(icon,
            color: destructive ? Theme.of(context).colorScheme.error : null),
        title: Text(label,
            style: destructive
                ? TextStyle(color: Theme.of(context).colorScheme.error)
                : null),
        minLeadingWidth: 28,
        contentPadding: const EdgeInsets.symmetric(horizontal: 28),
        onTap: () {
          Navigator.of(context).pop();
          action();
        },
      );
}

class _DrawerProfileHeader extends StatelessWidget {
  const _DrawerProfileHeader({required this.onPremium});
  final VoidCallback onPremium;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        final name =
            (data['name'] ?? user.displayName ?? 'Scholar').toString().trim();
        final email = user.email ?? '';
        final photo =
            (data['photoUrl'] ?? data['profileImage'] ?? user.photoURL ?? '')
                .toString();
        // Read the local-demo + Firestore-backed subscription state from the
        // app-wide [SubscriptionProviderScope] so that an in-app activation
        // (e.g. via the local demo path) is reflected here immediately,
        // instead of waiting for Firestore to catch up.
        return ListenableBuilder(
          listenable: SubscriptionProviderScope.of(context),
          builder: (context, _) {
            final provider = SubscriptionProviderScope.of(context);
            final subscription = provider.subscription;
            return Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [
                  ScholarBirdColors.primary,
                  ScholarBirdColors.primaryDark
                ]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _ProfileAvatar(name: name, photoUrl: photo),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(name.isEmpty ? 'Scholar' : name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16)),
                            Text(email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: .82),
                                    fontSize: 12)),
                          ])),
                    ]),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .16),
                          borderRadius: BorderRadius.circular(12)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.workspace_premium_outlined,
                                  size: 18, color: Colors.white),
                              const SizedBox(width: 6),
                              Text(
                                  subscription.isPremium
                                      ? 'ScholarBird Premium'
                                      : 'ScholarBird',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                              if (subscription.isPremium) ...[
                                const Spacer(),
                                const _PremiumBadge()
                              ],
                            ]),
                            const SizedBox(height: 4),
                            Text(
                                'Current Plan: ${subscription.isPremium ? (subscription.plan ?? 'Premium') : 'Free'}',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: .84),
                                    fontSize: 12)),
                            const SizedBox(height: 8),
                            const Text('Fly Towards Your Future',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12)),
                            if (!subscription.isPremium)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    onPremium();
                                  },
                                  icon: const Icon(Icons.arrow_upward_rounded,
                                      size: 16),
                                  label: const Text('Upgrade Now'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(0, 36),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                  ),
                                ),
                              ),
                          ]),
                    ),
                  ]),
            );
          },
        );
      },
    );
  }
}

class _PremiumBadge extends StatelessWidget {
  const _PremiumBadge();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .22),
            borderRadius: BorderRadius.circular(10)),
        child: const Text('PREMIUM',
            style: TextStyle(
                color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
      );
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.name, required this.photoUrl});
  final String name;
  final String photoUrl;
  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: 25,
        backgroundColor: Colors.white.withValues(alpha: .24),
        foregroundImage: photoUrl.isEmpty ? null : NetworkImage(photoUrl),
        child: Text(name.isEmpty ? 'S' : name.substring(0, 1).toUpperCase(),
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18)),
      );
}
