/// Coordinates the mentor profile picture: Supabase Storage upload
/// + Firestore mirror at `mentors/{mentorId}.photoUrl`.
///
/// Storage layout:
/// - bucket: `mentor-images`
/// - path:   `{mentorId}.jpg`  (one object per mentor; each upload overwrites)
///
/// Firestore layout:
/// - `mentors/{mentorId}.photoUrl` -> absolute public URL of the latest upload
///
/// The `mentors/{mentorId}.photoUrl` field is what [MentorCard] already
/// reads, so edits made through this service propagate live.
library;

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Handles upload + delete of a mentor's profile picture.
class MentorImageService {
  MentorImageService._();

  /// Shared singleton instance.
  static final MentorImageService instance = MentorImageService._();

  /// Name of the Supabase Storage bucket that holds mentor pictures.
  static const String bucketName = SupabaseConfig.mentorImagesBucket;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();
  SupabaseClient get _storage => Supabase.instance.client;

  /// Picks an image from the gallery, uploads it to Supabase, and writes
  /// the public URL to `mentors/{mentorId}.photoUrl`. Returns the new URL
  /// (or null if the user cancelled the picker).
  Future<String?> pickAndUploadFromGallery(String mentorId) async {
    return _pickAndUpload(mentorId, ImageSource.gallery);
  }

  /// Picks an image from the camera, uploads it to Supabase, and writes
  /// the public URL to `mentors/{mentorId}.photoUrl`. Returns the new URL
  /// (or null if the user cancelled).
  Future<String?> pickAndUploadFromCamera(String mentorId) async {
    return _pickAndUpload(mentorId, ImageSource.camera);
  }

  /// Removes the current mentor picture from both Supabase and Firestore.
  /// Safe to call when no image is uploaded.
  Future<void> removeMentorImage(String mentorId) async {
    try {
      await _storage.storage.from(bucketName).remove(['$mentorId.jpg']);
    } on StorageException catch (e) {
      // ignore: avoid_print
      print('[MentorImage] remove: status=${e.statusCode} msg=${e.message}');
      if (e.statusCode != '404' && !e.message.toLowerCase().contains('not found')) {
        rethrow;
      }
    }
    await _firestore.collection('mentors').doc(mentorId).set(
          {'photoUrl': null},
          SetOptions(merge: true),
        );
  }

  Future<String?> _pickAndUpload(String mentorId, ImageSource source) async {
    // ignore: avoid_print
    print('[MentorImage] pick: mentorId=$mentorId source=${source.name}');
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null) {
      // ignore: avoid_print
      print('[MentorImage] pick: cancelled');
      return null;
    }
    final bytes = await picked.readAsBytes();
    // ignore: avoid_print
    print('[MentorImage] pick: name=${picked.name} size=${bytes.length}');
    final url = await _uploadBytes(mentorId: mentorId, bytes: bytes);
    await _persistMentorPhotoUrl(mentorId, url);
    return url;
  }

  Future<String> _uploadBytes({
    required String mentorId,
    required Uint8List bytes,
  }) async {
    final path = '$mentorId.jpg';
    // ignore: avoid_print
    print('[Supabase] mentor upload → bucket=$bucketName path=$path '
        'keyPrefix=${SupabaseConfig.anonKey.substring(0, SupabaseConfig.anonKey.length < 12 ? SupabaseConfig.anonKey.length : 12)}...');
    try {
      await _storage.storage.from(bucketName).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
            ),
          );
    } on StorageException catch (e) {
      // ignore: avoid_print
      print('[Supabase] mentor upload failed: '
          'status=${e.statusCode} msg=${e.message}');
      throw StateError(_explainUploadError(e));
    }
    return _storage.storage.from(bucketName).getPublicUrl(path);
  }

  Future<void> _persistMentorPhotoUrl(String mentorId, String url) async {
    await _firestore.collection('mentors').doc(mentorId).set(
          {'photoUrl': url},
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
      return 'Permission denied uploading to "$bucketName". Verify the bucket '
          'is Public and that INSERT/UPDATE/DELETE policies exist for the '
          'anon role. If the key in .env starts with "sb_publishable_", '
          'replace it with the legacy "anon" JWT from '
          'Settings > API > Legacy API Keys.';
    }
    if (e.statusCode == '401' ||
        msg.contains('invalid api key') ||
        msg.contains('jwt')) {
      return 'Supabase rejected the API key. Use the legacy "anon" JWT '
          '(starts with "eyJhbGciOi...") from Settings > API > Legacy API '
          'Keys instead of the new "sb_publishable_..." key.';
    }
    return 'Upload failed: ${e.message}';
  }
}
