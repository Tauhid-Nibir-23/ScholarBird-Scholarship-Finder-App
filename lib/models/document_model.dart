/// Domain model for an uploadable academic document attached to a user.
///
/// Documents are persisted as Firestore metadata records at
/// `users/{uid}/documents/{documentType}`. File bytes themselves live in
/// Firebase Storage under
/// `users/{uid}/{documentType}/{fileName}` — this model intentionally keeps
/// only the metadata needed to render the UI and (later) trigger storage
/// uploads, so the rest of the app can stay Firestore-only.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// The fixed list of document categories ScholarBird supports.
///
/// Keep this enum the single source of truth: the document section iterates
/// through it to render a card for every type, the storage service uses it
/// to derive canonical file paths, and the Firestore subcollection id is
/// the [firestoreId] of each value.
enum DocumentType {
  passport('passport', 'Passport', Icons.badge_outlined),
  nationalId('nationalId', 'National ID', Icons.credit_card_outlined),
  cv('cv', 'CV / Resume', Icons.description_outlined),
  sop('sop', 'Statement of Purpose (SOP)', Icons.article_outlined),
  transcript('transcript', 'Academic Transcript', Icons.menu_book_outlined),
  degreeCertificate(
      'degreeCertificate', 'Degree Certificate', Icons.workspace_premium_outlined),
  englishProficiency(
      'englishProficiency', 'IELTS / TOEFL', Icons.translate_outlined),
  recommendationLetter(
      'recommendationLetter', 'Recommendation Letter', Icons.mail_outline_rounded),
  other('other', 'Other Documents', Icons.attach_file_rounded);

  const DocumentType(this.firestoreId, this.label, this.icon);

  /// Stable identifier persisted in Firestore and used in storage paths.
  final String firestoreId;

  /// Human-friendly label shown in the UI.
  final String label;

  /// Decorative icon rendered on the document card.
  final IconData icon;

  /// Returns the enum value whose [firestoreId] matches [id], or null.
  static DocumentType? tryFromId(String? id) {
    if (id == null) return null;
    for (final value in DocumentType.values) {
      if (value.firestoreId == id) return value;
    }
    return null;
  }
}

/// Immutable representation of a single uploadable document record.
///
/// All fields are nullable because the same model is used both for records
/// that have been uploaded and for the placeholder "not uploaded" state.
class DocumentModel {
  const DocumentModel({
    required this.type,
    this.fileName,
    this.downloadUrl,
    this.uploadedAt,
    this.fileSize,
  });

  /// The slot this document occupies — also the Firestore subcollection id.
  final DocumentType type;

  /// The original file name as uploaded by the user.
  final String? fileName;

  /// Download URL pointing at the file in Firebase Storage.
  final String? downloadUrl;

  /// When the document was last uploaded (or replaced).
  final DateTime? uploadedAt;

  /// File size in bytes.
  final int? fileSize;

  /// True when at least the metadata required to render an "uploaded" card
  /// is present. A document with a [downloadUrl] is considered uploaded.
  bool get isUploaded =>
      (downloadUrl != null && downloadUrl!.trim().isNotEmpty) ||
      (fileName != null && fileName!.trim().isNotEmpty);

  /// Convenience: pretty file size, e.g. `1.2 MB`. Returns `—` when unknown.
  String get displaySize {
    final bytes = fileSize;
    if (bytes == null || bytes <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit += 1;
    }
    return '${size.toStringAsFixed(size >= 10 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  /// Builds a [DocumentModel] from a Firestore document snapshot.
  factory DocumentModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return DocumentModel.fromMap(data, fallbackId: snapshot.id);
  }

  /// Builds a [DocumentModel] from a Firestore map. [fallbackId] is the
  /// Firestore document id used when the map does not carry [documentType].
  factory DocumentModel.fromMap(
    Map<String, dynamic> map, {
    String? fallbackId,
  }) {
    final type = DocumentType.tryFromId(map['documentType'] as String?) ??
        DocumentType.tryFromId(fallbackId) ??
        DocumentType.other;
    return DocumentModel(
      type: type,
      fileName: map['fileName'] as String?,
      downloadUrl: map['downloadUrl'] as String?,
      uploadedAt: _date(map['uploadedAt']),
      fileSize: _int(map['fileSize']),
    );
  }

  /// Serialises the model to a Firestore-friendly map.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'documentType': type.firestoreId,
        'fileName': fileName,
        'downloadUrl': downloadUrl,
        'uploadedAt': uploadedAt == null ? null : Timestamp.fromDate(uploadedAt!),
        'fileSize': fileSize,
      };

  /// Returns a copy with the supplied fields replaced.
  DocumentModel copyWith({
    DocumentType? type,
    String? fileName,
    String? downloadUrl,
    DateTime? uploadedAt,
    int? fileSize,
  }) =>
      DocumentModel(
        type: type ?? this.type,
        fileName: fileName ?? this.fileName,
        downloadUrl: downloadUrl ?? this.downloadUrl,
        uploadedAt: uploadedAt ?? this.uploadedAt,
        fileSize: fileSize ?? this.fileSize,
      );

  static DateTime? _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse('${value ?? ''}');
  }

  static int? _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}');
  }
}