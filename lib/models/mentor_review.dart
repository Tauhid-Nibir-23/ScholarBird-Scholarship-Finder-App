/// A student review for a Mentor Hub booking.
///
/// Stored in the `mentor_reviews` Firestore collection. Reviews are
/// restricted to `completed` bookings to keep the marketplace honest.
/// A scheduled Firestore trigger (future backend task) can recompute the
/// aggregate `rating` and `totalReviews` fields on the parent mentor
/// document. Until that runs, the UI computes averages client-side.
library;

import 'package:flutter/foundation.dart';

@immutable
class MentorReview {
  const MentorReview({
    required this.id,
    required this.mentorId,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.review,
    required this.date,
    this.bookingId = '',
    this.country = '',
  });

  final String id;
  final String mentorId;
  final String userId;
  final String userName;
  final double rating; // 1..5
  final String review;
  final DateTime date;
  final String bookingId;
  final String country;

  factory MentorReview.fromMap(Map<String, dynamic> map) => MentorReview(
        id: (map['id'] ?? '').toString(),
        mentorId: (map['mentorId'] ?? '').toString(),
        userId: (map['userId'] ?? '').toString(),
        userName: (map['userName'] ?? '').toString(),
        rating: _rating(map['rating']),
        review: (map['review'] ?? '').toString(),
        date: _date(map['date']),
        bookingId: (map['bookingId'] ?? '').toString(),
        country: (map['country'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'mentorId': mentorId,
        'userId': userId,
        'userName': userName,
        'rating': rating,
        'review': review,
        'date': date.toIso8601String(),
        'bookingId': bookingId,
        'country': country,
      };

  static double _rating(Object? raw) {
    if (raw is num) {
      final value = raw.toDouble();
      if (value.isNaN || value.isInfinite) return 0;
      return value.clamp(0.0, 5.0);
    }
    if (raw is String) return double.tryParse(raw) ?? 0;
    return 0;
  }

  static DateTime _date(Object? raw) {
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return DateTime.now();
  }
}
