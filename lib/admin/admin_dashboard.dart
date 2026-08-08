import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/admin_image_service.dart';
import 'admin_ui.dart';
import 'activity_logs_page.dart';
import 'analytics_page.dart';
import 'application_page.dart';
import 'dashboard_page.dart';
import 'mentor_admin_screen.dart';
import 'mentor_management_screen.dart';
import 'notifications_page.dart';
import 'scholarship_page.dart';
import 'settings_page.dart';
import 'users_page.dart';
import 'widgets/admin_image_picker.dart';

/// Root admin panel shell with grouped navigation, responsive sidebar
/// and animated transitions.
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;

  // Two logical groups: primary workflow and secondary/admin utilities.
  static const _primaryItems = <_AdminDestination>[
    _AdminDestination(
      'Dashboard',
      Icons.space_dashboard_outlined,
      Icons.space_dashboard,
    ),
    _AdminDestination(
      'Scholarships',
      Icons.school_outlined,
      Icons.school,
    ),
    _AdminDestination('Users', Icons.people_outline, Icons.people),
    _AdminDestination(
      'Reference Points',
      Icons.person_outline,
      Icons.person,
    ),
    _AdminDestination(
      'Mentor Marketplace',
      Icons.workspace_premium_outlined,
      Icons.workspace_premium,
    ),
    _AdminDestination(
      'Applications',
      Icons.description_outlined,
      Icons.description,
    ),
  ];

  static const _secondaryItems = <_AdminDestination>[
    _AdminDestination(
      'Notifications',
      Icons.notifications_outlined,
      Icons.notifications,
    ),
    _AdminDestination(
      'Analytics',
      Icons.insights_outlined,
      Icons.insights,
    ),
    _AdminDestination(
      'Activity Logs',
      Icons.history_toggle_off_outlined,
      Icons.history_toggle_off,
    ),
    _AdminDestination(
      'Settings',
      Icons.settings_outlined,
      Icons.settings,
    ),
  ];

  // Flat list used for the AppBar title lookups.
  List<_AdminDestination> get _allItems =>
      [..._primaryItems, ..._secondaryItems];

  List<Widget> get _pages => [
        DashboardPage(onNavigate: _select),
        ScholarshipPage(),
        UsersPage(),
        MentorAdminScreen(),
        MentorManagementScreen(),
        ApplicationPage(),
        NotificationsPage(),
        AnalyticsPage(),
        ActivityLogsPage(),
        SettingsPage(),
      ];

  // Index in the flat `_pages` list.
  void _select(int flatIndex) => setState(() {
        _selectedIndex = flatIndex;
      });

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not sign out. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final currentLabel = _allItems[_selectedIndex].label;

    return Theme(
      data: AdminTheme.data(context),
      child: Scaffold(
        drawer: isWide
            ? null
            : Drawer(
                child: _Sidebar(
                  primaryItems: _primaryItems,
                  secondaryItems: _secondaryItems,
                  selectedIndex: _selectedIndex,
                  onSelected: _select,
                  onLogout: _logout,
                  closeOnSelect: true,
                ),
              ),
        appBar: AppBar(
          title: Text(currentLabel),
          actions: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none),
              tooltip: 'Notifications',
            ),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _AdminProfileButton(),
            ),
          ],
        ),
        body: Row(
          children: [
            if (isWide)
              SizedBox(
                width: 260,
                child: _Sidebar(
                  primaryItems: _primaryItems,
                  secondaryItems: _secondaryItems,
                  selectedIndex: _selectedIndex,
                  onSelected: _select,
                  onLogout: _logout,
                  closeOnSelect: false,
                ),
              ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: KeyedSubtree(
                  key: ValueKey(_selectedIndex),
                  child: _pages[_selectedIndex],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.primaryItems,
    required this.secondaryItems,
    required this.selectedIndex,
    required this.onSelected,
    required this.onLogout,
    required this.closeOnSelect,
  });

  final List<_AdminDestination> primaryItems;
  final List<_AdminDestination> secondaryItems;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onLogout;
  final bool closeOnSelect;

  int _flatFor(int groupIndex, int index, {required bool primary}) {
    if (primary) return index;
    return primaryItems.length + index;
  }

  @override
  Widget build(BuildContext context) => Material(
        color: AdminPalette.background,
        child: SafeArea(
          child: Column(
            children: [
              // Ã¢â€â‚¬Ã¢â€â‚¬ Brand header Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Row(children: [
                  Image.asset(
                    'assets/images/Logo_ScholarBird.png',
                    height: 36,
                    width: 36,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 12),
                  const Text('ScholarBird',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: AdminPalette.heading,
                      )),
                ]),
              ),
              const Divider(height: 1),
              // Ã¢â€â‚¬Ã¢â€â‚¬ Grouped nav Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
              Expanded(
                child: ListView(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  children: [
                    _NavGroup(
                      label: 'WORKSPACE',
                      children: [
                        for (var i = 0; i < primaryItems.length; i++)
                          _NavTile(
                            item: primaryItems[i],
                            selected:
                                selectedIndex == _flatFor(0, i, primary: true),
                            onTap: () {
                              onSelected(_flatFor(0, i, primary: true));
                              if (closeOnSelect) Navigator.of(context).pop();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _NavGroup(
                      label: 'SYSTEM',
                      children: [
                        for (var i = 0; i < secondaryItems.length; i++)
                          _NavTile(
                            item: secondaryItems[i],
                            selected:
                                selectedIndex == _flatFor(0, i, primary: false),
                            onTap: () {
                              onSelected(_flatFor(0, i, primary: false));
                              if (closeOnSelect) Navigator.of(context).pop();
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminPalette.primaryDark,
                      side: const BorderSide(color: AdminPalette.primary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _NavGroup extends StatelessWidget {
  const _NavGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: AdminPalette.body,
              ),
            ),
          ),
          ...children,
        ],
      );
}

class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _AdminDestination item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: widget.selected
                ? AdminPalette.primary.withValues(alpha: 0.12)
                : (_hovered
                    ? AdminPalette.primary.withValues(alpha: 0.06)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: Icon(
              widget.selected ? widget.item.selectedIcon : widget.item.icon,
              color:
                  widget.selected ? AdminPalette.primary : AdminPalette.heading,
            ),
            title: Text(
              widget.item.label,
              style: TextStyle(
                color: widget.selected
                    ? AdminPalette.primary
                    : AdminPalette.heading,
                fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            onTap: widget.onTap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminDestination {
  const _AdminDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Live admin avatar in the AppBar. Streams the URL from
/// [AdminImageService] and opens a dialog with the reusable
/// [AdminImagePicker] when tapped.
class _AdminProfileButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? user?.email ?? 'Admin';
    final initials =
        displayName.isEmpty ? 'A' : displayName.characters.first.toUpperCase();

    return StreamBuilder<String?>(
      stream: AdminImageService.instance.streamAdminImage(),
      builder: (context, snapshot) {
        final url = snapshot.data;
        final hasPhoto = url != null && url.isNotEmpty;
        return Tooltip(
          message: 'Edit profile photo',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _openProfileDialog(context, url, initials),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AdminPalette.primary.withValues(alpha: 0.6),
                  width: 1.5,
                ),
              ),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: AdminPalette.primary.withValues(alpha: 0.12),
                foregroundImage: hasPhoto ? NetworkImage(url) : null,
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AdminPalette.primary,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openProfileDialog(
    BuildContext context,
    String? photoUrl,
    String initials,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Admin profile photo',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AdminPalette.heading,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Used across the admin panel.',
                style: TextStyle(
                  fontSize: 12,
                  color: AdminPalette.body,
                ),
              ),
              const SizedBox(height: 20),
              AdminImagePicker(
                photoUrl: photoUrl,
                title: 'Admin profile photo',
                subtitle: 'Recommended: 512x512 square',
                fallbackLabel: initials,
                shape: AdminImagePickerShape.circle,
                size: 160,
                onUploadFromGallery: () async {
                  final newUrl = await AdminImageService.instance
                      .pickAndUploadFromGallery();
                  return newUrl;
                },
                onUploadFromCamera: () async {
                  final newUrl = await AdminImageService.instance
                      .pickAndUploadFromCamera();
                  return newUrl;
                },
                onRemove: () async {
                  await AdminImageService.instance.removeAdminImage();
                },
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
