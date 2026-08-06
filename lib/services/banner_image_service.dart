/// Coordinates scholarship banner images: Supabase Storage upload +
/// Firestore mirror at `scholarships/{scholarshipId}.bannerUrl`.
///
/// Storage layout:
/// - bucket: `scholarship-banners`
/// - path:   `{scholarshipId}.jpg`  (one object per scholarship; each
///            upload overwrites the previous file)
///
/// Firestore layout:
/// - `scholarships/{scholarshipId}.bannerUrl` -> absolute public URL of
///   the latest upload
///
/// Only the public URL is persisted in Firestore — binary image data
/// never lives in Firestore. The banner URL is consumed by the public
/// scholarship list/detail screens.
library;

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Handles upload + delete of scholarship banner images.
class BannerImageService {
  BannerImageService._();

  /// Shared singleton instance.
  static final BannerImageService instance = BannerImageService._();

  /// Name of the Supabase Storage bucket that holds scholarship banners.
  static const String bucketName = SupabaseConfig.scholarshipBannersBucket;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();
  SupabaseClient get _storage => Supabase.instance.client;

  /// Picks an image from the gallery, uploads it to Supabase, and writes
  /// the public URL to `scholarships/{scholarshipId}.bannerUrl`.
  /// Returns the new URL (or null if the user cancelled the picker).
  Future<String?> pickAndUploadFromGallery(String scholarshipId) {
    return _pickAndUpload(scholarshipId, ImageSource.gallery);
  }

  /// Picks an image from the camera, uploads it to Supabase, and writes
  /// the public URL to `scholarships/{scholarshipId}.bannerUrl`.
  /// Returns the new URL (or null if the user cancelled).
  Future<String?> pickAndUploadFromCamera(String scholarshipId) {
    return _pickAndUpload(scholarshipId, ImageSource.camera);
  }

  /// Removes the current banner from both Supabase Storage and Firestore.
  /// Safe to call when no banner is uploaded.
  Future<void> removeBannerImage(String scholarshipId) async {
    try {
      await _storage.storage.from(bucketName).remove(['$scholarshipId.jpg']);
    } on StorageException catch (e) {
      // A missing file is fine — only surface *real* errors.
      if (e.statusCode != '404' &&
          !e.message.toLowerCase().contains('not found')) {
        rethrow;
      }
    }
    await _firestore.collection('scholarships').doc(scholarshipId).set(
          {'bannerUrl': null},
          SetOptions(merge: true),
        );
  }

  Future<String?> _pickAndUpload(String scholarshipId, ImageSource source) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1600,
      maxHeight: 900,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final url = await _uploadBytes(scholarshipId: scholarshipId, bytes: bytes);
    await _persistBannerUrl(scholarshipId, url);
    return url;
  }

  /// Uploads [bytes] to Supabase and returns its public URL.
  Future<String> _uploadBytes({
    required String scholarshipId,
    required Uint8List bytes,
  }) async {
    final path = '$scholarshipId.jpg';
    try {
      await _storage.storage.from(bucketName).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
            ),
          );
    } on StorageException catch (e) {
      throw StateError(_explainUploadError(e));
    }
    return _storage.storage.from(bucketName).getPublicUrl(path);
  }

  /// Writes the public URL to Firestore so every UI surface rebuilds.
  Future<void> _persistBannerUrl(String scholarshipId, String url) async {
    await _firestore.collection('scholarships').doc(scholarshipId).set(
          {
            'bannerUrl': url,
            // Legacy keys kept in sync so existing scholarship detail
            // screens that look up `image` keep rendering.
            'image': url,
          },
          SetOptions(merge: true),
        );
  }

  String _explainUploadError(StorageException e) {
    final msg = e.message.toLowerCase();
    if (e.statusCode == '404' || msg.contains('bucket not found')) {
      return 'Supabase bucket "$bucketName" was not found. Create a public '
          'bucket with that name in the Supabase dashboard.';
    }
    if (e.statusCode == '403' || msg.contains('not allowed')) {
      return 'Permission denied uploading to "$bucketName". Verify the '
          'bucket is Public and that INSERT/UPDATE/DELETE policies exist '
          'for the anon role.';
    }
    if (e.statusCode == '401' ||
        msg.contains('invalid api key') ||
        msg.contains('jwt')) {
      return 'Supabase rejected the API key. Use the legacy "anon" JWT '
          '(starts with "eyJhbGciOi...") from Settings > API > Legacy API '
          'Keys.';
    }
    return 'Upload failed: ${e.message}';
  }
}
