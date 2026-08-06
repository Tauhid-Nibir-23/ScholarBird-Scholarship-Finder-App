/// Recommendation payload returned by the AI advisor flow.
///
/// Keeps the generated score separate from the resolved scholarship data.
class ScholarshipRecommendation {
  const ScholarshipRecommendation({
    required this.scholarshipName,
    required this.matchProbability,
    required this.reason,
    this.country = '',
    this.scholarshipId = '',
    this.scholarshipData,
  });

  /// Creates a recommendation from the Gemini response payload.
  factory ScholarshipRecommendation.fromJson(Map<String, dynamic> json) =>
      ScholarshipRecommendation(
        scholarshipName: (json['scholarshipName'] ?? '').toString().trim(),
        matchProbability: (json['matchProbability'] ?? '').toString().trim(),
        reason: (json['reason'] ?? '').toString().trim(),
      );

  final String scholarshipName;
  final String matchProbability;
  final String reason;
  final String country;
  final String scholarshipId;
  final Map<String, dynamic>? scholarshipData;

  /// Returns the same recommendation enriched with Firestore scholarship data.
  ScholarshipRecommendation withScholarship({
    required String country,
    required String scholarshipId,
    Map<String, dynamic>? scholarshipData,
  }) =>
      ScholarshipRecommendation(
        scholarshipName: scholarshipName,
        matchProbability: matchProbability,
        reason: reason,
        country: country,
        scholarshipId: scholarshipId,
        scholarshipData: scholarshipData,
      );
}
