/// Snapshot of the user's academic context fed into the chat system prompt.
///
/// Combines the [UserProfile] with the user's uploaded documents and academic
/// references. All fields are JSON-serialisable so the prompt can hand them
/// to Gemini as a single structured block.
library;

import 'dart:convert';

import '../../models/document_model.dart';
import '../../models/reference_model.dart';
import '../../models/user_profile.dart';

/// Bundle of user-specific data injected into the chat system prompt.
class ChatContext {
  const ChatContext({
    required this.profile,
    required this.documents,
    required this.references,
  });

  /// Convenience factory that tolerates nulls — the chat stays functional
  /// even when the user has not completed their profile or uploaded any
  /// documents.
  factory ChatContext.from({
    required UserProfile profile,
    required List<DocumentModel> documents,
    required List<ReferenceModel> references,
  }) =>
      ChatContext(
        profile: profile,
        documents: documents
            .where((doc) => doc.isUploaded)
            .toList(growable: false),
        references: references
            .where((ref) => ref.isComplete)
            .toList(growable: false),
      );

  final UserProfile profile;
  final List<DocumentModel> documents;
  final List<ReferenceModel> references;

  /// Compact, JSON-serialised view of the context. We deliberately trim
  /// each value so we never accidentally push raw file blobs into the
  /// prompt — the model reasons about *which* documents exist, not their
  /// bytes.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'cgpa': profile.cgpa,
        'degree': profile.degree,
        'country': profile.country,
        'preferredCountries': profile.preferredStudyCountries,
        'skills': profile.skills,
        'academicBackground': profile.academicBackground,
        'documents': documents
            .map((doc) => <String, dynamic>{
                  'type': doc.type.label,
                  'fileName': doc.fileName,
                  'uploadedAt': doc.uploadedAt?.toIso8601String(),
                })
            .toList(),
        'references': references
            .map((ref) => <String, dynamic>{
                  'name': ref.fullName,
                  'designation': ref.designation,
                  'university': ref.university,
                  'relationship': ref.relationshipLabel,
                })
            .toList(),
      };

  /// Convenience used when rendering the chat bubble's "context loaded"
  /// hint — surfaces how much of the user's academic record we actually
  /// have to work with.
  String summary() {
    final docs = documents.length;
    final refs = references.length;
    final pieces = <String>[];
    if (profile.degree.isNotEmpty) pieces.add(profile.degree);
    if (profile.cgpa != null) pieces.add('CGPA ${profile.cgpa}');
    if (profile.preferredStudyCountries.isNotEmpty) {
      pieces.add('target: ${profile.preferredStudyCountries.join(', ')}');
    }
    if (docs > 0) pieces.add('$docs document${docs == 1 ? '' : 's'}');
    if (refs > 0) pieces.add('$refs reference${refs == 1 ? '' : 's'}');
    return pieces.isEmpty ? 'Profile context: not set up yet' : pieces.join(' • ');
  }

  /// Pretty JSON for embedding in the system prompt.
  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}