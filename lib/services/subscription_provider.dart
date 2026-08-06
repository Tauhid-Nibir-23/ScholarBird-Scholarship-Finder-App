/// App-wide subscription state provider.
///
/// Wraps [SubscriptionService.watch] in a [ChangeNotifier] so any widget
/// listening via `context.watch<SubscriptionProvider>()` (or `Selector`)
/// automatically rebuilds when Firestore updates the user's subscription
/// document â€” no app restart, no manual refetch, no duplicate streams.
///
/// Architecture overview:
///   â€¢  [SubscriptionService] â€” talks to Firestore + backend payment API.
///   â€¢  [SubscriptionProvider] â€” exposes a single, reactive view of the
///      current user's subscription to the entire widget tree. Firestore
///      is the source of truth; SharedPreferences is an offline cache so
///      the user remains premium across reloads even when offline.
///   â€¢  [PremiumGuard] / [UpgradeDialog] â€” declarative UI gate that
///      consults this provider before showing premium content.
///
/// The provider also exposes [refresh] so the upgrade screen can force a
/// re-read after a successful activation, even before Firestore's snapshot
/// listener catches up.
///
/// Local-only demo activation:
///   [activateLocalDemo] and [resetLocalDemo] toggle the user's premium
///   state and persist it to BOTH Firestore (canonical) and SharedPreferences
///   (offline cache). This keeps every premium-aware widget â€” drawer header,
///   profile card, manage-subscription page, premium banner â€” consistent
///   after activation, hot reload, app restart, or sign in on a new device.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/subscription_model.dart';
import 'subscription_service.dart';

/// Single source of truth for the signed-in user's subscription state.
class SubscriptionProvider extends ChangeNotifier {
  SubscriptionProvider({SubscriptionService? service})
      : _service = service ?? SubscriptionService();

  final SubscriptionService _service;

  StreamSubscription<SubscriptionModel>? _subscription;
  StreamSubscription<User?>? _authSubscription;
  SubscriptionModel _subscriptionModel =
      const SubscriptionModel(status: 'free');
  bool _isLoading = true;

  /// SharedPreferences key used to persist the local-only demo subscription.
  static const String _prefsKey = 'scholarbird.local_subscription.v1';

  /// `true` until the first snapshot from Firestore has been delivered.
  bool get isLoading => _isLoading;

  /// The latest subscription snapshot (defaults to a free-tier model).
  SubscriptionModel get subscription => _subscriptionModel;

  /// `true` when the user currently holds an active premium subscription.
  bool get isPremium => _subscriptionModel.isPremium;

  /// Plan identifier (`monthly` | `6months` | `yearly`) or `null` for free.
  String? get planId => _subscriptionModel.plan;

  /// Days remaining before the subscription expires (>= 0).
  int get daysRemaining => _subscriptionModel.daysRemaining;

  /// Expiry timestamp, if any.
  DateTime? get expiry => _subscriptionModel.expiry;

  /// Legacy flag kept for UI compatibility (always `true` since the static
  /// build does not contact a gateway at all).
  bool get isDemoMode => true;

  /// Begins listening to Firestore and hydrating any cached local-only demo
  /// subscription. Idempotent â€” calling it again restarts the underlying
  /// stream so it always points at the current signed-in user.
  void start() {
    _authSubscription ??= FirebaseAuth.instance.authStateChanges().listen((_) {
      _startForCurrentUser();
    });
    _startForCurrentUser();
  }

  /// Rebinds after Firebase restores, changes, or clears the signed-in user.
  /// This keeps all premium-aware screens synchronized after startup.
  void _startForCurrentUser() {
    _hydrateLocalDemo();
    _subscription?.cancel();
    _isLoading = true;
    notifyListeners();

    _subscription = _service.watch().listen(
      (model) {
        // Firestore is the source of truth. If the cached local demo
        // already claims premium but Firestore still says free (the common
        // case immediately after a demo activation, before our own write
        // round-trips back through the snapshot), keep the in-memory
        // premium state so the UI does not flicker. As soon as Firestore
        // confirms, we use the canonical record.
        if (model.status == 'free' && _subscriptionModel.isPremium) {
          // Hold the in-memory premium until the Firestore snapshot
          // catches up with the activation we just wrote.
        } else {
          _subscriptionModel = model;
        }
        _isLoading = false;
        notifyListeners();
      },
      onError: (Object error) {
        debugPrint('[SubscriptionProvider] watch error: $error');
        // Do not clobber an active local-only demo on a transient Firestore
        // failure â€” just stop showing the loading spinner.
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  /// Forces a one-shot re-read of the user's subscription document.
  Future<void> refresh() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _subscriptionModel = const SubscriptionModel(status: 'free');
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      _subscriptionModel = SubscriptionModel.fromMap(
          snapshot.data() ?? const <String, dynamic>{});
    } catch (error) {
      debugPrint('[SubscriptionProvider] refresh error: $error');
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Activates premium instantly and persists the new state to BOTH
  /// Firestore (canonical) and SharedPreferences (offline cache). After
  /// this call returns, every widget reading from the provider or from
  /// Firestore sees the user as premium â€” drawer header, profile card,
  /// manage-subscription page, and premium banner all update without
  /// requiring a restart or re-login.
  Future<void> activateLocalDemo({required SubscriptionPlan plan}) async {
    final now = DateTime.now();
    final expiry = now.add(Duration(days: plan.durationDays));
    final model = SubscriptionModel(
      status: 'premium',
      plan: plan.id,
      start: now,
      expiry: expiry,
      gateway: 'local_demo',
      paymentId: 'LOCAL_DEMO_${plan.id.toUpperCase()}',
      transactionId: 'LOCAL_DEMO_${now.millisecondsSinceEpoch}',
    );

    // 1) Optimistically update the in-memory model so the UI flips to
    //    premium immediately without waiting for the Firestore round-trip.
    _subscriptionModel = model;
    _isLoading = false;
    notifyListeners();

    // 2) Persist locally so reloads / cold starts keep the user premium
    //    until the Firestore listener delivers the canonical record.
    await _persistLocalDemo(model);

    // 3) Persist to Firestore â€” the single source of truth that every
    //    other widget reads from. This makes the drawer header, profile
    //    card, and manage-subscription page all show PRO consistently.
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set(model.toMap(), SetOptions(merge: true));
      } catch (error, st) {
        debugPrint('[SubscriptionProvider] activateLocalDemo firestore '
            'write failed: $error\n$st');
      }
    }
  }

  /// Drops the user back to the free tier. Mirrors [activateLocalDemo] â€”
  /// the in-memory state, the Firestore document, and the SharedPreferences
  /// cache are all updated together so nothing can drift out of sync.
  Future<void> resetLocalDemo() async {
    final model = const SubscriptionModel(status: 'free');

    // In-memory first so the UI flips immediately.
    _subscriptionModel = model;
    _isLoading = false;
    notifyListeners();

    // Clear the offline cache.
    await _clearLocalDemo();

    // Clear the canonical Firestore record. Using delete() would remove
    // unrelated profile fields, so we set the subscription fields back to
    // their free-tier defaults instead.
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set(model.toMap(), SetOptions(merge: true));
      } catch (error, st) {
        debugPrint('[SubscriptionProvider] resetLocalDemo firestore '
            'write failed: $error\n$st');
      }
    }
  }

  /// Restores a previously cached subscription so a cold start shows the
  /// user as premium until the Firestore snapshot confirms.
  Future<void> _hydrateLocalDemo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final restored = SubscriptionModel.fromStoredMap(map);
      if (restored.isPremium) {
        _subscriptionModel = restored;
      }
    } catch (error) {
      debugPrint('[SubscriptionProvider] hydrate local demo error: $error');
    }
  }

  /// Persists the supplied [model] (defaults to the current in-memory
  /// state) to SharedPreferences.
  Future<void> _persistLocalDemo([SubscriptionModel? model]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = (model ?? _subscriptionModel).toMap();
      await prefs.setString(_prefsKey, jsonEncode(payload));
    } catch (error) {
      debugPrint('[SubscriptionProvider] persist local demo error: $error');
    }
  }

  Future<void> _clearLocalDemo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (error) {
      debugPrint('[SubscriptionProvider] clear local demo error: $error');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
