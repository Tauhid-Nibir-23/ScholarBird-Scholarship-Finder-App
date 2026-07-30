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
    final apiKey = dotenv.env['GEMINI_API_KEY']?.trim();
    if (apiKey == null || apiKey.isEmpty || apiKey == 'YOUR_KEY') {
      throw const GeminiConfigurationException(
        'Gemini API key is missing. Add GEMINI_API_KEY to .env and restart the app.',
      );
    }

    final model = _model ?? GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(responseMimeType: 'application/json'),
    );

    try {
      final response = await model.generateContent([Content.text(_prompt(user, scholarships))]);
      return _parseRecommendations(response.text);
    } on GenerativeAIException catch (error) {
      throw GeminiRequestException('Gemini could not generate recommendations: ${error.message}');
    } on FormatException {
      throw const GeminiRequestException('Gemini returned an unreadable recommendation response.');
    }
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
        .map((item) => ScholarshipRecommendation.fromJson(Map<String, dynamic>.from(item)))
        .where((item) =>
            item.scholarshipName.isNotEmpty && item.matchProbability.isNotEmpty && item.reason.isNotEmpty)
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
