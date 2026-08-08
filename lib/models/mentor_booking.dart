/// Booking records for the Mentor Hub marketplace.
///
/// Stored in the `mentor_bookings` Firestore collection. The booking
/// status field follows the project lifecycle:
///
/// * `pending_payment` — package chosen, payment not yet completed.
/// * `confirmed` — mentor confirmed the slot (post-payment).
/// * `completed` — session finished, eligible for review.
/// * `cancelled` — either party cancelled.
library;

import 'package:flutter/foundation.dart';

enum MentorBookingStatus {
  pendingPayment,
  confirmed,
  completed,
  cancelled,
  refunded,
}

extension MentorBookingStatusX on MentorBookingStatus {
  String get value {
    switch (this) {
      case MentorBookingStatus.pendingPayment:
        return 'pending_payment';
      case MentorBookingStatus.confirmed:
        return 'confirmed';
      case MentorBookingStatus.completed:
        return 'completed';
      case MentorBookingStatus.cancelled:
        return 'cancelled';
      case MentorBookingStatus.refunded:
        return 'refunded';
    }
  }

  String get label {
    switch (this) {
      case MentorBookingStatus.pendingPayment:
        return 'Awaiting payment';
      case MentorBookingStatus.confirmed:
        return 'Confirmed';
      case MentorBookingStatus.completed:
        return 'Completed';
      case MentorBookingStatus.cancelled:
        return 'Cancelled';
      case MentorBookingStatus.refunded:
        return 'Refunded';
    }
  }

  static MentorBookingStatus fromString(String? raw) {
    switch (raw) {
      case 'confirmed':
        return MentorBookingStatus.confirmed;
      case 'completed':
        return MentorBookingStatus.completed;
      case 'cancelled':
        return MentorBookingStatus.cancelled;
      case 'refunded':
        return MentorBookingStatus.refunded;
      case 'pending_payment':
      default:
        return MentorBookingStatus.pendingPayment;
    }
  }
}

@immutable
class MentorBooking {
  const MentorBooking({
    required this.id,
    required this.mentorId,
    required this.userId,
    required this.packageId,
    required this.packageName,
    required this.price,
    required this.currency,
    required this.status,
    required this.createdAt,
    this.scheduledFor,
    this.notes = '',
    this.mentorName = '',
    this.userName = '',
    this.durationMinutes = 0,
  });

  final String id;
  final String mentorId;
  final String userId;
  final String packageId;
  final String packageName;
  final double price;
  final String currency;
  final MentorBookingStatus status;
  final DateTime createdAt;
  final DateTime? scheduledFor;
  final String notes;
  final String mentorName;
  final String userName;
  final int durationMinutes;

  factory MentorBooking.fromMap(Map<String, dynamic> map) => MentorBooking(
        id: (map['id'] ?? '').toString(),
        mentorId: (map['mentorId'] ?? '').toString(),
        userId: (map['userId'] ?? '').toString(),
        packageId: (map['packageId'] ?? '').toString(),
        packageName: (map['packageName'] ?? '').toString(),
        price: _double(map['price']),
        currency: (map['currency'] ?? 'USD').toString(),
        status: MentorBookingStatusX.fromString(map['status'] as String?),
        createdAt: _date(map['createdAt']),
        scheduledFor: _dateOrNull(map['scheduledFor']),
        notes: (map['notes'] ?? '').toString(),
        mentorName: (map['mentorName'] ?? '').toString(),
        userName: (map['userName'] ?? '').toString(),
        durationMinutes: _int(map['durationMinutes']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'mentorId': mentorId,
        'userId': userId,
        'packageId': packageId,
        'packageName': packageName,
        'price': price,
        'currency': currency,
        'status': status.value,
        'createdAt': createdAt.toIso8601String(),
        'scheduledFor': scheduledFor?.toIso8601String(),
        'notes': notes,
        'mentorName': mentorName,
        'userName': userName,
        'durationMinutes': durationMinutes,
      };

  MentorBooking copyWith({
    MentorBookingStatus? status,
    DateTime? scheduledFor,
    String? notes,
  }) =>
      MentorBooking(
        id: id,
        mentorId: mentorId,
        userId: userId,
        packageId: packageId,
        packageName: packageName,
        price: price,
        currency: currency,
        status: status ?? this.status,
        createdAt: createdAt,
        scheduledFor: scheduledFor ?? this.scheduledFor,
        notes: notes ?? this.notes,
        mentorName: mentorName,
        userName: userName,
        durationMinutes: durationMinutes,
      );

  static double _double(Object? raw) {
    if (raw is double) return raw;
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0;
    return 0;
  }

  static int _int(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  static DateTime _date(Object? raw) {
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return DateTime.now();
  }

  static DateTime? _dateOrNull(Object? raw) {
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return null;
  }
}

/// A free 5-minute introductory call request. Stored alongside regular
/// bookings (`mentor_bookings`) but tagged with `type: 'free_call'` so
/// reports can separate them.
@immutable
class MentorFreeCall {
  const MentorFreeCall({
    required this.id,
    required this.mentorId,
    required this.userId,
    required this.status,
    required this.createdAt,
    this.scheduledFor,
    this.topic = '',
    this.mentorName = '',
    this.userName = '',
  });

  final String id;
  final String mentorId;
  final String userId;
  final MentorFreeCallStatus status;
  final DateTime createdAt;
  final DateTime? scheduledFor;
  final String topic;
  final String mentorName;
  final String userName;

  factory MentorFreeCall.fromMap(Map<String, dynamic> map) => MentorFreeCall(
        id: (map['id'] ?? '').toString(),
        mentorId: (map['mentorId'] ?? '').toString(),
        userId: (map['userId'] ?? '').toString(),
        status: MentorFreeCallStatusX.fromString(map['status'] as String?),
        createdAt: _date(map['createdAt']),
        scheduledFor: _dateOrNull(map['scheduledFor']),
        topic: (map['topic'] ?? '').toString(),
        mentorName: (map['mentorName'] ?? '').toString(),
        userName: (map['userName'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'mentorId': mentorId,
        'userId': userId,
        'status': status.value,
        'createdAt': createdAt.toIso8601String(),
        'scheduledFor': scheduledFor?.toIso8601String(),
        'topic': topic,
        'mentorName': mentorName,
        'userName': userName,
        'type': 'free_call',
      };

  static DateTime _date(Object? raw) {
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return DateTime.now();
  }

  static DateTime? _dateOrNull(Object? raw) {
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return null;
  }
}

enum MentorFreeCallStatus {
  requested,
  accepted,
  scheduled,
  completed,
  declined,
  expired,
}

extension MentorFreeCallStatusX on MentorFreeCallStatus {
  String get value {
    switch (this) {
      case MentorFreeCallStatus.requested:
        return 'requested';
      case MentorFreeCallStatus.accepted:
        return 'accepted';
      case MentorFreeCallStatus.scheduled:
        return 'scheduled';
      case MentorFreeCallStatus.completed:
        return 'completed';
      case MentorFreeCallStatus.declined:
        return 'declined';
      case MentorFreeCallStatus.expired:
        return 'expired';
    }
  }

  String get label {
    switch (this) {
      case MentorFreeCallStatus.requested:
        return 'Request sent';
      case MentorFreeCallStatus.accepted:
        return 'Mentor accepted';
      case MentorFreeCallStatus.scheduled:
        return 'Scheduled';
      case MentorFreeCallStatus.completed:
        return 'Completed';
      case MentorFreeCallStatus.declined:
        return 'Declined';
      case MentorFreeCallStatus.expired:
        return 'Expired';
    }
  }

  static MentorFreeCallStatus fromString(String? raw) {
    switch (raw) {
      case 'accepted':
        return MentorFreeCallStatus.accepted;
      case 'scheduled':
        return MentorFreeCallStatus.scheduled;
      case 'completed':
        return MentorFreeCallStatus.completed;
      case 'declined':
        return MentorFreeCallStatus.declined;
      case 'expired':
        return MentorFreeCallStatus.expired;
      case 'requested':
      default:
        return MentorFreeCallStatus.requested;
    }
  }
}
