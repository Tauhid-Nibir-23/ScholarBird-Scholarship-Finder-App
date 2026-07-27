import 'package:cloud_firestore/cloud_firestore.dart';

class RoleNavigation {
  const RoleNavigation._();

  static Future<String> routeForUser(String uid) async {
    try {
      final userDocument =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final userData = userDocument.data();

      if (userData?['role'] == 'admin') {
        return '/admin';
      }
    } catch (_) {
      // Preserve the existing user experience if a role cannot be read.
    }

    return '/home';
  }
}
