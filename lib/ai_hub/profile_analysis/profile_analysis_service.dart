/// Generates a qualitative profile analysis for the current user.
///
/// The service reuses the existing [ChatContext] (which already bundles
/// `UserProfile`, uploaded documents and references) and the shared
/// `GeminiService` transport. It does **not** compute a number — the prompt
/// instructs Gemini to pick one of four fixed qualitative bands and to
/// explain every single suggestion.
library;

import 'dart:convert';

import '../chat/chat_context.dart';
import '../services/gemini_service.dart';
import 'profile_analysis_report.dart';

/// Stateless orchestrator that builds the analysis prompt, calls Gemini and
/// validates the structured response.
class ProfileAnalysisService {
  ProfileAnalysisService({GeminiService? gemini})
      : _gemini = gemini ?? GeminiService();

  final GeminiService _gemini;

  /// The four qualitative bands the model is allowed to return. The list is
  /// intentionally hard-coded so the UI can never be tricked into displaying
  /// a percentage or a fabricated weighted score.
  static const List<String> _kAllowedRatings = <String>[
    'Emerging',
    'Developing',
    'Competitive',
    'Strong',
  ];

  /// Generates a structured [ProfileAnalysisReport] for the supplied context.
  Future<ProfileAnalysisReport> analyze({
    required ChatContext context,
    required DateTime now,
  }) async {
    final raw = await _gemini.generateRaw(
      _prompt(context),
      busyMessage:
          'Gemini is temporarily busy. Please try again in a moment.',
      defaultErrorMessage:
          'Gemini could not complete the profile analysis.',
    );
    return _parse(raw, now);
  }

  /// Builds the prompt sent to Gemini. The structure mirrors the SOP
  /// generator's JSON-only contract so parsing rules can be shared.
  String _prompt(ChatContext context) {
    final contextJson = context.toJsonString();
    final allowedRatings = _kAllowedRatings.join(', ');
    return '''
You are ScholarBird's profile analyst. Analyse the applicant whose academic
profile, uploaded documents and academic references are summarised under
APPLICANT_CONTEXT and produce a personalised readiness report.

The report must be QUALITATIVE only:
  - Do not invent numbers, percentages, or weighted scores.
  - Pick the overall rating from this exact list: $allowedRatings.
  - Every bullet must come with a one-sentence rationale explaining why it
    applies to *this* applicant. If you cannot justify a bullet, omit it.
  - Treat the applicant context as the source of truth. If a field is empty
    (for example no references yet, or no English proficiency score), say
    so explicitly rather than guessing.

APPLICANT_CONTEXT (JSON):
$contextJson

OUTPUT FORMAT — return strict JSON only, no markdown, no comments:
{
  "overallRating": "<one of: $allowedRatings>",
  "ratingRationale": "<one paragraph explaining why this rating fits the applicant>",
  "strengths": [
    { "title": "<short headline>", "rationale": "<why this is a strength for THIS applicant>" }
  ],
  "weaknesses": [
    { "title": "<short headline>", "rationale": "<why this is a gap to address>" }
  ],
  "missingDocuments": [
    { "title": "<document type>", "rationale": "<why this document is needed before applying>" }
  ],
  "scholarshipReadiness": "<one paragraph on where the applicant is in the application pipeline>",
  "suggestedImprovements": [
    { "title": "<actionable step>", "rationale": "<what changes once they do this>" }
  ],
  "bestScholarshipTypes": [
    { "title": "<scholarship name or archetype>", "rationale": "<why this fits the applicant>" }
  ],
  "countriesRecommendation": [
    { "title": "<country>", "rationale": "<why this country matches the profile and preferences>" }
  ],
  "summary": "<one paragraph summary the applicant can read at a glance>"
}

GUIDANCE:
  - strengths: 2-5 items, focused on distinct qualities (CGPA, skills,
    research, leadership, international experience, etc.)
  - weaknesses: 1-4 items, only flag gaps that meaningfully affect
    scholarship outcomes
  - missingDocuments: 1-5 items, name the document type (e.g. "Transcript",
    "English Proficiency") and tie it to the scholarship categories it
    unlocks
  - suggestedImprovements: 3-5 items, each should be specific and doable
    within a few weeks
  - bestScholarshipTypes: 2-4 items, pair Government / University / Private
    archetypes with the applicant story
  - countriesRecommendation: 2-4 items, prefer the applicant's preferred
    countries when they fit, otherwise justify a new recommendation
  - If the applicant has no preferred countries, recommend 2-3 countries
    that match their field and budget
''';
  }

  /// Parses the raw Gemini response into a strict [ProfileAnalysisReport].
  ProfileAnalysisReport _parse(String? responseText, DateTime now) {
    if (responseText == null || responseText.trim().isEmpty) {
      throw const GeminiRequestException(
        'Gemini returned an empty profile analysis.',
      );
    }
    final cleaned = responseText
        .trim()
        .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '');
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is! Map) {
        throw const FormatException('Expected a JSON object.');
      }
      data = Map<String, dynamic>.from(decoded);
    } on FormatException catch (error) {
      throw GeminiRequestException(
        'Gemini returned an unreadable analysis response: ${error.message}',
      );
    }

    final rating = _normaliseRating(data['overallRating']);
    final ratingRationale =
        (data['ratingRationale'] as String?)?.trim() ?? '';

    return ProfileAnalysisReport(
      overallRating: ProfileRating.fromLabel(rating),
      ratingRationale: ratingRationale.isEmpty
          ? 'Gemini did not provide a rationale for the overall rating.'
          : ratingRationale,
      strengths: _decodeInsights(data['strengths']),
      weaknesses: _decodeInsights(data['weaknesses']),
      missingDocuments: _decodeInsights(data['missingDocuments']),
      scholarshipReadiness:
          (data['scholarshipReadiness'] as String?)?.trim() ??
              'Gemini did not provide a readiness summary.',
      suggestedImprovements: _decodeInsights(data['suggestedImprovements']),
      bestScholarshipTypes: _decodeInsights(data['bestScholarshipTypes']),
      countriesRecommendation:
          _decodeInsights(data['countriesRecommendation']),
      summary: (data['summary'] as String?)?.trim() ??
          'Gemini did not provide a summary for this report.',
      generatedAt: now,
    );
  }

  /// Decodes an array of `{title, rationale}` objects. Items missing either
  /// field are dropped so the UI never renders an unjustified bullet.
  List<ProfileAnalysisInsight> _decodeInsights(dynamic raw) {
    if (raw is! List) {
      return const <ProfileAnalysisInsight>[];
    }
    final out = <ProfileAnalysisInsight>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final title = (map['title'] as String?)?.trim() ?? '';
      final rationale = (map['rationale'] as String?)?.trim() ?? '';
      if (title.isEmpty || rationale.isEmpty) {
        continue;
      }
      out.add(ProfileAnalysisInsight(title: title, rationale: rationale));
    }
    return List.unmodifiable(out);
  }

  /// Coerces the model output into one of the four allowed bands. Anything
  /// that does not match exactly is prefixed with a clear marker so the UI
  /// can surface that the model returned an unexpected value.
  String _normaliseRating(dynamic raw) {
    final cleaned = (raw?.toString() ?? '').trim();
    for (final allowed in _kAllowedRatings) {
      if (cleaned.toLowerCase() == allowed.toLowerCase()) {
        return allowed;
      }
    }
    if (cleaned.isEmpty) {
      return ProfileRating.developing.label;
    }
    return '${ProfileRating.developing.label} (note: model returned "$cleaned")';
  }
}
