/// Coordinates the admin profile picture: Supabase Storage upload +
/// Firestore mirror at `users/{uid}.adminImage`.
///
/// Storage layout:
/// - bucket: `admin-images`
/// - path:   `{uid}.jpg`  (one object per admin; each upload overwrites)
///
/// Firestore layout:
/// - `users/{uid}.adminImage` -> absolute public URL of the latest upload
///
/// Only the public URL is persisted in Firestore. The admin profile
/// photo is shown in the admin dashboard sidebar / AppBar.
library;

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Handles upload + delete of the signed-in admin's profile picture.
class AdminImageService {
  AdminImageService._();

  /// Shared singleton instance.
  static final AdminImageService instance = AdminImageService._();

  /// Name of the Supabase Storage bucket that holds admin pictures.
  static const String bucketName = SupabaseConfig.adminImagesBucket;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _picker = ImagePicker();
  SupabaseClient get _storage => Supabase.instance.client;

  /// Streams the current admin profile picture URL. `null` when no image
  /// has been uploaded (or the user is signed out).
  Stream<String?> streamAdminImage() {
    final user = _auth.currentUser;
    if (user == null) return Stream<String?>.value(null);
    return _firestore.collection('users').doc(user.uid).snapshots().map((snap) {
      final data = snap.data();
      final url = data == null ? null : (data['adminImage'] as String?);
      return (url == null || url.isEmpty) ? null : url;
    });
  }

  /// Picks an image from the gallery, uploads it to Supabase, and writes
  /// the public URL to `users/{uid}.adminImage`. Returns the new URL
  /// (or null if the user cancelled the picker).
  Future<String?> pickAndUploadFromGallery() => _pickAndUpload(ImageSource.gallery);

  /// Picks an image from the camera, uploads it to Supabase, and writes
  /// the public URL to `users/{uid}.adminImage`. Returns the new URL
  /// (or null if the user cancelled).
  Future<String?> pickAndUploadFromCamera() => _pickAndUpload(ImageSource.camera);

  /// Removes the current admin picture from both Supabase Storage and
  /// Firestore. Safe to call when no image is uploaded.
  Future<void> removeAdminImage() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated admin user available.');
    }
    try {
      await _storage.storage.from(bucketName).remove(['${user.uid}.jpg']);
    } on StorageException catch (e) {
      if (e.statusCode != '404' &&
          !e.message.toLowerCase().contains('not found')) {
        rethrow;
      }
    }
    await _firestore
        .collection('users')
        .doc(user.uid)
        .set({'adminImage': null}, SetOptions(merge: true));
  }

  Future<String?> _pickAndUpload(ImageSource source) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated admin user available for upload.');
    }
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final url = await _uploadBytes(userUid: user.uid, bytes: bytes);
    await _persistAdminImageUrl(user.uid, url);
    return url;
  }

  Future<String> _uploadBytes({
    required String userUid,
    required Uint8List bytes,
  }) async {
    final path = '$userUid.jpg';
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

  Future<void> _persistAdminImageUrl(String uid, String url) async {
    await _firestore.collection('users').doc(uid).set(
          {'adminImage': url},
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
