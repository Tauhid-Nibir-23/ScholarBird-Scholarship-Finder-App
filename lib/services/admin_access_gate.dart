import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Blocks both signed-out and non-admin users from rendering admin content.
///
/// This is deliberately a live document stream: demoting an open admin takes
/// effect immediately instead of leaving a stale dashboard on screen.
class AdminAccessGate extends StatelessWidget {
  const AdminAccessGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, auth) {
        final user = auth.data;
        if (auth.connectionState == ConnectionState.waiting) {
          return const _AdminGateLoading();
        }
        if (user == null) return const _AdminAccessDenied(signedOut: true);
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
          builder: (context, profile) {
            if (profile.connectionState == ConnectionState.waiting) {
              return const _AdminGateLoading();
            }
            if (profile.hasError || profile.data?.data()?['role'] != 'admin') {
              return const _AdminAccessDenied();
            }
            return child;
          },
        );
      },
    );
  }
}

class _AdminGateLoading extends StatelessWidget {
  const _AdminGateLoading();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}

class _AdminAccessDenied extends StatelessWidget {
  const _AdminAccessDenied({this.signedOut = false});
  final bool signedOut;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 12),
              Text(signedOut ? 'Please sign in to continue.' : 'Admin access required.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
                  signedOut ? '/login' : '/home',
                  (_) => false,
                ),
                child: Text(signedOut ? 'Go to login' : 'Go to home'),
              ),
            ]),
          ),
        ),
      );
}
