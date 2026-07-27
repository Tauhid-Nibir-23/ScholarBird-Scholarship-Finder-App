import 'package:flutter/material.dart';

import 'admin_ui.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Settings', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Dashboard settings will be available here in a future update.'),
            const SizedBox(height: 28),
            AdminSurface(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.settings_outlined, size: 42, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('Settings placeholder', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text('No preferences are saved and no user-facing behavior can be changed from this page yet.'),
                ]),
              ),
            ),
          ]),
        ),
      );
}
