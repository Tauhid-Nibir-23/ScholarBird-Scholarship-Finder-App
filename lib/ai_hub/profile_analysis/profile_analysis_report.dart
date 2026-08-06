/// Immutable report produced by the profile analysis service.
///
/// Every list item is a `ProfileAnalysisInsight` — an idea *plus* the reason
/// Gemini produced it. The report deliberately avoids any quantitative score;
/// `overallRating` is one of a small fixed set of qualitative bands so the UI
/// never suggests an objective calculation has taken place.
library;

import 'package:flutter/foundation.dart';

/// Qualitative bands ScholarBird uses to summarise an applicant.
///
/// We use four discrete bands so a user can tell at a glance whether their
/// profile is "ready" or "needs work" without ever implying a percentage or
/// weighted score. The model is instructed to pick exactly one band per
/// report; any other value is surfaced verbatim and rendered in italic so the
/// UI stays honest about what came back from Gemini.
enum ProfileRating {
  emerging('Emerging'),
  developing('Developing'),
  competitive('Competitive'),
  strong('Strong');

  const ProfileRating(this.label);

  /// Human-friendly label shown in the UI.
  final String label;

  /// Tries to map an arbitrary string to a known band; falls back to
  /// `ProfileRating.developing` so the screen always has something to render.
  static ProfileRating fromLabel(String? raw) {
    final cleaned = (raw ?? '').trim().toLowerCase();
    for (final value in ProfileRating.values) {
      if (value.label.toLowerCase() == cleaned) {
        return value;
      }
    }
    return ProfileRating.developing;
  }
}

/// A single observation plus the reasoning that produced it.
///
/// The rationale is mandatory in the JSON contract — items without an
/// explanation are dropped during parsing so the UI never shows an
/// unjustified bullet point.
@immutable
class ProfileAnalysisInsight {
  const ProfileAnalysisInsight({
    required this.title,
    required this.rationale,
  });

  /// Short headline shown in bold above the rationale.
  final String title;

  /// Plain-language explanation for *why* Gemini flagged this insight.
  final String rationale;
}

/// Aggregated profile analysis report rendered by the UI.
///
/// All fields are required and non-nullable so the screen can render
/// unconditionally — the service validates the payload before constructing
/// an instance, and the Firestore record layer defaults missing sections to
/// empty lists rather than nulls.
@immutable
class ProfileAnalysisReport {
  const ProfileAnalysisReport({
    required this.overallRating,
    required this.ratingRationale,
    required this.strengths,
    required this.weaknesses,
    required this.missingDocuments,
    required this.scholarshipReadiness,
    required this.suggestedImprovements,
    required this.bestScholarshipTypes,
    required this.countriesRecommendation,
    required this.summary,
    required this.generatedAt,
  });

  /// Qualitative summary of how ready the applicant looks overall.
  final ProfileRating overallRating;

  /// Plain-language explanation of why the [overallRating] was chosen.
  final String ratingRationale;

  /// Things the applicant is doing well.
  final List<ProfileAnalysisInsight> strengths;

  /// Areas where the profile is thin or missing context.
  final List<ProfileAnalysisInsight> weaknesses;

  /// Document slots the applicant should fill in before applying.
  final List<ProfileAnalysisInsight> missingDocuments;

  /// Short narrative on where the applicant stands in the scholarship
  /// pipeline (e.g. "ready to apply to two programmes", "needs one more
  /// reference before submitting").
  final String scholarshipReadiness;

  /// Concrete, actionable next steps the applicant can take.
  final List<ProfileAnalysisInsight> suggestedImprovements;

  /// Scholarship flavours the applicant should target, with rationale.
  final List<ProfileAnalysisInsight> bestScholarshipTypes;

  /// Country recommendations, with reasoning for each.
  final List<ProfileAnalysisInsight> countriesRecommendation;

  /// One-paragraph human summary of the report.
  final String summary;

  /// Timestamp when the report was generated. Used for the history list.
  final DateTime generatedAt;

  /// Stable id derived from [generatedAt] so the history list can dedupe.
  String get id => 'analysis-${generatedAt.microsecondsSinceEpoch}';
}

/// Persisted form used by the AI history service to round-trip the report
/// through Firestore. Keeps the in-memory model free of `cloud_firestore`
/// imports so it stays testable.
@immutable
class ProfileAnalysisRecord {
  const ProfileAnalysisRecord({
    required this.id,
    required this.data,
    required this.createdAt,
  });

  /// Firestore document id (matches [ProfileAnalysisReport.id]).
  final String id;

  /// Raw Firestore payload — deserialised lazily by [toReport].
  final Map<String, dynamic> data;

  /// When the report was first generated.
  final DateTime createdAt;

  /// Rebuilds the in-memory `ProfileAnalysisReport` from Firestore data.
  ProfileAnalysisReport toReport() {
    final generatedAt =
        (data['generatedAt'] as String?) ?? createdAt.toIso8601String();
    final parsedAt = DateTime.tryParse(generatedAt) ?? createdAt;
    return ProfileAnalysisReport(
      overallRating: ProfileRating.fromLabel(data['overallRating'] as String?),
      ratingRationale: (data['ratingRationale'] as String?) ?? '',
      strengths: _insights(data['strengths']),
      weaknesses: _insights(data['weaknesses']),
      missingDocuments: _insights(data['missingDocuments']),
      scholarshipReadiness: (data['scholarshipReadiness'] as String?) ?? '',
      suggestedImprovements: _insights(data['suggestedImprovements']),
      bestScholarshipTypes: _insights(data['bestScholarshipTypes']),
      countriesRecommendation: _insights(data['countriesRecommendation']),
      summary: (data['summary'] as String?) ?? '',
      generatedAt: parsedAt,
    );
  }

  /// Builds a Firestore-friendly map from an in-memory report.
  static Map<String, dynamic> fromReport(ProfileAnalysisReport report) =>
      <String, dynamic>{
        'overallRating': report.overallRating.label,
        'ratingRationale': report.ratingRationale,
        'strengths': _encodeInsights(report.strengths),
        'weaknesses': _encodeInsights(report.weaknesses),
        'missingDocuments': _encodeInsights(report.missingDocuments),
        'scholarshipReadiness': report.scholarshipReadiness,
        'suggestedImprovements': _encodeInsights(report.suggestedImprovements),
        'bestScholarshipTypes': _encodeInsights(report.bestScholarshipTypes),
        'countriesRecommendation':
            _encodeInsights(report.countriesRecommendation),
        'summary': report.summary,
        'generatedAt': report.generatedAt.toIso8601String(),
        'createdAt': report.generatedAt,
      };

  static List<ProfileAnalysisInsight> _insights(dynamic raw) {
    if (raw is! List) {
      return const <ProfileAnalysisInsight>[];
    }
    return raw
        .whereType<Map>()
        .map((item) {
          final map = Map<String, dynamic>.from(item);
          final title = (map['title'] as String?)?.trim() ?? '';
          final rationale = (map['rationale'] as String?)?.trim() ?? '';
          if (title.isEmpty || rationale.isEmpty) {
            return null;
          }
          return ProfileAnalysisInsight(
            title: title,
            rationale: rationale,
          );
        })
        .whereType<ProfileAnalysisInsight>()
        .toList(growable: false);
  }

  static List<Map<String, String>> _encodeInsights(
    List<ProfileAnalysisInsight> insights,
  ) =>
      insights
          .map((item) => <String, String>{
                'title': item.title,
                'rationale': item.rationale,
              })
          .toList(growable: false);
}
