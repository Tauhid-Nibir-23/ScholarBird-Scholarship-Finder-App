import 'package:flutter/material.dart';
import 'profile_widgets.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: sbBackground,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Notifications',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: sbText,
            ),
          ),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: sbText),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: const Center(
          child: ProfileEmptyState(
            title: 'No notifications yet',
            message: 'You will see important updates and reminders here.',
            icon: Icons.notifications_none_outlined,
          ),
        ),
      );
}
