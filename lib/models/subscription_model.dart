/// Subscription state stored under the signed-in user's profile.
import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents the user's subscription tier and expiry information.
class SubscriptionModel {
  const SubscriptionModel({
    required this.status,
    this.plan,
    this.start,
    this.expiry,
    this.gateway,
    this.paymentId,
    this.transactionId,
  });

  /// Creates a subscription model from a Firestore map.
  factory SubscriptionModel.fromMap(Map<String, dynamic> map) =>
      SubscriptionModel(
        status: (map['subscriptionStatus'] ?? 'free').toString(),
        plan: map['subscriptionPlan']?.toString(),
        start: _date(map['subscriptionStart']),
        expiry: _date(map['subscriptionExpiry']),
        gateway: map['paymentGateway']?.toString(),
        paymentId: map['lastPaymentId']?.toString(),
        transactionId: map['lastTransactionId']?.toString(),
      );

  /// Restores a model that was persisted via [toMap] / SharedPreferences.
  factory SubscriptionModel.fromStoredMap(Map<String, dynamic> map) =>
      SubscriptionModel(
        status: (map['subscriptionStatus'] ?? 'free').toString(),
        plan: map['subscriptionPlan']?.toString(),
        start: _date(map['subscriptionStart']),
        expiry: _date(map['subscriptionExpiry']),
        gateway: map['paymentGateway']?.toString(),
        paymentId: map['lastPaymentId']?.toString(),
        transactionId: map['lastTransactionId']?.toString(),
      );

  final String status;
  final String? plan;
  final DateTime? start;
  final DateTime? expiry;
  final String? gateway;
  final String? paymentId;
  final String? transactionId;

  /// Indicates whether the subscription is active and premium.
  bool get isPremium =>
      status == 'premium' && expiry != null && expiry!.isAfter(DateTime.now());

  /// Returns the number of days remaining until expiry.
  int get daysRemaining => expiry == null
      ? 0
      : expiry!.difference(DateTime.now()).inDays.clamp(0, 9999).toInt();

  /// Returns a copy of this model with the provided fields replaced.
  SubscriptionModel copyWith({
    String? status,
    String? plan,
    DateTime? start,
    DateTime? expiry,
    String? gateway,
    String? paymentId,
    String? transactionId,
  }) =>
      SubscriptionModel(
        status: status ?? this.status,
        plan: plan ?? this.plan,
        start: start ?? this.start,
        expiry: expiry ?? this.expiry,
        gateway: gateway ?? this.gateway,
        paymentId: paymentId ?? this.paymentId,
        transactionId: transactionId ?? this.transactionId,
      );

  /// Serialises this model to a plain map for SharedPreferences / offline
  /// persistence. Inverse of [fromStoredMap].
  Map<String, dynamic> toMap() => {
        'subscriptionStatus': status,
        'subscriptionPlan': plan,
        'subscriptionStart': start?.toIso8601String(),
        'subscriptionExpiry': expiry?.toIso8601String(),
        'paymentGateway': gateway,
        'lastPaymentId': paymentId,
        'lastTransactionId': transactionId,
      };

  static DateTime? _date(dynamic value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
          ? value
          : DateTime.tryParse('${value ?? ''}');
}

/// Supported subscription durations offered by the upgrade flow.
enum SubscriptionPlan { monthly, sixMonths, yearly }

/// Exposes stable identifiers and pricing metadata for each plan.
extension SubscriptionPlanInfo on SubscriptionPlan {
  String get id => this == SubscriptionPlan.monthly
      ? 'monthly'
      : this == SubscriptionPlan.sixMonths
          ? '6months'
          : 'yearly';

  String get label => this == SubscriptionPlan.monthly
      ? 'Monthly'
      : this == SubscriptionPlan.sixMonths
          ? '6 Months'
          : 'Yearly';

  int get amount => this == SubscriptionPlan.monthly
      ? 299
      : this == SubscriptionPlan.sixMonths
          ? 1299
          : 2499;

  /// Subscription duration in days, used for the local-only demo activation.
  int get durationDays => this == SubscriptionPlan.monthly
      ? 30
      : this == SubscriptionPlan.sixMonths
          ? 180
          : 365;
}

