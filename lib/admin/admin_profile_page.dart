/// Admin Profile page.
///
/// Shows the signed-in admin's photo (streamed from Supabase Storage via
/// `AdminImageService`) and lets them upload a new one or remove the
/// current photo. Display name and email are read-only — auth changes are
/// handled outside Phase C scope.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/admin_image_service.dart';
import 'admin_ui.dart';
import 'widgets/admin_image_picker.dart';
import 'widgets/admin_section.dart';

class AdminProfilePage extends StatelessWidget {
  const AdminProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? user?.email ?? 'Admin';
    final initials = displayName.isEmpty
        ? 'A'
        : displayName.characters.first.toUpperCase();
    final email = user?.email ?? '—';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AdminPageHeader(
              title: 'Admin profile',
              subtitle:
                  'Update the photo that represents you across the admin panel.',
            ),
            const SizedBox(height: 24),
            AdminSection(
              title: 'Profile photo',
              icon: Icons.account_circle_outlined,
              child: StreamBuilder<String?>(
                stream: AdminImageService.instance.streamAdminImage(),
                builder: (context, snapshot) {
                  final url = snapshot.data;
                  return Center(
                    child: AdminImagePicker(
                      photoUrl: url,
                      title: 'Admin profile photo',
                      subtitle: 'Recommended: 512×512 square photo',
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
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            AdminSection(
              title: 'Account',
              icon: Icons.badge_outlined,
              child: Column(
                children: [
                  _InfoRow(label: 'Name', value: displayName),
                  const Divider(height: 24),
                  _InfoRow(label: 'Email', value: email),
                  const Divider(height: 24),
                  _InfoRow(
                    label: 'Auth provider',
                    value: _providerLabel(user),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _providerLabel(User? user) {
    if (user == null) return '—';
    final providers = user.providerData.map((p) => p.providerId).toList();
    if (providers.isEmpty) return '—';
    return providers.join(', ');
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: const TextStyle(
                  color: AdminPalette.body,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: AdminPalette.heading,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      );
}