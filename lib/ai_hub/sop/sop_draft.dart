import 'package:flutter/foundation.dart';

import 'scholarship_type.dart';

/// In-memory representation of a generated SOP draft.
///
/// Drafts are persisted to Firestore (under `users/{uid}/aiHub/sops/{id}`) so
/// the user can re-open the output and download the PDF again without paying
/// for another generation.
@immutable
class SopDraft {
  const SopDraft({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    required this.targetProgramme,
    required this.targetUniversity,
    required this.targetField,
    required this.scholarshipName,
    required this.wordCount,
    required this.missingFields,
    required this.regenerations,
    this.notes = '',
  });

  /// Firestore document id (auto-generated when first saved).
  final String id;

  /// Owning user id — denormalised for collection-group queries.
  final String userId;

  /// Short title shown in history lists; default = scholarship label.
  final String title;

  /// Full SOP body in plain text.
  final String body;

  /// Which scholarship flavour this draft targets.
  final ScholarshipType type;

  /// Timestamp when the draft was first generated.
  final DateTime createdAt;

  /// Programme the draft was written for (may be empty).
  final String targetProgramme;
  final String targetUniversity;
  final String targetField;

  /// Specific scholarship name (may be empty).
  final String scholarshipName;

  /// Approximate word count (computed at generation time).
  final int wordCount;

  /// Profile fields Gemini flagged as missing — used to render a friendly
  /// "you may want to add this" hint in the UI.
  final List<String> missingFields;

  /// How many times the user pressed Regenerate (so we can cap abuse).
  final int regenerations;

  /// Free-form user notes attached to this draft.
  final String notes;

  /// Safe filename for download — strips characters that confuse filesystems.
  String suggestedFilename() {
    final source = (title.isNotEmpty
            ? title
            : '${type.label} SOP')
        .toLowerCase();
    final cleaned =
        source.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'_+'), '_');
    final base = cleaned.replaceAll(RegExp(r'^_|_$'), '');
    return '${base.isEmpty ? 'sop' : base}.pdf';
  }

  /// Pretty subtitle for the history card.
  String get subtitle {
    final parts = <String>[];
    if (targetProgramme.trim().isNotEmpty) parts.add(targetProgramme.trim());
    if (targetUniversity.trim().isNotEmpty) parts.add(targetUniversity.trim());
    if (parts.isEmpty) return type.label;
    return '${parts.join(' • ')} • ${type.label}';
  }
}

/// Persisted form used by [AiHistoryService] to round-trip the draft through
/// Firestore. Keeps the in-memory model ([SopDraft]) free of `json_serializable`
/// boilerplate.
@immutable
class SopDraftRecord {
  const SopDraftRecord({
    required this.id,
    required this.data,
    required this.createdAt,
  });

  final String id;
  final Map<String, dynamic> data;
  final DateTime createdAt;

  SopDraft toDraft({required String userId}) {
    final type = ScholarshipType.fromId(data['scholarshipType'] as String?);
    final missing = (data['missingFields'] as List?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];
    return SopDraft(
      id: id,
      userId: userId,
      title: (data['title'] as String?) ?? type.label,
      body: (data['body'] as String?) ?? '',
      type: type,
      createdAt: createdAt,
      targetProgramme: (data['targetProgramme'] as String?) ?? '',
      targetUniversity: (data['targetUniversity'] as String?) ?? '',
      targetField: (data['targetField'] as String?) ?? '',
      scholarshipName: (data['scholarshipName'] as String?) ?? '',
      wordCount: (data['wordCount'] as num?)?.toInt() ?? 0,
      missingFields: missing,
      regenerations: (data['regenerations'] as num?)?.toInt() ?? 0,
      notes: (data['notes'] as String?) ?? '',
    );
  }

  static Map<String, dynamic> fromDraft(
    SopDraft draft, {
    required DateTime now,
  }) =>
      <String, dynamic>{
        'title': draft.title,
        'body': draft.body,
        'scholarshipType': draft.type.id,
        'targetProgramme': draft.targetProgramme,
        'targetUniversity': draft.targetUniversity,
        'targetField': draft.targetField,
        'scholarshipName': draft.scholarshipName,
        'wordCount': draft.wordCount,
        'missingFields': draft.missingFields,
        'regenerations': draft.regenerations,
        'notes': draft.notes,
        'updatedAt': now,
        'createdAt': draft.createdAt,
      };
}
