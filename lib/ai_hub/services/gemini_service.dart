import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../../models/scholarship.dart';
import '../../models/scholarship_recommendation.dart';
import '../../models/user_profile.dart';

/// Thin Gemini transport used by every AI Hub feature.
///
/// The class is intentionally generic — each AI Hub feature (SOP Generator,
/// chat, profile analysis) supplies its own prompt + parser via [_request].
class GeminiService {
  GeminiService({GenerativeModel? model}) : _model = model;

  final GenerativeModel? _model;

  /// Returns the top five matching scholarships for the supplied user.
  Future<List<ScholarshipRecommendation>> getScholarshipRecommendations(
    UserProfile user,
    List<Scholarship> scholarships,
  ) async {
    if (scholarships.isEmpty) return <ScholarshipRecommendation>[];

    final text = await _request<String>(
      prompt: _recommendationPrompt(user, scholarships),
      parser: (raw) => raw ?? '',
      busyMessage:
          'Gemini is temporarily busy. Please try again in a moment.',
    );
    return _parseRecommendations(text);
  }

  /// Sends an arbitrary prompt and returns the raw response text.
  ///
  /// Used by AI Hub features (SOP generator, profile analysis, chat) that
  /// need Gemini's natural language output but apply their own parsing.
  /// Inherits the same primary → fallback → retry transport as the
  /// recommendation path.
  Future<String> generateRaw(
    String prompt, {
    String busyMessage = 'Gemini is temporarily busy. Please try again in a moment.',
    String defaultErrorMessage = 'Gemini could not complete the request.',
  }) =>
      _request<String>(
        prompt: prompt,
        parser: (text) => text ?? '',
        busyMessage: busyMessage,
        defaultErrorMessage: defaultErrorMessage,
      );

  /// Sends an arbitrary prompt and returns a stream of incremental text
  /// chunks as Gemini produces them.
  ///
  /// Used by the AI Hub chat feature to provide a streaming response. The
  /// transport reuses the same primary → fallback model list as
  /// [generateRaw]; on a transient 503 the call retries on the same model,
  /// and only falls through to the lite variant after the primary has been
  /// exhausted. The returned stream emits [String] chunks — when the model
  /// is unavailable the stream completes with a [GeminiRequestException]
  /// surfaced as an error event.
  Stream<String> generateRawStream(
    String prompt, {
    String busyMessage = 'Gemini is temporarily busy. Please try again in a moment.',
    String defaultErrorMessage = 'Gemini could not complete the request.',
  }) =>
      _stream(prompt, busyMessage, defaultErrorMessage);

  /// Resolves the model list for the primary → fallback strategy.
  /// Returns `null` when no API key is configured.
  List<GenerativeModel>? _resolveModels() {
    if (_model != null) return <GenerativeModel>[_model!];
    // Support the existing GOOGLE_API_KEY name as well as the app-specific
    // GEMINI_API_KEY name so existing local configurations keep working.
    final apiKey =
        (dotenv.env['GEMINI_API_KEY'] ?? dotenv.env['GOOGLE_API_KEY'])?.trim();
    if (apiKey == null || apiKey.isEmpty || apiKey == 'YOUR_KEY') {
      return null;
    }
    return <GenerativeModel>[
      _createModel('gemini-3.5-flash', apiKey),
      // A lower-demand model keeps recommendations available when the
      // primary Flash endpoint is temporarily at capacity.
      _createModel('gemini-3.5-flash-lite', apiKey),
    ];
  }

  /// Shared transport used by every AI Hub feature.
  ///
  /// 1. Resolves the configured Gemini models (or throws a configuration
  ///    exception when the API key is missing).
  /// 2. Tries the primary model, falling back to the lite variant.
  /// 3. Retries each model once on transient 503 / high-demand errors.
  /// 4. Hands the raw response text to the caller-supplied [parser].
  Future<T> _request<T>({
    required String prompt,
    required T Function(String?) parser,
    required String busyMessage,
    String defaultErrorMessage = 'Gemini could not complete the request.',
  }) async {
    final models = _resolveModels();
    if (models == null) {
      throw const GeminiConfigurationException(
        'Gemini API key is missing. Add GEMINI_API_KEY or GOOGLE_API_KEY to .env and restart the app.',
      );
    }

    GenerativeAIException? lastError;
    for (final model in models) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final response =
              await model.generateContent([Content.text(prompt)]);
          return parser(response.text);
        } on GenerativeAIException catch (error) {
          lastError = error;
          if (!_isTemporaryUnavailable(error) || attempt == 1) break;
          await Future<void>.delayed(Duration(seconds: attempt + 1));
        } on FormatException catch (error) {
          throw GeminiRequestException(
              'Gemini returned an unreadable response: ${error.message}');
        }
      }
    }

    if (lastError != null && _isTemporaryUnavailable(lastError)) {
      throw GeminiRequestException(busyMessage);
    }
    throw GeminiRequestException(
      '$defaultErrorMessage ${lastError?.message ?? 'Unknown error'}',
    );
  }

  GenerativeModel _createModel(String modelName, String apiKey) =>
      GenerativeModel(
        model: modelName,
        apiKey: apiKey,
        generationConfig:
            GenerationConfig(responseMimeType: 'application/json'),
      );

  /// Creates a streaming-friendly model variant. We omit the JSON
  /// response-mime-type that the recommendation path uses, since chat replies
  /// are plain prose and forcing JSON makes the model wrap every answer in a
  /// code fence.
  GenerativeModel _createStreamingModel(String modelName, String apiKey) =>
      GenerativeModel(model: modelName, apiKey: apiKey);

  /// Streaming transport that mirrors [_request].
  ///
  /// Emits each chunk of text Gemini produces. The stream closes cleanly
  /// when the model finishes, and surfaces a [GeminiRequestException] as a
  /// [Stream.error] event when every model has been exhausted.
  Stream<String> _stream(
    String prompt,
    String busyMessage,
    String defaultErrorMessage,
  ) async* {
    final streamingModels = _resolveStreamingModels();
    if (streamingModels == null) {
      throw const GeminiConfigurationException(
        'Gemini API key is missing. Add GEMINI_API_KEY or GOOGLE_API_KEY to .env and restart the app.',
      );
    }

    GenerativeAIException? lastError;
    for (final model in streamingModels) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final stream = model.generateContentStream([Content.text(prompt)]);
          await for (final chunk in stream) {
            final text = chunk.text;
            if (text != null && text.isNotEmpty) {
              yield text;
            }
          }
          return;
        } on GenerativeAIException catch (error) {
          lastError = error;
          if (!_isTemporaryUnavailable(error) || attempt == 1) break;
          await Future<void>.delayed(Duration(seconds: attempt + 1));
        }
      }
    }

    if (lastError != null && _isTemporaryUnavailable(lastError)) {
      throw GeminiRequestException(busyMessage);
    }
    throw GeminiRequestException(
      '$defaultErrorMessage ${lastError?.message ?? 'Unknown error'}',
    );
  }

  /// Resolves the streaming model list. Mirrors [_resolveModels] but uses
  /// non-JSON models so chat replies are unforced plain text.
  List<GenerativeModel>? _resolveStreamingModels() {
    final apiKey =
        (dotenv.env['GEMINI_API_KEY'] ?? dotenv.env['GOOGLE_API_KEY'])?.trim();
    if (apiKey == null || apiKey.isEmpty || apiKey == 'YOUR_KEY') {
      return null;
    }
    return <GenerativeModel>[
      _createStreamingModel('gemini-3.5-flash', apiKey),
      _createStreamingModel('gemini-3.5-flash-lite', apiKey),
    ];
  }

  bool _isTemporaryUnavailable(GenerativeAIException error) {
    final message = error.message.toLowerCase();
    return message.contains('503') ||
        message.contains('unavailable') ||
        message.contains('high demand');
  }

  String _recommendationPrompt(UserProfile user, List<Scholarship> scholarships) => '''
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
