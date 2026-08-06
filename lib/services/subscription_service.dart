/// Handles subscription state and backend payment requests for upgrades.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/subscription_model.dart';

/// Describes the payment gateway session returned by the backend.
class PaymentSessionResponse {
  const PaymentSessionResponse({
    required this.gatewayUrl,
    required this.transactionId,
    required this.status,
  });

  final String gatewayUrl;
  final String transactionId;
  final String status;
}

/// Represents the backend response returned after payment verification.
class PaymentValidationResult {
  const PaymentValidationResult({
    required this.status,
    required this.transactionId,
    this.validationId,
    this.amount,
    this.currency,
    this.raw = const {},
  });

  final String status;
  final String transactionId;
  final String? validationId;
  final String? amount;
  final String? currency;
  final Map<String, dynamic> raw;

  bool get isValid =>
      status.toUpperCase() == 'VALID' || status.toUpperCase() == 'VALIDATED';
  bool get isCancelled => status.toUpperCase() == 'CANCELLED';
  bool get isFailed =>
      status.toUpperCase() == 'FAILED' || status.toUpperCase() == 'INVALID';
}

/// Signals an expected payment or backend failure for the UI to present.
class PaymentException implements Exception {
  const PaymentException(
    this.message, {
    this.isNetworkError = false,
    this.isTimeout = false,
    this.isDuplicate = false,
  });

  final String message;
  final bool isNetworkError;
  final bool isTimeout;
  final bool isDuplicate;

  @override
  String toString() => message;
}

/// Reads subscription state from Firestore and coordinates payment validation.
class SubscriptionService {
  final _db = FirebaseFirestore.instance;

  /// Whether the current build uses the in-process direct activation flow.
  ///
  /// Reads the `DEMO_PAYMENT` env variable. Defaults to `true` so existing
  /// development setups work without any extra configuration.
  ///
  ///   • `DEMO_PAYMENT=true`  → calls `/api/payment/direct-activate` and
  ///     skips SSLCommerz / WebView entirely.
  ///   • `DEMO_PAYMENT=false` → reserved for a future production gateway.
  ///     The architecture is provider-agnostic so the rest of the app
  ///     keeps working unchanged.
  static bool get isDemoMode {
    final raw = dotenv.env['DEMO_PAYMENT']?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return true;
    if (raw == 'false' || raw == '0' || raw == 'no' || raw == 'off') {
      return false;
    }
    return true;
  }

  /// Streams the current user's subscription model from Firestore.
  Stream<SubscriptionModel> watch() {
    final u = FirebaseAuth.instance.currentUser;
    return u == null
        ? Stream.value(const SubscriptionModel(status: 'free'))
        : _db
            .collection('users')
            .doc(u.uid)
            .snapshots()
            .map((d) => SubscriptionModel.fromMap(d.data() ?? {}));
  }

  String get _baseUrl {
    final envUrl =
        (dotenv.env['PAYMENT_API_URL'] ?? dotenv.env['BACKEND_URL'])?.trim();
    if (envUrl != null && envUrl.isNotEmpty) {
      return envUrl.endsWith('/')
          ? envUrl.substring(0, envUrl.length - 1)
          : envUrl;
    }
    if (!kIsWeb) {
      try {
        if (Platform.isAndroid) {
          return 'http://10.0.2.2:8000';
        }
      } catch (_) {
        // Platform unavailable (e.g. unsupported web configuration) – fall
        // through to the localhost default below.
      }
    }
    return 'http://localhost:8000';
  }

  /// Requests a new payment session from the backend for the selected plan.
  Future<PaymentSessionResponse> createPaymentSession({
    required SubscriptionPlan plan,
    String? phone,
    String? address,
    String? city,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const PaymentException(
          'User must be logged in to upgrade subscription.');
    }

    final body = {
      'uid': user.uid,
      'plan': plan.id,
      'amount': plan.amount,
    };

    final responseMap = await _postJson('/payment/create', body);

    final gatewayUrl = responseMap['gateway_url']?.toString() ?? '';
    final transactionId = responseMap['transaction_id']?.toString() ?? '';

    if (gatewayUrl.isEmpty || transactionId.isEmpty) {
      throw const PaymentException(
          'Backend returned an invalid payment session response.');
    }

    return PaymentSessionResponse(
      gatewayUrl: gatewayUrl,
      transactionId: transactionId,
      status: 'CREATED',
    );
  }

  /// Activates premium directly through the backend without any external
  /// payment gateway (no SSLCommerz, no mock checkout page).
  ///
  /// Mirrors the demo flow: select a plan → tap Pay Now → Firestore updates →
  /// premium badge unlocks. The backend endpoint records a synthetic
  /// transaction under `users/{uid}/payments/` and returns the full subscription
  /// state for the UI to react to immediately.
  Future<Map<String, dynamic>> activatePremiumDirect({
    required SubscriptionPlan plan,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const PaymentException(
          'User must be logged in to upgrade subscription.');
    }

    final body = {
      'uid': user.uid,
      'plan': plan.id,
      'amount': plan.amount,
      'currency': 'BDT',
    };

    final responseMap = await _postJson('/api/payment/direct-activate', body);
    final status = responseMap['status']?.toString().toUpperCase() ?? '';
    if (status != 'PREMIUM') {
      throw PaymentException(
          'Backend could not activate premium: status=$status');
    }
    return responseMap;
  }

  /// Validates a completed transaction against the backend payment API.
  Future<PaymentValidationResult> validatePayment(String transactionId) async {
    if (transactionId.trim().isEmpty) {
      throw const PaymentException(
          'Transaction ID is required for validation.');
    }

    final body = {
      'transaction_id': transactionId.trim(),
    };

    final responseMap = await _postJson('/api/payment/validate', body);

    final status = responseMap['status']?.toString() ?? 'FAILED';
    final tranId = responseMap['transaction_id']?.toString() ?? transactionId;

    return PaymentValidationResult(
      status: status,
      transactionId: tranId,
      validationId: responseMap['validation_id']?.toString(),
      amount: responseMap['amount']?.toString(),
      currency: responseMap['currency']?.toString(),
      raw: responseMap,
    );
  }

  Future<Map<String, dynamic>> _postJson(
      String endpoint, Map<String, dynamic> body) async {
    final url = Uri.parse('$_baseUrl$endpoint');
    debugPrint('[PaymentService] _baseUrl=$_baseUrl endpoint=$endpoint');
    debugPrint('[PaymentService] POST $url body=$body');
    try {
      final response = await http
          .post(
            url,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));

      debugPrint('[PaymentService] ← ${response.statusCode} $url '
          'body=${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        throw const FormatException(
            'Server returned an unexpected JSON structure.');
      } else if (response.statusCode == 409) {
        throw const PaymentException(
          'A payment request is already in progress or duplicate. Please wait a moment before trying again.',
          isDuplicate: true,
        );
      } else {
        var message = 'Payment server error (${response.statusCode}).';
        try {
          final errMap = jsonDecode(response.body);
          if (errMap is Map && errMap.containsKey('detail')) {
            message = errMap['detail'].toString();
          }
        } catch (_) {}
        throw PaymentException(message);
      }
    } on http.ClientException catch (e, st) {
      debugPrint('[PaymentService] ClientException: $e\n$st');
      throw const PaymentException(
        'Unable to connect to payment backend server. Please check your internet connection and verify backend is running.',
        isNetworkError: true,
      );
    } on TimeoutException catch (e, st) {
      debugPrint('[PaymentService] TimeoutException: $e\n$st');
      throw const PaymentException(
        'The request to payment backend server timed out. Please try again.',
        isTimeout: true,
      );
    } on FormatException catch (e, st) {
      debugPrint('[PaymentService] FormatException: $e\n$st');
      throw PaymentException(
          'Invalid response from payment server: ${e.message}');
    } catch (e, st) {
      debugPrint('[PaymentService] Unexpected error: $e\n$st');
      if (e is PaymentException) rethrow;
      throw PaymentException('Payment request failed: ${e.toString()}');
    }
  }
}
