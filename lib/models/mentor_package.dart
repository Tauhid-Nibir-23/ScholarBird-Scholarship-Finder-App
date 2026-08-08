/// A service package a mentor sells inside the Mentor Hub booking flow.
///
/// Packages live in the `mentor_packages` Firestore collection. Each
/// package belongs to one mentor ([mentorId]) and has a human-friendly
/// name, price, duration, and description.
library;

import 'package:flutter/foundation.dart';

@immutable
class MentorPackage {
  const MentorPackage({
    required this.id,
    required this.mentorId,
    required this.name,
    required this.description,
    required this.price,
    required this.durationMinutes,
    this.currency = 'USD',
    this.highlight = false,
  });

  final String id;
  final String mentorId;
  final String name;
  final String description;
  final double price;
  final int durationMinutes;
  final String currency;

  /// When true, the booking screen renders this package with a "Popular"
  /// badge. Used by the admin form to spotlight one package per mentor.
  final bool highlight;

  factory MentorPackage.fromMap(Map<String, dynamic> map) => MentorPackage(
        id: (map['id'] ?? '').toString(),
        mentorId: (map['mentorId'] ?? '').toString(),
        name: (map['name'] ?? '').toString(),
        description: (map['description'] ?? '').toString(),
        price: _double(map['price']),
        durationMinutes: _int(map['durationMinutes']),
        currency: (map['currency'] ?? 'USD').toString(),
        highlight: map['highlight'] == true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'mentorId': mentorId,
        'name': name,
        'description': description,
        'price': price,
        'durationMinutes': durationMinutes,
        'currency': currency,
        'highlight': highlight,
      };

  MentorPackage copyWith({
    String? id,
    String? mentorId,
    String? name,
    String? description,
    double? price,
    int? durationMinutes,
    String? currency,
    bool? highlight,
  }) =>
      MentorPackage(
        id: id ?? this.id,
        mentorId: mentorId ?? this.mentorId,
        name: name ?? this.name,
        description: description ?? this.description,
        price: price ?? this.price,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        currency: currency ?? this.currency,
        highlight: highlight ?? this.highlight,
      );

  /// Human-friendly duration label, e.g. "45 min", "1 hr 30 min".
  String get durationLabel {
    if (durationMinutes <= 0) return 'Self-paced';
    if (durationMinutes < 60) return '$durationMinutes min';
    final hours = durationMinutes ~/ 60;
    final rem = durationMinutes % 60;
    if (rem == 0) return '$hours hr';
    return '$hours hr $rem min';
  }

  static int _int(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  static double _double(Object? raw) {
    if (raw is double) return raw;
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0;
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MentorPackage && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// The default catalogue of packages a brand-new mentor gets seeded with.
/// Admins can edit, disable, or replace these from the management screen.
List<MentorPackage> defaultMentorPackages(String mentorId) => [
      MentorPackage(
        id: '$mentorId-pkg-basic',
        mentorId: mentorId,
        name: 'Basic Consultation',
        description:
            'A 30-minute introductory call to assess your goals, profile, and the right next step.',
        price: 0,
        durationMinutes: 30,
      ),
      MentorPackage(
        id: '$mentorId-pkg-cv',
        mentorId: mentorId,
        name: 'CV Review',
        description:
            'Detailed review of your academic CV with line-by-line feedback and a revised version.',
        price: 0,
        durationMinutes: 45,
      ),
      MentorPackage(
        id: '$mentorId-pkg-sop',
        mentorId: mentorId,
        name: 'SOP Review',
        description:
            'Two rounds of detailed edits on your Statement of Purpose with structural feedback.',
        price: 0,
        durationMinutes: 60,
        highlight: true,
      ),
      MentorPackage(
        id: '$mentorId-pkg-shortlist',
        mentorId: mentorId,
        name: 'Scholarship Shortlisting',
        description:
            'A curated list of 10–15 scholarships that match your profile, with deadlines and fit notes.',
        price: 0,
        durationMinutes: 45,
      ),
      MentorPackage(
        id: '$mentorId-pkg-university',
        mentorId: mentorId,
        name: 'University Selection',
        description:
            'Build a balanced university shortlist (reach / target / safety) with rationale per pick.',
        price: 0,
        durationMinutes: 60,
      ),
      MentorPackage(
        id: '$mentorId-pkg-application',
        mentorId: mentorId,
        name: 'Application Guidance',
        description:
            'End-to-end guidance for one application: documents, portals, recommendations, and follow-ups.',
        price: 0,
        durationMinutes: 90,
      ),
      MentorPackage(
        id: '$mentorId-pkg-interview',
        mentorId: mentorId,
        name: 'Interview Preparation',
        description:
            'Two mock interviews with recorded feedback and a personalised preparation plan.',
        price: 0,
        durationMinutes: 90,
      ),
      MentorPackage(
        id: '$mentorId-pkg-complete',
        mentorId: mentorId,
        name: 'Complete Scholarship Journey',
        description:
            'A multi-session mentorship covering everything from shortlisting to enrolment.',
        price: 0,
        durationMinutes: 600,
      ),
      MentorPackage(
        id: '$mentorId-pkg-visa',
        mentorId: mentorId,
        name: 'Visa Guidance',
        description:
            'Step-by-step visa preparation: document checklist, mock interview, and DS-160 review.',
        price: 0,
        durationMinutes: 60,
      ),
    ];
