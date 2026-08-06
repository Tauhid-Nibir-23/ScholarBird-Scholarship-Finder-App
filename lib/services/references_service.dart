/// Coordinates Firestore reads/writes for the user academic references
/// subcollection. Records live at `users/{uid}/references/{referenceId}`.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/reference_model.dart';

/// Coordinates Firestore reads and writes for academic references.
class ReferencesService {
  ReferencesService._();

  /// Shared singleton instance.
  static final ReferencesService instance = ReferencesService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Returns the references subcollection for the current user, or null
  /// when no user is signed in.
  CollectionReference<Map<String, dynamic>>? _collection() {
    final user = _auth.currentUser;
    if (user == null) return null;
    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('references');
  }

  /// Streams the full list of references for the current user. The list is
  /// empty when the user has not saved any references yet.
  Stream<List<ReferenceModel>> streamReferences() {
    final collection = _collection();
    if (collection == null) {
      return Stream<List<ReferenceModel>>.value(const <ReferenceModel>[]);
    }
    return collection.snapshots().map((snapshot) => snapshot.docs
        .map(ReferenceModel.fromFirestore)
        .toList(growable: false));
  }

  /// Persists (creates or updates) a single reference record.
  Future<void> saveReference(ReferenceModel reference) async {
    final collection = _collection();
    if (collection == null) {
      throw StateError('No authenticated user available to save reference.');
    }
    await collection.doc(reference.id).set(
          reference.toMap(),
          SetOptions(merge: true),
        );
  }

  /// Deletes the reference with the given [referenceId].
  Future<void> deleteReference(String referenceId) async {
    final collection = _collection();
    if (collection == null) return;
    await collection.doc(referenceId).delete();
  }
}
