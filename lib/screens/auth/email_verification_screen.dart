/// Screen that prompts the user to verify their email address.
///
/// Used both directly after sign-up and after a login attempt where the
/// account exists but the email has not yet been verified.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/email_verification_service.dart';
import '../../services/role_navigation.dart';

/// Reasons this screen may be shown — drives the headline copy.
enum EmailVerificationReason {
  /// Account was just created; verification email was just sent.
  justSignedUp,

  /// Existing account logs in but emailVerified is false.
  unverifiedLogin,
}

/// Self-contained screen that handles resend, re-check, and reverting to login.
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({
    required this.email,
    required this.reason,
    super.key,
  });

  /// Address that received the verification email; shown to the user.
  final String email;

  /// Whether we got here right after signup or after a login attempt.
  final EmailVerificationReason reason;

  /// Convenience push helper to keep call sites readable.
  static Future<T?> push<T>(
    BuildContext context, {
    required String email,
    required EmailVerificationReason reason,
  }) =>
      Navigator.of(context).pushNamed(
        '/verify-email',
        arguments: EmailVerificationScreenArgs(email: email, reason: reason),
      );

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final EmailVerificationService _service = EmailVerificationService.instance;

  bool _isBusy = false;
  String? _infoMessage;
  String? _errorMessage;

  @override
  void dispose() {
    // Don't tear down the shared service here — other screens may still
    // observe the cooldown notifier after we navigate away.
    super.dispose();
  }

  String get _title => widget.reason == EmailVerificationReason.justSignedUp
      ? 'Verify your email'
      : 'Email not verified';

  String get _headline => widget.reason == EmailVerificationReason.justSignedUp
      ? 'Your account has been created successfully.'
      : 'Your email address has not been verified yet.';

  String get _body => widget.reason == EmailVerificationReason.justSignedUp
      ? 'A verification email has been sent to your email address.\n\n'
          'Please verify your email before logging in.'
      : 'To keep your account secure, please confirm the verification email '
          'we sent to your address before signing in.';

  Future<void> _handleResend() async {
    if (_service.isResendLocked || _isBusy) return;

    setState(() {
      _isBusy = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final result = await _service.sendVerificationEmail();

    if (!mounted) return;
    setState(() {
      _isBusy = false;
      if (result.success) {
        _infoMessage =
            'A new verification email has been sent to ${widget.email}.';
      } else {
        _errorMessage = result.message;
      }
    });
  }

  Future<void> _handleIHaveVerified() async {
    if (_isBusy) return;

    setState(() {
      _isBusy = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      final verified = await _service.checkVerified();
      if (!mounted) return;

      if (verified) {
        // The user is already signed in (signup flow kept the session, login
        // flow signed in momentarily). Continue to the home route.
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          // Defensive fallback — should not normally happen, but keep the
          // user on a safe screen if their session vanished.
          _goToLogin();
          return;
        }
        final route = await RoleNavigation.routeForUser(user.uid);
        if (!mounted) return;
        Navigator.of(context).pushNamed(route);
        return;
      }

      setState(() {
        _errorMessage = 'Email is still not verified.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _verificationErrorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  void _goToLogin() {
    // Sign out in case the user is still authenticated (login flow path)
    // before dropping them back to the login screen.
    FirebaseAuth.instance.signOut();
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: widget.reason == EmailVerificationReason.unverifiedLogin
          ? AppBar(
              backgroundColor: const Color(0xFFF5F7FB),
              elevation: 0,
              automaticallyImplyLeading: false,
              title: const Text(
                'Verification Required',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              centerTitle: true,
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: size.height * 0.85),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),

                  // Hero icon
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF5B7AE8), Color(0xFF3D5AC1)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0052CC)
                                .withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.mark_email_unread_outlined,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Title
                  Text(
                    _title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Headline (success message)
                  Text(
                    _headline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Body explanation
                  Text(
                    _body,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF6B7A95),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Email chip
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(0xFFE5E7EB),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.mail_outline,
                            size: 16,
                            color: Color(0xFF5B7AE8),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              widget.email,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A2E),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Info / Error messages
                  if (_infoMessage != null)
                    _MessageBanner(
                      message: _infoMessage!,
                      color: const Color(0xFF10B981),
                      icon: Icons.check_circle_outline,
                    ),
                  if (_errorMessage != null)
                    Padding(
                      padding: EdgeInsets.only(top: _infoMessage != null ? 8 : 0),
                      child: _MessageBanner(
                        message: _errorMessage!,
                        color: colorScheme.error,
                        icon: Icons.error_outline,
                      ),
                    ),

                  const SizedBox(height: 8),

                  // Resend Email Button (with 60s countdown)
                  ValueListenableBuilder<bool>(
                    valueListenable: _service.cooldownActiveListenable,
                    builder: (context, isLocked, _) {
                      return ValueListenableBuilder<int>(
                        valueListenable: _service.cooldownRemainingListenable,
                        builder: (context, remaining, _) {
                          final label = isLocked
                              ? 'Resend available in ${remaining}s'
                              : 'Resend Email';
                          return _ActionButton(
                            label: label,
                            icon: Icons.refresh,
                            onPressed: (isLocked || _isBusy)
                                ? null
                                : _handleResend,
                            outlined: true,
                            busy: _isBusy && !isLocked,
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // I Have Verified Button
                  _ActionButton(
                    label: 'I Have Verified',
                    icon: Icons.verified_outlined,
                    onPressed: _isBusy ? null : _handleIHaveVerified,
                    primary: true,
                    busy: _isBusy,
                  ),
                  const SizedBox(height: 12),

                  // Back to Login Button
                  TextButton(
                    onPressed: _isBusy ? null : _goToLogin,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'Back to Login',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5B7AE8),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Help footer
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFE5E7EB),
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: Color(0xFF6B7A95),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Didn\'t get the email? Check your spam folder, or '
                            'wait a minute before requesting a new one.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7A95),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Used as `arguments` for the named route lookup in `main.dart`.
class EmailVerificationScreenArgs {
  const EmailVerificationScreenArgs({
    required this.email,
    required this.reason,
  });

  final String email;
  final EmailVerificationReason reason;
}

/// Pill-shaped banner for success/error feedback.
class _MessageBanner extends StatelessWidget {
  const _MessageBanner({
    required this.message,
    required this.color,
    required this.icon,
  });

  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: color,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Themed action button used on the verification screen.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.outlined = false,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool outlined;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final baseColor = const Color(0xFF5B7AE8);

    if (outlined) {
      return SizedBox(
        height: 52,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(baseColor),
                  ),
                )
              : Icon(icon, size: 18, color: disabled ? baseColor.withValues(alpha: 0.5) : baseColor),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: disabled ? baseColor.withValues(alpha: 0.5) : baseColor,
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: BorderSide(
              color: baseColor.withValues(alpha: disabled ? 0.3 : 0.6),
              width: 1.5,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Icon(icon, size: 18, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: primary
              ? baseColor
              : baseColor.withValues(alpha: 0.9),
          disabledBackgroundColor: baseColor.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: primary ? 3 : 0,
        ),
      ),
    );
  }
}

/// Translates thrown errors into a friendly message; mirrors the service-side
/// translation so the screen can also format errors raised during `checkVerified`.
String _verificationErrorMessage(Object error) {
  final raw = error.toString().toLowerCase();
  if (raw.contains('network') || raw.contains('socket')) {
    return 'Network error. Please check your connection and retry.';
  }
  if (raw.contains('requires-recent-login')) {
    return 'Your session has expired. Please log in again to continue.';
  }
  if (raw.contains('user-disabled')) {
    return 'This account has been disabled.';
  }
  return 'Could not check verification status. Please try again.';
}