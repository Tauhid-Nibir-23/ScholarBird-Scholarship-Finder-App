import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'admin_ui.dart';
import 'analytics_page.dart';
import 'application_page.dart';
import 'dashboard_page.dart';
import 'scholarship_page.dart';
import 'settings_page.dart';
import 'users_page.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;

  static const _items = <_AdminDestination>[
    _AdminDestination(
        'Dashboard', Icons.space_dashboard_outlined, Icons.space_dashboard),
    _AdminDestination('Scholarships', Icons.school_outlined, Icons.school),
    _AdminDestination(
        'Applications', Icons.description_outlined, Icons.description),
    _AdminDestination('Users', Icons.people_outline, Icons.people),
    _AdminDestination('Analytics', Icons.insights_outlined, Icons.insights),
    _AdminDestination('Settings', Icons.settings_outlined, Icons.settings),
  ];

  final _pages = const [
    DashboardPage(),
    ScholarshipPage(),
    ApplicationPage(),
    UsersPage(),
    AnalyticsPage(),
    SettingsPage(),
  ];

  void _select(int index) => setState(() => _selectedIndex = index);

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

    return Theme(
      data: AdminTheme.data(context),
      child: Scaffold(
        drawer: isWide
            ? null
            : Drawer(
                child: _Sidebar(
                  items: _items,
                  selectedIndex: _selectedIndex,
                  onSelected: _select,
                  onLogout: _logout,
                  closeOnSelect: true,
                ),
              ),
        appBar: AppBar(
          title: Text(_items[_selectedIndex].label),
          actions: [
            IconButton(
                onPressed: () {},
                icon: const Icon(Icons.notifications_none),
                tooltip: 'Notifications'),
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: CircleAvatar(child: Text('A')),
            ),
          ],
        ),
        body: Row(
          children: [
            if (isWide)
              SizedBox(
                width: 260,
                child: _Sidebar(
                  items: _items,
                  selectedIndex: _selectedIndex,
                  onSelected: _select,
                  onLogout: _logout,
                  closeOnSelect: false,
                ),
              ),
            Expanded(child: _pages[_selectedIndex]),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.onLogout,
    required this.closeOnSelect,
  });

  final List<_AdminDestination> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onLogout;
  final bool closeOnSelect;

  @override
  Widget build(BuildContext context) => Material(
        color: AdminPalette.background,
        child: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Row(children: [
                  Icon(Icons.school, size: 30, color: AdminPalette.primary),
                  SizedBox(width: 12),
                  Text('ScholarBird',
                      style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: AdminPalette.heading))
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isSelected = index == selectedIndex;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: ListTile(
                        leading: Icon(
                          isSelected ? item.selectedIcon : item.icon,
                        ),
                        title: Text(item.label),
                        selected: isSelected,
                        selectedTileColor:
                            AdminPalette.primary.withValues(alpha: 0.12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onTap: () {
                          onSelected(index);
                          if (closeOnSelect) Navigator.of(context).pop();
                        },
                      ),
                    );
                  },
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

class _AdminDestination {
  const _AdminDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
