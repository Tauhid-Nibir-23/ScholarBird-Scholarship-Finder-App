import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../models/scholarship.dart';
import '../models/scholarship_recommendation.dart';
import '../models/user_profile.dart';

class GeminiService {
  GeminiService({GenerativeModel? model}) : _model = model;

  final GenerativeModel? _model;

  Future<List<ScholarshipRecommendation>> getScholarshipRecommendations(
    UserProfile user,
    List<Scholarship> scholarships,
  ) async {
    if (scholarships.isEmpty) return <ScholarshipRecommendation>[];
    // Support the existing GOOGLE_API_KEY name as well as the app-specific
    // GEMINI_API_KEY name so existing local configurations keep working.
    final apiKey =
        (dotenv.env['GEMINI_API_KEY'] ?? dotenv.env['GOOGLE_API_KEY'])?.trim();
    if (apiKey == null || apiKey.isEmpty || apiKey == 'YOUR_KEY') {
      throw const GeminiConfigurationException(
        'Gemini API key is missing. Add GEMINI_API_KEY or GOOGLE_API_KEY to .env and restart the app.',
      );
    }

    final models = _model == null
        ? <GenerativeModel>[
            _createModel('gemini-3.5-flash', apiKey),
            // A lower-demand model keeps recommendations available when the
            // primary Flash endpoint is temporarily at capacity.
            _createModel('gemini-3.5-flash-lite', apiKey),
          ]
        : <GenerativeModel>[_model!];

    GenerativeAIException? lastError;
    for (final model in models) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final response = await model
              .generateContent([Content.text(_prompt(user, scholarships))]);
          return _parseRecommendations(response.text);
        } on GenerativeAIException catch (error) {
          lastError = error;
          if (!_isTemporaryUnavailable(error) || attempt == 1) break;
          await Future<void>.delayed(Duration(seconds: attempt + 1));
        } on FormatException {
          throw const GeminiRequestException(
              'Gemini returned an unreadable recommendation response.');
        }
      }
    }

    if (lastError != null && _isTemporaryUnavailable(lastError)) {
      throw const GeminiRequestException(
        'Gemini is temporarily busy. Please try again in a moment.',
      );
    }
    throw GeminiRequestException(
      'Gemini could not generate recommendations: ${lastError?.message ?? 'Unknown error'}',
    );
  }

  GenerativeModel _createModel(String modelName, String apiKey) =>
      GenerativeModel(
        model: modelName,
        apiKey: apiKey,
        generationConfig:
            GenerationConfig(responseMimeType: 'application/json'),
      );

  bool _isTemporaryUnavailable(GenerativeAIException error) {
    final message = error.message.toLowerCase();
    return message.contains('503') ||
        message.contains('unavailable') ||
        message.contains('high demand');
  }

  String _prompt(UserProfile user, List<Scholarship> scholarships) => '''
You are ScholarBird's scholarship advisor. Select the top five matching entries only from SCHOLARSHIPS. Use the applicant profile and scholarship eligibility. Do not invent scholarships or requirements.

APPLICANT PROFILE:
${jsonEncode({
            'degree': user.degree,
            'cgpa': user.cgpa,
            'country': user.country,
            'skills': user.skills,
            'preferredStudyCountries': user.preferredStudyCountries,
            'academicBackground': user.academicBackground,
          })}

SCHOLARSHIPS:
${jsonEncode(scholarships.map((item) => item.toGeminiMap()).toList())}

Return JSON only: an array of at most five objects. Every object must have exactly scholarshipName, matchProbability (for example "92%"), and reason. Keep each reason concise.
''';

  List<ScholarshipRecommendation> _parseRecommendations(String? responseText) {
    if (responseText == null || responseText.trim().isEmpty) {
      throw const GeminiRequestException('Gemini returned no recommendations.');
    }
    final cleaned = responseText
        .trim()
        .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '');
    final decoded = jsonDecode(cleaned);
    if (decoded is! List) throw const FormatException('Expected a JSON array.');
    return decoded
        .whereType<Map>()
        .map((item) =>
            ScholarshipRecommendation.fromJson(Map<String, dynamic>.from(item)))
        .where((item) =>
            item.scholarshipName.isNotEmpty &&
            item.matchProbability.isNotEmpty &&
            item.reason.isNotEmpty)
        .take(5)
        .toList();
  }
}

class GeminiConfigurationException implements Exception {
  const GeminiConfigurationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GeminiRequestException implements Exception {
  const GeminiRequestException(this.message);
  final String message;
  @override
  String toString() => message;
}
