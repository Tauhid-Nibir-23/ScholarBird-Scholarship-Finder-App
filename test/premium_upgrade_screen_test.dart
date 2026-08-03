import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ScholarBird/models/subscription_model.dart';
import 'package:ScholarBird/services/subscription_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SubscriptionModel Tests', () {
    test('SubscriptionPlan enum attributes are accurate', () {
      expect(SubscriptionPlan.monthly.id, 'monthly');
      expect(SubscriptionPlan.monthly.amount, 299);
      expect(SubscriptionPlan.monthly.label, 'Monthly');

      expect(SubscriptionPlan.sixMonths.id, '6months');
      expect(SubscriptionPlan.sixMonths.amount, 1299);
      expect(SubscriptionPlan.sixMonths.label, '6 Months');

      expect(SubscriptionPlan.yearly.id, 'yearly');
      expect(SubscriptionPlan.yearly.amount, 2499);
      expect(SubscriptionPlan.yearly.label, 'Yearly');
    });

    test('PaymentValidationResult getters evaluate validity correctly', () {
      const validResult = PaymentValidationResult(
        status: 'VALIDATED',
        transactionId: 'SB-MONT-1234',
        amount: '299.00',
        currency: 'BDT',
      );
      expect(validResult.isValid, isTrue);
      expect(validResult.isCancelled, isFalse);
      expect(validResult.isFailed, isFalse);

      const cancelledResult = PaymentValidationResult(
        status: 'CANCELLED',
        transactionId: 'SB-MONT-1234',
      );
      expect(cancelledResult.isValid, isFalse);
      expect(cancelledResult.isCancelled, isTrue);
      expect(cancelledResult.isFailed, isFalse);

      const failedResult = PaymentValidationResult(
        status: 'FAILED',
        transactionId: 'SB-MONT-1234',
      );
      expect(failedResult.isValid, isFalse);
      expect(failedResult.isFailed, isTrue);
    });
  });
}
