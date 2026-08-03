import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_ui.dart';

class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  Future<void> _updateUser(
      BuildContext context,
      DocumentSnapshot<Map<String, dynamic>> user,
      Map<String, dynamic> values) async {
    try {
      await user.reference.update(values);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update user.')));
      }
    }
  }

  Future<void> _deleteUser(
      BuildContext context, DocumentSnapshot<Map<String, dynamic>> user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Firestore user profile?'),
        content: const Text(
            'This deletes only the users collection document. The Firebase Authentication account is not deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete profile')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await user.reference.delete();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not delete Firestore profile.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load users.'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snapshot.data?.docs ?? [];
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Users',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text(
                        'Manage roles and access through Firestore user profiles.'),
                    const SizedBox(height: 28),
                    AdminSurface(
                      padding: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: users.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(32),
                                child: Center(child: Text('No users found.')))
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text('Name')),
                                    DataColumn(label: Text('Email')),
                                    DataColumn(label: Text('Role')),
                                    DataColumn(label: Text('Access')),
                                    DataColumn(label: Text('Actions')),
                                  ],
                                  rows: users.map((user) {
                                    final data = user.data();
                                    final isAdmin = data['role'] == 'admin';
                                    final isDisabled =
                                        data['isDisabled'] == true;
                                    return DataRow(cells: [
                                      DataCell(Row(children: [
                                        AdminAvatar(
                                            name:
                                                data['name']?.toString() ?? '',
                                            radius: 17),
                                        const SizedBox(width: 10),
                                        Text(
                                            data['name']?.toString() ??
                                                'Unnamed user',
                                            style: const TextStyle(
                                                color: AdminPalette.heading,
                                                fontWeight: FontWeight.w700))
                                      ])),
                                      DataCell(Text(
                                          data['email']?.toString() ?? '—')),
                                      DataCell(Chip(
                                          label: Text(
                                              isAdmin ? 'Admin' : 'User'))),
                                      DataCell(Chip(
                                          label: Text(isDisabled
                                              ? 'Disabled'
                                              : 'Active'))),
                                      DataCell(PopupMenuButton<String>(
                                        onSelected: (action) {
                                          if (action == 'admin') {
                                            _updateUser(context, user,
                                                {'role': 'admin'});
                                          }
                                          if (action == 'removeAdmin') {
                                            _updateUser(context, user,
                                                {'role': 'user'});
                                          }
                                          if (action == 'disable') {
                                            _updateUser(context, user,
                                                {'isDisabled': !isDisabled});
                                          }
                                          if (action == 'delete') {
                                            _deleteUser(context, user);
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          if (!isAdmin)
                                            const PopupMenuItem(
                                                value: 'admin',
                                                child: Text('Make Admin')),
                                          if (isAdmin)
                                            const PopupMenuItem(
                                                value: 'removeAdmin',
                                                child: Text('Remove Admin')),
                                          PopupMenuItem(
                                              value: 'disable',
                                              child: Text(isDisabled
                                                  ? 'Enable User'
                                                  : 'Disable User')),
                                          const PopupMenuItem(
                                              value: 'delete',
                                              child: Text(
                                                  'Delete Firestore profile')),
                                        ],
                                      )),
                                    ]);
                                  }).toList(),
                                ),
                              ),
                      ),
                    ),
                  ]),
            ),
          );
        },
      );
}
