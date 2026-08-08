/// Coordinates the **Reference Point** portrait: Supabase Storage upload
/// + Firestore mirror at `reference_points/{entryId}.photoUrl`.
///
/// Reference Points store professors, researchers, labs and universities.
/// Their portraits live in the `mentor-images` Supabase bucket under a
/// `reference-points/` prefix so they are clearly separated from any
/// marketplace avatars stored under `mentors-marketplace/`.
///
/// Storage layout:
/// - bucket: `mentor-images`
/// - path:   `reference-points/{entryId}.jpg`
///   (one object per reference entry; each upload overwrites)
///
/// Firestore layout:
/// - `reference_points/{entryId}.photoUrl` -> absolute public URL of the
///   latest upload
///
/// The `reference_points/{entryId}.photoUrl` field is what `MentorCard`
/// already reads, so edits made through this service propagate live.
library;

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firestore_collections.dart';
import 'supabase_config.dart';

/// Handles upload + delete of a Reference Point's portrait.
class MentorImageService {
  MentorImageService._();

  /// Shared singleton instance.
  static final MentorImageService instance = MentorImageService._();

  /// Name of the Supabase Storage bucket that holds Reference Point
  /// portraits and Marketplace avatars.
  static const String bucketName = SupabaseConfig.mentorImagesBucket;

  /// Storage prefix shared by every Reference Point portrait.
  /// Mentor Marketplace avatars must use a different prefix (e.g.
  /// `mentors-marketplace/`) so the two image namespaces cannot collide.
  static const String referencePointsPrefix = 'reference-points';

  /// Storage prefix for Mentor Marketplace avatars. Kept distinct from
  /// [referencePointsPrefix] so the two namespaces never share object names.
  static const String marketplacePrefix = 'mentors-marketplace';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();
  SupabaseClient get _storage => Supabase.instance.client;

  /// Picks an image from the gallery, uploads it to Supabase, and writes
  /// the public URL to `reference_points/{entryId}.photoUrl`. Returns the
  /// new URL (or null if the user cancelled the picker).
  Future<String?> pickAndUploadFromGallery(String mentorId) async {
    return _pickAndUpload(mentorId, ImageSource.gallery);
  }

  /// Picks an image from the camera, uploads it to Supabase, and writes
  /// the public URL to `reference_points/{entryId}.photoUrl`. Returns the
  /// new URL (or null if the user cancelled).
  Future<String?> pickAndUploadFromCamera(String mentorId) async {
    return _pickAndUpload(mentorId, ImageSource.camera);
  }

  /// Removes the current Reference Point portrait from both Supabase and
  /// Firestore. Safe to call when no image is uploaded.
  Future<void> removeMentorImage(String mentorId) async {
    final path = _objectPath(mentorId);
    try {
      await _storage.storage.from(bucketName).remove([path]);
    } on StorageException catch (e) {
      // ignore: avoid_print
      print('[MentorImage] remove: path=$path status=${e.statusCode} '
          'msg=${e.message}');
      if (e.statusCode != '404' &&
          !e.message.toLowerCase().contains('not found')) {
        rethrow;
      }
    }
    await _firestore.collection(kCollectionReferencePoints).doc(mentorId).set(
      {'photoUrl': null},
      SetOptions(merge: true),
    );
  }

  /// Picks a Mentor Marketplace portrait from the gallery, uploads it to
  /// Supabase under `mentors-marketplace/{mentorId}.jpg`, and writes the
  /// public URL to `mentors_marketplace/{mentorId}.profilePhoto`. Returns
  /// the new URL (or null if the user cancelled the picker).
  ///
  /// [mentorId] must be a stable identifier — for new mentors the caller
  /// should generate one with `FirebaseFirestore.instance.collection(...).doc().id`
  /// before the first upload so the URL is stable across edits.
  Future<String?> pickAndUploadMarketplacePortrait(
    String mentorId, {
    ImageSource source = ImageSource.gallery,
  }) async {
    return _pickAndUploadMarketplace(mentorId, source);
  }

  /// Removes the current Mentor Marketplace portrait from both Supabase and
  /// the `mentors_marketplace` Firestore document. Safe to call when no
  /// image has been uploaded yet.
  Future<void> removeMarketplacePortrait(String mentorId) async {
    final path = _marketplaceObjectPath(mentorId);
    try {
      await _storage.storage.from(bucketName).remove([path]);
    } on StorageException catch (e) {
      // ignore: avoid_print
      print(
          '[MentorImage] marketplace remove: path=$path status=${e.statusCode} '
          'msg=${e.message}');
      if (e.statusCode != '404' &&
          !e.message.toLowerCase().contains('not found')) {
        rethrow;
      }
    }
    await _firestore
        .collection(kCollectionMentorsMarketplace)
        .doc(mentorId)
        .set({'profilePhoto': null}, SetOptions(merge: true));
  }

  Future<String?> _pickAndUploadMarketplace(
    String mentorId,
    ImageSource source,
  ) async {
    // ignore: avoid_print
    print('[MentorImage] marketplace pick: mentorId=$mentorId '
        'source=${source.name}');
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null) {
      // ignore: avoid_print
      print('[MentorImage] marketplace pick: cancelled');
      return null;
    }
    final bytes = await picked.readAsBytes();
    // ignore: avoid_print
    print('[MentorImage] marketplace pick: name=${picked.name} '
        'size=${bytes.length}');
    final url = await _uploadMarketplaceBytes(mentorId: mentorId, bytes: bytes);
    await _persistMarketplacePhotoUrl(mentorId, url);
    return url;
  }

  Future<String> _uploadMarketplaceBytes({
    required String mentorId,
    required Uint8List bytes,
  }) async {
    final path = _marketplaceObjectPath(mentorId);
    // ignore: avoid_print
    print('[Supabase] marketplace upload → bucket=$bucketName path=$path');
    await _uploadOrReplace(
      path: path,
      bytes: bytes,
      label: 'marketplace',
    );
    return _publicUrlWithCacheBust(path);
  }

  Future<void> _persistMarketplacePhotoUrl(String mentorId, String url) async {
    await _firestore
        .collection(kCollectionMentorsMarketplace)
        .doc(mentorId)
        .set({'profilePhoto': url}, SetOptions(merge: true));
  }

  /// Canonical Supabase object path for a Mentor Marketplace portrait.
  String _marketplaceObjectPath(String mentorId) =>
      '$marketplacePrefix/$mentorId.jpg';

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
    await _persistReferencePhotoUrl(mentorId, url);
    return url;
  }

  Future<String> _uploadBytes({
    required String mentorId,
    required Uint8List bytes,
  }) async {
    final path = _objectPath(mentorId);
    // ignore: avoid_print
    print('[Supabase] reference upload → bucket=$bucketName path=$path '
        'keyPrefix=${SupabaseConfig.anonKey.substring(0, SupabaseConfig.anonKey.length < 12 ? SupabaseConfig.anonKey.length : 12)}...');
    await _uploadOrReplace(
      path: path,
      bytes: bytes,
      label: 'reference',
    );
    return _publicUrlWithCacheBust(path);
  }

  /// Returns the Supabase public URL for [path] with a `?v=...`
  /// cache-buster so the CDN and Flutter's `Image.network` do not keep
  /// serving the previous version after an overwrite.
  String _publicUrlWithCacheBust(String path) {
    final base = _storage.storage.from(bucketName).getPublicUrl(path);
    final separator = base.contains('?') ? '&' : '?';
    return '$base${separator}v=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Uploads [bytes] to [path] inside the mentor-images bucket. When the
  /// object already exists the call is automatically retried with
  /// `updateBinary` so re-uploading the same mentor's portrait silently
  /// overwrites the previous file instead of throwing "already exists".
  ///
  /// [label] is just a tag for the console logs (e.g. "marketplace" or
  /// "reference") so the trace makes it obvious which namespace failed.
  Future<void> _uploadOrReplace({
    required String path,
    required Uint8List bytes,
    required String label,
  }) async {
    final fileOptions = const FileOptions(contentType: 'image/jpeg');
    try {
      await _storage.storage
          .from(bucketName)
          .uploadBinary(path, bytes, fileOptions: fileOptions);
    } on StorageException catch (e) {
      final msg = e.message.toLowerCase();
      final isConflict = e.statusCode == '409' ||
          e.statusCode == '400' ||
          msg.contains('already exists') ||
          msg.contains('duplicate');
      if (!isConflict) {
        // ignore: avoid_print
        print('[Supabase] $label upload failed: '
            'status=${e.statusCode} msg=${e.message}');
        throw StateError(_explainUploadError(e));
      }
      // Object exists → overwrite it.
      // ignore: avoid_print
      print('[Supabase] $label upload conflict at path=$path, retrying '
          'with updateBinary');
      try {
        await _storage.storage
            .from(bucketName)
            .updateBinary(path, bytes, fileOptions: fileOptions);
      } on StorageException catch (e2) {
        // ignore: avoid_print
        print('[Supabase] $label updateBinary failed: '
            'status=${e2.statusCode} msg=${e2.message}');
        throw StateError(_explainUploadError(e2));
      }
    }
  }

  Future<void> _persistReferencePhotoUrl(String mentorId, String url) async {
    await _firestore.collection(kCollectionReferencePoints).doc(mentorId).set(
      {'photoUrl': url},
      SetOptions(merge: true),
    );
  }

  /// Canonical Supabase object path for a Reference Point portrait.
  String _objectPath(String mentorId) => '$referencePointsPrefix/$mentorId.jpg';

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
