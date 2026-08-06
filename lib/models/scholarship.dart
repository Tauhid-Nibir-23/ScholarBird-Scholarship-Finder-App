/// Firestore-backed scholarship record used throughout the app.
import 'package:cloud_firestore/cloud_firestore.dart';

/// Normalized scholarship data mapped from Firestore documents.
class Scholarship {
  const Scholarship({
    required this.id,
    required this.title,
    required this.country,
    required this.deadline,
    required this.field,
    required this.minCgpa,
    required this.eligibility,
    required this.fundingType,
  });

  /// Creates a scholarship model from a Firestore document snapshot.
  factory Scholarship.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final rawCgpa = data['minCGPA'] ?? data['minCgpa'];
    return Scholarship(
      id: doc.id,
      title: _text(data['title']),
      country: _text(data['country']),
      deadline: _text(data['deadline']),
      field: _text(data['field']),
      minCgpa:
          rawCgpa is num ? rawCgpa.toDouble() : double.tryParse(_text(rawCgpa)),
      eligibility: _text(data['eligibility']),
      fundingType: _text(data['fundingType']).isNotEmpty
          ? _text(data['fundingType'])
          : _text(data['amount']),
    );
  }

  final String id;
  final String title;
  final String country;
  final String deadline;
  final String field;
  final double? minCgpa;
  final String eligibility;
  final String fundingType;

  /// Serializes the model into the structure expected by Gemini.
  Map<String, dynamic> toGeminiMap() => {
        'title': title,
        'country': country,
        'deadline': deadline,
        'field': field,
        'minCGPA': minCgpa,
        'eligibility': eligibility,
        'fundingType': fundingType,
      };

  static String _text(dynamic value) => value?.toString().trim() ?? '';
}
