import 'package:flutter/foundation.dart';

import '../../models/document_model.dart';
import '../../models/reference_model.dart';
import '../../models/user_profile.dart';
import 'scholarship_type.dart';

/// Inputs collected for the SOP prompt.
///
/// The struct deliberately mirrors only the fields the model should reason
/// about — raw document blobs, full reference lists and unrelated profile
/// data stay out of the prompt to keep token usage predictable.
@immutable
class SopPromptParams {
  const SopPromptParams({
    required this.user,
    required this.type,
    required this.targetProgramme,
    required this.targetUniversity,
    required this.targetField,
    this.scholarshipName = '',
    this.wordCountTarget = 800,
    this.additionalNotes = '',
    this.documents = const <DocumentModel>[],
    this.references = const <ReferenceModel>[],
    this.sopDocuments = const <DocumentModel>[],
  });

  /// Applicant context used by Gemini to stay grounded.
  final UserProfile user;

  /// Scholarship flavour — controls tone + structure.
  final ScholarshipType type;

  /// Optional programme name (e.g. "Computer Science MSc").
  final String targetProgramme;

  /// Optional university or programme consortium.
  final String targetUniversity;

  /// Optional field of study (e.g. "Renewable Energy Engineering").
  final String targetField;

  /// Specific named scholarship when known (DAAD Helmut Schmidt, Chevening
  /// partner scheme, etc.). Empty when the user wants a generic SOP.
  final String scholarshipName;

  /// Word count guidance — defaults to ~800 words, which sits between the
  /// typical DAAD and Chevening upper limits.
  final int wordCountTarget;

  /// Free-form notes the applicant wants folded into the narrative.
  final String additionalNotes;

  /// Supporting documents (transcripts, CV, motivation letter draft, etc.).
  final List<DocumentModel> documents;

  /// Already-uploaded SOP drafts — folded in so the new draft can avoid
  /// contradicting prior writing.
  final List<DocumentModel> sopDocuments;

  /// Academic references that may be mentioned.
  final List<ReferenceModel> references;

  /// Subset of documents the applicant actually wants to lean on.
  Iterable<DocumentModel> get leanedOnDocuments => [
        ...documents,
        ...sopDocuments,
      ];

  /// Brief one-line description of the profile Gemini can use.
  String buildProfileSummary() {
    final parts = <String>[];
    if (user.degree.trim().isNotEmpty) {
      parts.add('Current/most recent degree: ${user.degree.trim()}.');
    }
    final cgpaText = user.cgpa?.toString().trim() ?? '';
    if (cgpaText.isNotEmpty) {
      parts.add('Grade: $cgpaText.');
    }
    if (user.country.trim().isNotEmpty) {
      parts.add('From: ${user.country.trim()}.');
    }
    final skillsText = user.skills.join(', ').trim();
    if (skillsText.isNotEmpty) {
      parts.add('Skills: $skillsText.');
    }
    final countriesText = user.preferredStudyCountries.join(', ').trim();
    if (countriesText.isNotEmpty) {
      parts.add('Preferred study destinations: $countriesText.');
    }
    if (user.academicBackground.trim().isNotEmpty) {
      parts.add('Academic context: ${user.academicBackground.trim()}.');
    }
    if (parts.isEmpty) {
      return 'Limited profile information available.';
    }
    return parts.join(' ');
  }

  /// Programme / scholarship framing (may be empty if applicant skipped it).
  String buildProgrammeSummary() {
    final parts = <String>[];
    if (targetProgramme.trim().isNotEmpty) {
      parts.add('Programme: ${targetProgramme.trim()}.');
    }
    if (targetUniversity.trim().isNotEmpty) {
      parts.add('University: ${targetUniversity.trim()}.');
    }
    if (targetField.trim().isNotEmpty) {
      parts.add('Field: ${targetField.trim()}.');
    }
    if (scholarshipName.trim().isNotEmpty) {
      parts.add('Specific scholarship: ${scholarshipName.trim()}.');
    }
    if (parts.isEmpty) return '';
    return parts.join(' ');
  }

  /// Output schema for the JSON parser.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'applicant': buildProfileSummary(),
        'programme': buildProgrammeSummary(),
        'scholarshipType': type.id,
        'scholarshipLabel': type.label,
        'scholarshipCountry': type.country,
        'scholarshipFraming': type.description,
        'wordCountTarget': wordCountTarget,
        'additionalNotes': additionalNotes,
        'documents': leanedOnDocuments
            .map((doc) => <String, dynamic>{
                  'title': doc.fileName ?? doc.type.label,
                  'type': doc.type.label,
                })
            .toList(),
        'references': references
            .where((ref) => ref.isComplete)
            .map((ref) => <String, dynamic>{
                  'fullName': ref.fullName,
                  'designation': ref.designation,
                  'department': ref.department,
                  'university': ref.university,
                  'relationship': ref.relationship,
                })
            .toList(),
      };
}
