/// Domain model for the paid mentor marketplace (the new "Mentor Hub").
///
/// This model is intentionally separate from the legacy [Mentor] class used
/// by the Reference Point feature. The two features live side-by-side:
///
/// * `mentors` Firestore collection — paid mentors (this class).
/// * `mentors` Firestore collection — was previously used for faculty
///   references; that data is still served by [Mentor] and the
///   Reference Point screen and is **never** touched by this class.
///
/// Fields are Firestore-friendly: every field is optional where it makes
/// sense, and [MentorProfile.fromMap] deserialises a document without
/// throwing on missing keys.
library;

import 'package:flutter/foundation.dart';

/// A paid mentor surfaced in the Mentor Hub marketplace.
@immutable
class MentorProfile {
  const MentorProfile({
    required this.id,
    required this.name,
    this.profilePhoto,
    this.designation = '',
    this.university = '',
    this.country = '',
    this.education = const <String>[],
    this.expertise = const <String>[],
    this.yearsExperience = 0,
    this.languages = const <String>[],
    this.bio = '',
    this.whatsapp = '',
    this.email = '',
    this.hourlyPrice = 0,
    this.packagePrice = 0,
    this.currency = 'USD',
    this.rating = 0,
    this.totalReviews = 0,
    this.successRate = 0,
    this.studentsHelped = 0,
    this.responseTime = '',
    this.availability = '',
    this.featured = false,
    this.verified = false,
    this.premiumOnly = false,
    this.testimonials = const <MentorTestimonial>[],
    this.disabled = false,
  });

  /// Stable Firestore document id.
  final String id;
  final String name;
  final String? profilePhoto;
  final String designation;
  final String university;
  final String country;
  final List<String> education;
  final List<String> expertise;
  final int yearsExperience;
  final List<String> languages;
  final String bio;
  final String whatsapp;
  final String email;
  final double hourlyPrice;
  final double packagePrice;
  final String currency;
  final double rating;
  final int totalReviews;
  final int successRate; // 0..100
  final int studentsHelped;
  final String responseTime; // e.g. "Usually within 2 hours"
  final String availability; // free text or status
  final bool featured;
  final bool verified;
  final bool premiumOnly;

  /// Optional static testimonials surfaced on the detail screen before any
  /// real reviews are written.
  final List<MentorTestimonial> testimonials;

  /// Soft-disable flag — admin can take a mentor offline without deleting.
  final bool disabled;

  /// Deserialise from a Firestore document map. Unknown keys are ignored.
  factory MentorProfile.fromMap(Map<String, dynamic> map) {
    final testimonialsRaw = map['testimonials'];
    final testimonials = <MentorTestimonial>[];
    if (testimonialsRaw is List) {
      for (final entry in testimonialsRaw) {
        if (entry is Map) {
          testimonials.add(MentorTestimonial.fromMap(
              entry.map((k, v) => MapEntry(k.toString(), v))));
        }
      }
    }
    return MentorProfile(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      profilePhoto: map['profilePhoto'] as String?,
      designation: (map['designation'] ?? '').toString(),
      university: (map['university'] ?? '').toString(),
      country: (map['country'] ?? '').toString(),
      education: _stringList(map['education']),
      expertise: _stringList(map['expertise']),
      yearsExperience: _intOrZero(map['yearsExperience']),
      languages: _stringList(map['languages']),
      bio: (map['bio'] ?? '').toString(),
      whatsapp: (map['whatsapp'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      hourlyPrice: _doubleOrZero(map['hourlyPrice']),
      packagePrice: _doubleOrZero(map['packagePrice']),
      currency: (map['currency'] ?? 'USD').toString(),
      rating: _doubleOrZero(map['rating']),
      totalReviews: _intOrZero(map['totalReviews']),
      successRate: _intOrZero(map['successRate']),
      studentsHelped: _intOrZero(map['studentsHelped']),
      responseTime: (map['responseTime'] ?? '').toString(),
      availability: (map['availability'] ?? '').toString(),
      featured: map['featured'] == true,
      verified: map['verified'] == true,
      premiumOnly: map['premiumOnly'] == true,
      testimonials: testimonials,
      disabled: map['disabled'] == true,
    );
  }

  /// Convert to a Firestore-friendly map. Use [withId] when the caller
  /// supplies its own id (admin forms do this).
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'profilePhoto': profilePhoto,
        'designation': designation,
        'university': university,
        'country': country,
        'education': education,
        'expertise': expertise,
        'yearsExperience': yearsExperience,
        'languages': languages,
        'bio': bio,
        'whatsapp': whatsapp,
        'email': email,
        'hourlyPrice': hourlyPrice,
        'packagePrice': packagePrice,
        'currency': currency,
        'rating': rating,
        'totalReviews': totalReviews,
        'successRate': successRate,
        'studentsHelped': studentsHelped,
        'responseTime': responseTime,
        'availability': availability,
        'featured': featured,
        'verified': verified,
        'premiumOnly': premiumOnly,
        'testimonials': [
          for (final t in testimonials) t.toMap(),
        ],
        'disabled': disabled,
        'updatedAt': DateTime.now().toIso8601String(),
      };

  /// Convenience for immutable updates (e.g. admin edits).
  MentorProfile copyWith({
    String? id,
    String? name,
    String? profilePhoto,
    String? designation,
    String? university,
    String? country,
    List<String>? education,
    List<String>? expertise,
    int? yearsExperience,
    List<String>? languages,
    String? bio,
    String? whatsapp,
    String? email,
    double? hourlyPrice,
    double? packagePrice,
    String? currency,
    double? rating,
    int? totalReviews,
    int? successRate,
    int? studentsHelped,
    String? responseTime,
    String? availability,
    bool? featured,
    bool? verified,
    bool? premiumOnly,
    List<MentorTestimonial>? testimonials,
    bool? disabled,
  }) =>
      MentorProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        profilePhoto: profilePhoto ?? this.profilePhoto,
        designation: designation ?? this.designation,
        university: university ?? this.university,
        country: country ?? this.country,
        education: education ?? this.education,
        expertise: expertise ?? this.expertise,
        yearsExperience: yearsExperience ?? this.yearsExperience,
        languages: languages ?? this.languages,
        bio: bio ?? this.bio,
        whatsapp: whatsapp ?? this.whatsapp,
        email: email ?? this.email,
        hourlyPrice: hourlyPrice ?? this.hourlyPrice,
        packagePrice: packagePrice ?? this.packagePrice,
        currency: currency ?? this.currency,
        rating: rating ?? this.rating,
        totalReviews: totalReviews ?? this.totalReviews,
        successRate: successRate ?? this.successRate,
        studentsHelped: studentsHelped ?? this.studentsHelped,
        responseTime: responseTime ?? this.responseTime,
        availability: availability ?? this.availability,
        featured: featured ?? this.featured,
        verified: verified ?? this.verified,
        premiumOnly: premiumOnly ?? this.premiumOnly,
        testimonials: testimonials ?? this.testimonials,
        disabled: disabled ?? this.disabled,
      );

  /// True when any free-text field contains [query] (case-insensitive).
  bool matchesQuery(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    final haystack = <String>[
      name,
      designation,
      university,
      country,
      bio,
      email,
      availability,
      responseTime,
      ...expertise,
      ...languages,
      ...education,
    ].map((s) => s.toLowerCase()).toList();
    for (final value in haystack) {
      if (value.contains(needle)) return true;
    }
    return false;
  }

  static List<String> _stringList(Object? raw) {
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  static int _intOrZero(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  static double _doubleOrZero(Object? raw) {
    if (raw is double) return raw;
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0;
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is MentorProfile && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// A static testimonial bundled with a [MentorProfile]. These seed the
/// detail screen; once real reviews start arriving in `mentor_reviews`,
/// the UI shows both lists.
@immutable
class MentorTestimonial {
  const MentorTestimonial({
    required this.author,
    required this.quote,
    this.country = '',
    this.rating = 5,
  });

  final String author;
  final String quote;
  final String country;
  final double rating;

  factory MentorTestimonial.fromMap(Map<String, dynamic> map) =>
      MentorTestimonial(
        author: (map['author'] ?? '').toString(),
        quote: (map['quote'] ?? '').toString(),
        country: (map['country'] ?? '').toString(),
        rating: (map['rating'] is num)
            ? (map['rating'] as num).toDouble()
            : 5.0,
      );

  Map<String, dynamic> toMap() => {
        'author': author,
        'quote': quote,
        'country': country,
        'rating': rating,
      };
}