import 'package:cloud_firestore/cloud_firestore.dart';

class SubscriptionModel {
  const SubscriptionModel(
      {required this.status,
      this.plan,
      this.start,
      this.expiry,
      this.gateway,
      this.paymentId,
      this.transactionId});
  factory SubscriptionModel.fromMap(Map<String, dynamic> map) =>
      SubscriptionModel(
          status: (map['subscriptionStatus'] ?? 'free').toString(),
          plan: map['subscriptionPlan']?.toString(),
          start: _date(map['subscriptionStart']),
          expiry: _date(map['subscriptionExpiry']),
          gateway: map['paymentGateway']?.toString(),
          paymentId: map['lastPaymentId']?.toString(),
          transactionId: map['lastTransactionId']?.toString());
  final String status;
  final String? plan;
  final DateTime? start;
  final DateTime? expiry;
  final String? gateway;
  final String? paymentId;
  final String? transactionId;
  bool get isPremium =>
      status == 'premium' && expiry != null && expiry!.isAfter(DateTime.now());
  int get daysRemaining => expiry == null
      ? 0
      : expiry!.difference(DateTime.now()).inDays.clamp(0, 9999).toInt();
  static DateTime? _date(dynamic value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
          ? value
          : DateTime.tryParse('${value ?? ''}');
}

enum SubscriptionPlan { monthly, sixMonths, yearly }

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
}
