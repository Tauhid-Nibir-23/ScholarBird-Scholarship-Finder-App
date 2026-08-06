/// Wraps Firebase email-verification actions with friendly error messages and
/// a shared 60-second resend cooldown.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Outcome of a verification attempt, surfaced to the UI layer.
class EmailVerificationResult {
  const EmailVerificationResult({required this.success, this.message});

  final bool success;
  final String? message;
}

/// Translates FirebaseAuth errors into a single user-facing message.
String _verificationErrorMessage(Object error) {
  final raw = error.toString().toLowerCase();
  const fallback = 'Something went wrong. Please try again.';

  if (raw.contains('too-many-requests') || raw.contains('too many')) {
    return 'Too many attempts. Please wait a moment before trying again.';
  }
  if (raw.contains('network') || raw.contains('socket')) {
    return 'Network error. Please check your connection and retry.';
  }
  if (raw.contains('user-not-found')) {
    return 'No account found for this session. Please log in again.';
  }
  if (raw.contains('user-disabled')) {
    return 'This account has been disabled.';
  }
  if (raw.contains('requires-recent-login')) {
    return 'Your session has expired. Please log in again to continue.';
  }
  if (raw.contains('invalid-email')) {
    return 'The email address is not valid.';
  }
  if (raw.contains('configuration-not-found')) {
    return 'Firebase Authentication is not configured correctly.';
  }

  // Some Firebase platforms embed the error code in a different position;
  // surface the first short line when nothing else matches.
  final firstLine = error.toString().split('\n').first.trim();
  if (firstLine.isNotEmpty && firstLine.length < 120) {
    return firstLine;
  }
  return fallback;
}

/// Single source of truth for sending verification emails and checking the
/// `emailVerified` flag, including a shared resend cooldown.
class EmailVerificationService {
  EmailVerificationService._() {
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_cooldownRemaining.value > 0) {
        _cooldownRemaining.value--;
        if (_cooldownRemaining.value == 0) {
          _cooldownActive.value = false;
        }
      }
    });
  }

  /// Shared instance used by both the signup and login flows.
  static final EmailVerificationService instance = EmailVerificationService._();

  /// How long the user must wait between resend attempts.
  static const Duration resendCooldown = Duration(seconds: 60);

  final FirebaseAuth _auth = FirebaseAuth.instance;

  final ValueNotifier<int> _cooldownRemaining = ValueNotifier<int>(0);
  final ValueNotifier<bool> _cooldownActive = ValueNotifier<bool>(false);

  Timer? _cooldownTimer;

  /// Notifier exposing the seconds remaining in the current cooldown.
  ValueListenable<int> get cooldownRemainingListenable => _cooldownRemaining;

  /// Notifier exposing whether the resend button is currently disabled.
  ValueListenable<bool> get cooldownActiveListenable => _cooldownActive;

  /// Whether the resend button should currently be disabled.
  bool get isResendLocked => _cooldownActive.value;

  /// Seconds remaining before resend becomes available again.
  int get cooldownSecondsRemaining => _cooldownRemaining.value;

  /// Reloads the currently signed-in user and reports whether their email is
  /// verified. Returns `false` if there is no signed-in user.
  Future<bool> checkVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  /// Sends (or resends) the verification email to the currently signed-in user.
  /// Activates a 60-second cooldown on success.
  Future<EmailVerificationResult> sendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null) {
      return const EmailVerificationResult(
        success: false,
        message: 'Your session has expired. Please log in again.',
      );
    }

    if (_cooldownActive.value) {
      return EmailVerificationResult(
        success: false,
        message:
            'Please wait ${_cooldownRemaining.value} seconds before requesting another email.',
      );
    }

    try {
      await user.sendEmailVerification();
      _startCooldown();
      return const EmailVerificationResult(success: true);
    } catch (e) {
      return EmailVerificationResult(
        success: false,
        message: _verificationErrorMessage(e),
      );
    }
  }

  void _startCooldown() {
    _cooldownRemaining.value = resendCooldown.inSeconds;
    _cooldownActive.value = true;
  }

  /// Manually resets the cooldown; useful for tests and forced unlock paths.
  void resetCooldown() {
    _cooldownRemaining.value = 0;
    _cooldownActive.value = false;
  }

  /// Stops the internal timer; safe to call multiple times.
  void dispose() {
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
  }
}