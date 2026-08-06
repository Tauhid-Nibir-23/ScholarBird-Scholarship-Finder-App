/// Coordinates Firestore metadata + Supabase Storage file uploads for the
/// user documents subcollection.
///
/// All document metadata lives at `users/{uid}/documents/{documentType}` in
/// Firestore. File bytes are uploaded to the Supabase Storage bucket
/// `documents` under the path `users/{uid}/{documentType}/{fileName}`, and
/// the public download URL is written back into the Firestore record.
library;

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/document_model.dart';
import 'supabase_config.dart';

/// Small value object returned by the file picker.
class _PickedFile {
  const _PickedFile({
    required this.name,
    required this.size,
    required this.bytes,
  });

  final String name;
  final int size;
  final Uint8List bytes;
}

/// Coordinates Firestore metadata + Supabase Storage uploads for user
/// documents.
class DocumentsService {
  DocumentsService._();

  /// Shared singleton instance.
  static final DocumentsService instance = DocumentsService._();

  /// Name of the Supabase Storage bucket that holds document files.
  static const String bucketName = 'documents';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  SupabaseClient get _storage => Supabase.instance.client;

  /// Returns the documents subcollection for the current user, or null when
  /// no user is signed in.
  CollectionReference<Map<String, dynamic>>? _collection() {
    final user = _auth.currentUser;
    if (user == null) return null;
    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('documents');
  }

  /// Streams the full set of document slots, keyed by [DocumentType]. A
  /// slot is always emitted for every supported [DocumentType] even when
  /// the user has not uploaded anything yet, so the UI can render a card
  /// for every category.
  Stream<List<DocumentModel>> streamDocuments() {
    final collection = _collection();
    if (collection == null) {
      return Stream<List<DocumentModel>>.value(
        DocumentType.values.map(_emptyFor).toList(growable: false),
      );
    }
    return collection.snapshots().map((snapshot) {
      final byId = <String, DocumentModel>{
        for (final doc in snapshot.docs)
          doc.id: DocumentModel.fromFirestore(doc),
      };
      return DocumentType.values
          .map((type) => byId[type.firestoreId] ?? _emptyFor(type))
          .toList(growable: false);
    });
  }

  /// Persists the metadata record for a single document. If the slot does
  /// not yet exist it is created; otherwise it is overwritten.
  ///
  /// When [pickFile] is true the user is prompted to choose a file from
  /// the device; that file is uploaded to Supabase Storage and the public
  /// download URL is written into the Firestore record. When false, only
  /// the metadata (fileName, fileSize, uploadedAt) supplied on [document]
  /// is saved as-is — useful for re-saving an existing record.
  Future<void> saveDocument(
    DocumentModel document, {
    bool pickFile = false,
  }) async {
    final collection = _collection();
    if (collection == null) {
      throw StateError('No authenticated user available for document upload.');
    }

    DocumentModel toSave = document;

    if (pickFile) {
      final picked = await _pickFile();
      if (picked == null) {
        // User cancelled the picker — leave existing record untouched.
        return;
      }
      final publicUrl = await _uploadBytes(
        document: document,
        bytes: picked.bytes,
        fileName: picked.name,
      );
      toSave = document.copyWith(
        fileName: picked.name,
        downloadUrl: publicUrl,
        fileSize: picked.size,
        uploadedAt: DateTime.now(),
      );
    }

    await collection.doc(document.type.firestoreId).set(
          toSave.toMap(),
          SetOptions(merge: true),
        );
  }

  /// Lets the user pick a single file via the OS file picker. Returns null
  /// when the user cancels.
  Future<_PickedFile?> _pickFile() async {
    // ignore: avoid_print
    print('[DocUpload] _pickFile: opening file picker...');
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    // ignore: avoid_print
    print('[DocUpload] _pickFile: result=${result == null ? 'null' : 'files=${result.files.length}'}');
    final file = result?.files.single;
    if (file == null) return null;
    final bytes = file.bytes;
    // ignore: avoid_print
    print('[DocUpload] _pickFile: name=${file.name} size=${bytes?.length ?? -1}');
    if (bytes == null) return null;
    return _PickedFile(name: file.name, size: bytes.length, bytes: bytes);
  }

  /// Uploads [bytes] to the Supabase bucket and returns the public URL.
  Future<String> _uploadBytes({
    required DocumentModel document,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user available for upload.');
    }
    // Sanitise the file name so unusual characters (spaces, accented
    // letters, etc.) don't confuse the Supabase storage REST endpoint.
    final safeName = fileName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        '${user.uid}/${document.type.firestoreId}/${DateTime.now().millisecondsSinceEpoch}-$safeName';
    // Log current config so 403 problems are debuggable from the console.
    // ignore: avoid_print
    print('[Supabase] upload → bucket=$bucketName path=$path '
        'keyPrefix=${SupabaseConfig.anonKey.substring(0, SupabaseConfig.anonKey.length < 12 ? SupabaseConfig.anonKey.length : 12)}...');
    try {
      // NOTE: do not set `upsert: true` — recent Supabase servers reject
      // requests with the `x-upsert: true` header that the SDK sends for
      // that flag, even when the underlying policy permits the insert.
      await _storage.storage.from(bucketName).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/octet-stream',
            ),
          );
    } on StorageException catch (e) {
      // ignore: avoid_print
      print('[Supabase] upload failed: status=${e.statusCode} msg=${e.message}');
      throw StateError(_explainUploadError(e));
    }
    return _storage.storage.from(bucketName).getPublicUrl(path);
  }

  /// Translates raw Supabase Storage errors into actionable messages the
  /// snackbar can show to the user.
  String _explainUploadError(StorageException e) {
    final msg = e.message.toLowerCase();
    if (e.statusCode == '404' || msg.contains('bucket not found')) {
      return 'Supabase bucket "$bucketName" was not found. Create a public bucket with that name in the Supabase dashboard.';
    }
    if (e.statusCode == '403' || msg.contains('not allowed')) {
      return 'Permission denied uploading to "$bucketName". '
          'Verify the bucket is Public and that INSERT/UPDATE/DELETE policies '
          'exist for the anon role. If the key in .env starts with '
          '"sb_publishable_", replace it with the legacy "anon" JWT from '
          'Settings > API > Legacy API Keys.';
    }
    if (e.statusCode == '401' || msg.contains('invalid api key') ||
        msg.contains('jwt')) {
      return 'Supabase rejected the API key. Use the legacy "anon" JWT '
          '(starts with "eyJhbGciOi...") from Settings > API > Legacy API '
          'Keys instead of the new "sb_publishable_..." key.';
    }
    return 'Upload failed: ${e.message}';
  }

  /// Removes the metadata record for [type]. A no-op when the slot is
  /// already empty.
  Future<void> deleteDocument(DocumentType type) async {
    final collection = _collection();
    if (collection == null) return;
    await collection.doc(type.firestoreId).delete();
  }

  DocumentModel _emptyFor(DocumentType type) =>
      DocumentModel(type: type);
}
