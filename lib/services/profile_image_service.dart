/// Coordinates the user's profile picture: Supabase Storage upload
/// + Firestore mirror at `users/{uid}.profileImage`.
///
/// Storage layout:
/// - bucket: `profile-images`
/// - path:   `{uid}.jpg`  (one object per user; each upload overwrites)
///
/// Firestore layout:
/// - `users/{uid}.profileImage` -> absolute public URL of the latest upload
///
/// The `users/{uid}.profileImage` field is what every UI surface
/// (drawer, profile, home greeting) should read so the photo updates
/// live across the app.
library;

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Handles upload + delete of the signed-in user's profile picture.
class ProfileImageService {
  ProfileImageService._();

  /// Shared singleton instance.
  static final ProfileImageService instance = ProfileImageService._();

  /// Name of the Supabase Storage bucket that holds profile pictures.
  static const String bucketName = SupabaseConfig.profileImagesBucket;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _picker = ImagePicker();
  SupabaseClient get _storage => Supabase.instance.client;

  /// Returns a stream of the current profile picture URL. `null` when no
  /// image has been uploaded (or the user is signed out).
  Stream<String?> streamProfileImage() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream<String?>.value(null);
    }
    return _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .map((snap) {
      final data = snap.data();
      // Read both the canonical key and the legacy one so existing users
      // who uploaded via the edit-profile screen still see their photo.
      final url = data == null
          ? null
          : (data['profileImage'] as String?) ??
              (data['photoUrl'] as String?);
      return (url == null || url.isEmpty) ? null : url;
    });
  }

  /// Picks an image from the gallery, uploads it to Supabase, and writes
  /// the public URL to `users/{uid}.profileImage`. Returns the new URL
  /// (or null if the user cancelled the picker).
  Future<String?> pickAndUploadFromGallery() async {
    return _pickAndUpload(ImageSource.gallery);
  }

  /// Picks an image from the camera, uploads it to Supabase, and writes
  /// the public URL to `users/{uid}.profileImage`. Returns the new URL
  /// (or null if the user cancelled the picker / camera).
  Future<String?> pickAndUploadFromCamera() async {
    return _pickAndUpload(ImageSource.camera);
  }

  /// Removes the current profile picture from both Supabase Storage and
  /// Firestore. Safe to call when no image is uploaded.
  Future<void> removeProfileImage() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user available.');
    }
    try {
      await _storage.storage.from(bucketName).remove(['${user.uid}.jpg']);
    } on StorageException catch (e) {
      // A missing file is fine — only surface *real* errors.
      // ignore: avoid_print
      print('[ProfileImage] remove: status=${e.statusCode} msg=${e.message}');
      if (e.statusCode != '404' && !e.message.toLowerCase().contains('not found')) {
        rethrow;
      }
    }
    await _firestore.collection('users').doc(user.uid).set(
      {
        'profileImage': null,
        'photoUrl': null,
      },
      SetOptions(merge: true),
    );
  }

  Future<String?> _pickAndUpload(ImageSource source) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user available for upload.');
    }
    // ignore: avoid_print
    print('[ProfileImage] pick: source=${source.name}');
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 800,
      maxHeight: 800,
    );
    if (picked == null) {
      // ignore: avoid_print
      print('[ProfileImage] pick: cancelled');
      return null;
    }
    final bytes = await picked.readAsBytes();
    // ignore: avoid_print
    print('[ProfileImage] pick: name=${picked.name} size=${bytes.length}');
    final url = await _uploadBytes(userUid: user.uid, bytes: bytes);
    await _persistProfileImageUrl(user.uid, url);
    return url;
  }

  /// Uploads [bytes] to Supabase and returns its public URL with a cache
  /// busting query string so the new image appears immediately across the
  /// app (Supabase caches by URL).
  Future<String> _uploadBytes({
    required String userUid,
    required Uint8List bytes,
  }) async {
    final path = '$userUid.jpg';
    // ignore: avoid_print
    print('[Supabase] profile upload → bucket=$bucketName path=$path '
        'keyPrefix=${SupabaseConfig.anonKey.substring(0, SupabaseConfig.anonKey.length < 12 ? SupabaseConfig.anonKey.length : 12)}...');
    try {
      await _storage.storage.from(bucketName).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
    } on StorageException catch (e) {
      // ignore: avoid_print
      print('[Supabase] profile upload failed: '
          'status=${e.statusCode} msg=${e.message}');
      throw StateError(_explainUploadError(e));
    }
    final baseUrl = _storage.storage.from(bucketName).getPublicUrl(path);
    // Append a timestamp query string to bust any HTTP/CDN cache so the
    // new photo shows up everywhere immediately after upload.
    return '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Writes the public URL to Firestore so every UI surface rebuilds.
  Future<void> _persistProfileImageUrl(String uid, String url) async {
    await _firestore.collection('users').doc(uid).set(
          {
            'profileImage': url,
            // Mirror to the legacy key so the existing profile screen /
            // drawer photoUrl fallback path keeps working.
            'photoUrl': url,
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
