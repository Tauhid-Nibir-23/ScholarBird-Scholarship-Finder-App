import 'dart:convert';

import '../services/gemini_service.dart';
import 'scholarship_type.dart';
import 'sop_draft.dart';
import 'sop_prompt_params.dart';

/// Generates an SOP draft from a [SopPromptParams] payload.
///
/// The service is stateless — it does not touch Firestore. Persistence is
/// the responsibility of [AiHistoryService] so this class stays focused on
/// prompt construction + response parsing.
class SopGeneratorService {
  SopGeneratorService({GeminiService? gemini})
      : _gemini = gemini ?? GeminiService();

  final GeminiService _gemini;

  /// Returns a parsed [SopDraft] for the supplied parameters.
  Future<SopDraft> generate({
    required String userId,
    required SopPromptParams params,
    required String draftId,
    required DateTime now,
    String existingTitle = '',
  }) async {
    final raw = await _gemini.generateRaw(_prompt(params));
    final parsed = _parse(raw);
    final title = existingTitle.trim().isNotEmpty
        ? existingTitle.trim()
        : _suggestedTitle(params);
    return SopDraft(
      id: draftId,
      userId: userId,
      title: title,
      body: parsed.body,
      type: params.type,
      createdAt: now,
      targetProgramme: params.targetProgramme,
      targetUniversity: params.targetUniversity,
      targetField: params.targetField,
      scholarshipName: params.scholarshipName,
      wordCount: parsed.wordCount,
      missingFields: parsed.missingFields,
      regenerations: 0,
      notes: params.additionalNotes,
    );
  }

  String _suggestedTitle(SopPromptParams params) {
    final programme = params.targetProgramme.trim();
    if (programme.isNotEmpty) return '${params.type.label} • $programme';
    if (params.targetField.trim().isNotEmpty) {
      return '${params.type.label} • ${params.targetField.trim()}';
    }
    return params.type.label;
  }

  String _prompt(SopPromptParams params) {
    final paramsJson = jsonEncode(params.toJson());
    final wordTarget = params.wordCountTarget.clamp(300, 1500);
    return '''
You are ScholarBird's SOP co-author. Write a sincere, specific Statement of
Purpose for the applicant. The applicant has provided context under
APPLICANT_CONTEXT; do not invent degrees, awards, jobs, publications,
volunteer work or personal stories that are not described there. If the
context is silent on something the applicant would normally mention (for
example research experience, publications or volunteer work), acknowledge
the gap in a single neutral sentence at the natural point in the narrative
rather than fabricating the detail.

CONTEXT (JSON):
$paramsJson

SCHOLARSHIP FRAMING (${params.type.id}):
${params.type.description}

INSTRUCTIONS:
- Target length: ~$wordTarget words (±10%).
- Tone: first person, confident, specific. Avoid clichés like
  "ever since I was a child" or "passionate about".
- Structure: opening motivation paragraph → academic background → relevant
  experience (documents / references cited naturally) → programme fit →
  future impact aligned with the scholarship framing → concise close.
- When a reference is available, mention at most one by name + relationship.
- When documents are listed, treat them as supporting evidence but do not
  quote verbatim from them.
- When the applicant has flagged missing information, weave in a short
  acknowledgement (for example "I am still completing my final-year
  research project, which I expect to submit before enrolment.") instead of
  inventing it.
- Do not use markdown headings. Use plain paragraphs separated by blank
  lines.

OUTPUT FORMAT — return strict JSON only:
{
  "title": "<short, programme-specific title>",
  "body": "<full SOP text in plain paragraphs>",
  "wordCount": <integer word count of the body>,
  "missingFields": ["<field 1>", "<field 2>"]
}
''';
  }

  _ParsedDraft _parse(String? responseText) {
    if (responseText == null || responseText.trim().isEmpty) {
      throw const GeminiRequestException(
          'Gemini returned an empty SOP draft.');
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
          'Gemini returned an unreadable SOP response: ${error.message}');
    }
    final body = (data['body'] as String?)?.trim() ?? '';
    if (body.isEmpty) {
      throw const GeminiRequestException(
          'Gemini returned an SOP without a body.');
    }
    final missing = (data['missingFields'] as List?)
            ?.whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList() ??
        const <String>[];
    final reportedWords = (data['wordCount'] as num?)?.toInt() ?? 0;
    final actualWords = _wordCount(body);
    return _ParsedDraft(
      body: body,
      wordCount: reportedWords > 0 ? reportedWords : actualWords,
      missingFields: missing,
    );
  }

  static int _wordCount(String body) {
    final tokens = body
        .split(RegExp(r'\s+'))
        .where((token) => token.trim().isNotEmpty)
        .toList();
    return tokens.length;
  }
}

class _ParsedDraft {
  const _ParsedDraft({
    required this.body,
    required this.wordCount,
    required this.missingFields,
  });

  final String body;
  final int wordCount;
  final List<String> missingFields;
}

// Suppress "unused import" warning if ScholarshipType is only used inside
// the dynamic prompt string at the bottom of the file.
// ignore: unused_element
String _typeLabel(ScholarshipType type) => type.label;