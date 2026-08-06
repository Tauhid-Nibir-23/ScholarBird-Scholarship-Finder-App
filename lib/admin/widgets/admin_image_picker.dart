/// Generic image picker used everywhere the admin uploads a photo
/// (mentor portraits, scholarship banners, admin profile).
///
/// Mirrors the existing `MentorImageService` / `ProfileImageService`
/// pattern: actual bytes go to Supabase Storage, only the public URL
/// is persisted in Firestore.
///
/// The widget exposes a `value` URL plus an `onChanged` callback so the
/// owning form (e.g. `MentorFormScreen`, `AddScholarshipPage`) decides
/// where to save the URL.
library;

import 'package:flutter/material.dart';

import '../admin_ui.dart';

/// Async function that picks + uploads a photo and returns the new
/// URL (or `null` when the user cancelled).
typedef PickUploader = Future<String?> Function();

/// Async function that removes the current photo.
typedef PhotoRemover = Future<void> Function();

/// Two visual variants are supported so the same widget works for
/// square banners and circular avatars.
enum AdminImagePickerShape { circle, rounded }

/// Reusable image-picker card / avatar.
class AdminImagePicker extends StatelessWidget {
  const AdminImagePicker({
    super.key,
    required this.photoUrl,
    required this.onUploadFromGallery,
    required this.onUploadFromCamera,
    this.onRemove,
    this.title = 'Photo',
    this.subtitle,
    this.fallbackLabel = '?',
    this.shape = AdminImagePickerShape.circle,
    this.size = 120,
    this.borderRadius,
    this.aspectRatio,
  });

  /// Current public URL. Empty string / null means no photo uploaded.
  final String? photoUrl;

  /// Callback that uploads from the gallery and returns the new URL.
  final PickUploader onUploadFromGallery;

  /// Callback that uploads from the camera and returns the new URL.
  final PickUploader onUploadFromCamera;

  /// Optional callback that removes the current photo. When null, the
  /// "Remove" option is hidden.
  final PhotoRemover? onRemove;

  /// Header shown in the picker bottom sheet.
  final String title;

  /// Subheader shown beneath the title (e.g. "Recommended: 1600x900").
  final String? subtitle;

  /// Letter shown when no photo is uploaded.
  final String fallbackLabel;

  /// Visual shape. `rounded` is used for banner previews.
  final AdminImagePickerShape shape;

  /// Diameter for the circle, width for the rounded preview.
  final double size;

  /// Override the rounded preview's border radius.
  final double? borderRadius;

  /// Force an aspect ratio on the rounded preview (e.g. 16/9).
  final double? aspectRatio;

  bool get _hasPhoto => photoUrl != null && photoUrl!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _hasPhoto;
    final radius = shape == AdminImagePickerShape.circle
        ? size / 2
        : (borderRadius ?? 16);

    final preview = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: shape == AdminImagePickerShape.circle ? size : null,
      height: shape == AdminImagePickerShape.circle ? size : null,
      decoration: BoxDecoration(
        color: AdminPalette.primary.withValues(alpha: 0.12),
        shape: shape == AdminImagePickerShape.circle
            ? BoxShape.circle
            : BoxShape.rectangle,
        borderRadius: shape == AdminImagePickerShape.circle
            ? null
            : BorderRadius.circular(radius),
      ),
      child: hasPhoto
          ? ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                width: shape == AdminImagePickerShape.circle ? size : null,
                height: shape == AdminImagePickerShape.circle ? size : null,
                errorBuilder: (_, __, ___) => _placeholder(context, radius),
                loadingBuilder: (ctx, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
              ),
            )
          : _placeholder(context, radius),
    );

    final wrapped = shape == AdminImagePickerShape.circle
        ? Center(child: preview)
        : AspectRatio(
            aspectRatio: aspectRatio ?? 16 / 9,
            child: preview,
          );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Stack(
        alignment: Alignment.center,
        children: [
          wrapped,
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: shape == AdminImagePickerShape.circle
                    ? const CircleBorder()
                    : RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(radius),
                      ),
                onTap: () => _pickSource(context),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AdminPalette.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        hasPhoto ? Icons.edit : Icons.add_a_photo_outlined,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context, double radius) {
    final icon = shape == AdminImagePickerShape.circle
        ? Icons.image_outlined
        : Icons.add_photo_alternate_outlined;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: AdminPalette.primary),
          if (shape == AdminImagePickerShape.rounded) ...[
            const SizedBox(height: 6),
            Text(
              fallbackLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AdminPalette.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickSource(BuildContext context) async {
    final source = await showModalBottomSheet<_PickerSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: [
                  const Icon(Icons.image_outlined, color: AdminPalette.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AdminPalette.heading,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminPalette.body,
                    ),
                  ),
                ),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(ctx).pop(_PickerSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(ctx).pop(_PickerSource.camera),
            ),
            if (_hasPhoto && onRemove != null)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFDC2626),
                ),
                title: const Text(
                  'Remove current photo',
                  style: TextStyle(color: Color(0xFFDC2626)),
                ),
                onTap: () => Navigator.of(ctx).pop(_PickerSource.remove),
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (source) {
        case _PickerSource.remove:
          await onRemove!();
          messenger.showSnackBar(
            const SnackBar(content: Text('Photo removed')),
          );
          break;
        case _PickerSource.gallery:
          final url = await onUploadFromGallery();
          if (url != null) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Photo uploaded')),
            );
          }
          break;
        case _PickerSource.camera:
          final url = await onUploadFromCamera();
          if (url != null) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Photo uploaded')),
            );
          }
          break;
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

enum _PickerSource { gallery, camera, remove }
