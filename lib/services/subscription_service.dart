import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/subscription_model.dart';

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

class SubscriptionService {
  final _db = FirebaseFirestore.instance;

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
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://localhost:8000';
  }

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
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(url);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response =
          await request.close().timeout(const Duration(seconds: 20));

      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(responseBody);
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
          final errMap = jsonDecode(responseBody);
          if (errMap is Map && errMap.containsKey('detail')) {
            message = errMap['detail'].toString();
          }
        } catch (_) {}
        throw PaymentException(message);
      }
    } on SocketException {
      throw const PaymentException(
        'Unable to connect to payment backend server. Please check your internet connection and verify backend is running.',
        isNetworkError: true,
      );
    } on TimeoutException {
      throw const PaymentException(
        'The request to payment backend server timed out. Please try again.',
        isTimeout: true,
      );
    } on HandshakeException {
      throw const PaymentException(
          'Secure connection to payment backend server failed.');
    } on FormatException catch (e) {
      throw PaymentException(
          'Invalid response from payment server: ${e.message}');
    } catch (e) {
      if (e is PaymentException) rethrow;
      throw PaymentException('Payment request failed: ${e.toString()}');
    } finally {
      client.close();
    }
  }
}
