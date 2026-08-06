/// Reusable circular avatar with photo upload / preview / remove.
///
/// This file is preserved as a thin wrapper around the new generic
/// [AdminImagePicker], so `MentorFormScreen` (which already calls
/// `AdminImageUpload(...)`) continues to compile without any change.
library;

import 'package:flutter/material.dart';

import '../../services/mentor_image_service.dart';
import 'admin_image_picker.dart';

class AdminImageUpload extends StatelessWidget {
  const AdminImageUpload({
    super.key,
    required this.mentorId,
    required this.photoUrl,
    required this.onChanged,
    required this.name,
    this.radius = 50,
  });

  /// Used to namespace the file in Supabase Storage.
  final String mentorId;

  /// Current public URL. Empty string → no photo uploaded.
  final String? photoUrl;

  /// Notified when the URL changes after upload or remove.
  final ValueChanged<String?> onChanged;

  /// Name whose first letter is rendered as initials when no photo
  /// is set yet. Helps admins see the avatar react when they type.
  final String name;

  final double radius;

  @override
  Widget build(BuildContext context) {
    return AdminImagePicker(
      photoUrl: photoUrl,
      title: 'Mentor portrait',
      subtitle: 'Recommended: 512x512 square photo',
      fallbackLabel: name.isEmpty
          ? '?'
          : name.characters.first.toUpperCase(),
      shape: AdminImagePickerShape.circle,
      size: radius * 2,
      onUploadFromGallery: () async {
        final url = await MentorImageService.instance
            .pickAndUploadFromGallery(mentorId);
        if (url != null) onChanged(url);
        return url;
      },
      onUploadFromCamera: () async {
        final url = await MentorImageService.instance
            .pickAndUploadFromCamera(mentorId);
        if (url != null) onChanged(url);
        return url;
      },
      onRemove: () async {
        await MentorImageService.instance.removeMentorImage(mentorId);
        onChanged(null);
      },
    );
  }
}