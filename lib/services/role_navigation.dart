/// Resolves the first route after authentication based on the stored user role.
import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads the signed-in user's role and maps it to the correct landing route.
class RoleNavigation {
  const RoleNavigation._();

  /// Returns the route for the authenticated user, defaulting to `/home`.
  static Future<String> routeForUser(String uid) async {
    try {
      final userDocument =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final userData = userDocument.data();

      if (userData?['role'] == 'admin') {
        return '/admin';
      }
    } catch (e) {
      // Do not grant access on an unreadable profile. The caller safely
      // falls back to the normal user landing route.
      // ignore: avoid_print
      print('Unable to resolve user role: $e');
    }

    return '/home';
  }
}
