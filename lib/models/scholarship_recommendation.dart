class ScholarshipRecommendation {
  const ScholarshipRecommendation({
    required this.scholarshipName,
    required this.matchProbability,
    required this.reason,
    this.country = '',
  });

  final String scholarshipName;
  final String matchProbability;
  final String reason;
  final String country;

  factory ScholarshipRecommendation.fromJson(Map<String, dynamic> json) =>
      ScholarshipRecommendation(
        scholarshipName: (json['scholarshipName'] ?? '').toString().trim(),
        matchProbability: (json['matchProbability'] ?? '').toString().trim(),
        reason: (json['reason'] ?? '').toString().trim(),
      );

  ScholarshipRecommendation withCountry(String value) => ScholarshipRecommendation(
        scholarshipName: scholarshipName,
        matchProbability: matchProbability,
        reason: reason,
        country: value,
      );
}
