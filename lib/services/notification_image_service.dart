/// Uploads optional broadcast images to Supabase Storage.
library;

import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

class NotificationImageService {
  NotificationImageService._();

  static final NotificationImageService instance = NotificationImageService._();
  static const String bucketName = SupabaseConfig.notificationImagesBucket;

  final ImagePicker _picker = ImagePicker();
  SupabaseClient get _storage => Supabase.instance.client;

  Future<String?> pickAndUploadFromGallery() =>
      _pickAndUpload(ImageSource.gallery);
  Future<String?> pickAndUploadFromCamera() =>
      _pickAndUpload(ImageSource.camera);

  Future<String?> _pickAndUpload(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1600,
      maxHeight: 900,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    return _uploadBytes(bytes);
  }

  Future<String> _uploadBytes(Uint8List bytes) async {
    final path = 'broadcasts/${DateTime.now().microsecondsSinceEpoch}.jpg';
    try {
      await _storage.storage.from(bucketName).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
      return _storage.storage.from(bucketName).getPublicUrl(path);
    } on StorageException catch (error) {
      final message = error.message.toLowerCase();
      if (error.statusCode == '404' || message.contains('bucket not found')) {
        throw StateError('Supabase bucket "$bucketName" was not found.');
      }
      if (error.statusCode == '403' || message.contains('not allowed')) {
        throw StateError(
            'Supabase denied the image upload. Check the notification-images policies.');
      }
      throw StateError('Image upload failed: ${error.message}');
    }
  }
}
