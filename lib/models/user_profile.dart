import 'package:cloud_firestore/cloud_firestore.dart';

/// The fields Gemini needs to make a scholarship recommendation.
class UserProfile {
  const UserProfile({
    required this.degree,
    required this.cgpa,
    required this.country,
    required this.skills,
    required this.preferredStudyCountries,
    required this.academicBackground,
  });

  factory UserProfile.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return UserProfile(
      degree: _text(data['education']).isNotEmpty
          ? _text(data['education'])
          : _text(data['degree']),
      cgpa: _number(data['cgpa']),
      country: _text(data['country']),
      skills: _strings(data['skills']).isNotEmpty
          ? _strings(data['skills'])
          : _strings(data['interestedFields']),
      preferredStudyCountries: _strings(data['preferredCountries']),
      academicBackground: [
        _text(data['department']),
        _text(data['university']),
        _text(data['targetDegree']),
      ].where((value) => value.isNotEmpty).join(', '),
    );
  }

  final String degree;
  final double? cgpa;
  final String country;
  final List<String> skills;
  final List<String> preferredStudyCountries;
  final String academicBackground;

  bool get hasEnoughInformation =>
      degree.isNotEmpty ||
      cgpa != null ||
      skills.isNotEmpty ||
      academicBackground.isNotEmpty;

  static String _text(dynamic value) => value?.toString().trim() ?? '';

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(_text(value));
  }

  static List<String> _strings(dynamic value) {
    if (value is Iterable) {
      return value.map(_text).where((item) => item.isNotEmpty).toList();
    }
    final text = _text(value);
    return text.isEmpty
        ? <String>[]
        : text.split(',').map((e) => e.trim()).toList();
  }
}
