/// Handles per-user saved scholarship persistence and live query helpers.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Materialized saved-scholarship data with the originating document id.
class SavedScholarshipRef {
  const SavedScholarshipRef({
    required this.id,
    required this.savedAt,
    required this.data,
  });

  final String id;
  final DateTime savedAt;
  final Map<String, dynamic> data;

  Map<String, dynamic> toScholarshipMap() => <String, dynamic>{
        ...data,
        'id': id,
      };
}

/// Coordinates Firestore reads and writes for the saved scholarships feature.
class SavedScholarshipsService {
  SavedScholarshipsService._();

  static final SavedScholarshipsService instance = SavedScholarshipsService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>>? _collection() {
    final user = _auth.currentUser;
    if (user == null) return null;
    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('savedScholarships');
  }

  DocumentReference<Map<String, dynamic>>? _doc(String scholarshipId) {
    final collection = _collection();
    if (collection == null || scholarshipId.isEmpty) return null;
    return collection.doc(scholarshipId);
  }

  /// Emits whether the current user has saved the given scholarship.
  Stream<bool> watchSavedStatus(String scholarshipId) {
    final doc = _doc(scholarshipId);
    if (doc == null) return Stream.value(false);
    return doc
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) => snapshot.exists);
  }

  /// Streams the current user's saved scholarships ordered by most recent save.
  Stream<List<SavedScholarshipRef>> watchSavedScholarships() {
    final collection = _collection();
    if (collection == null) return Stream.value(const <SavedScholarshipRef>[]);

    return collection
        .orderBy('savedAt', descending: true)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            final savedAtValue = data['savedAt'];
            final savedAt = savedAtValue is Timestamp
                ? savedAtValue.toDate()
                : savedAtValue is DateTime
                    ? savedAtValue
                    : DateTime.fromMillisecondsSinceEpoch(0);
            return SavedScholarshipRef(
              id: doc.id,
              savedAt: savedAt,
              data: Map<String, dynamic>.from(data),
            );
          }).toList(),
        );
  }

  /// Persists a scholarship snapshot into the signed-in user's saved list.
  Future<void> saveScholarship(Map<String, dynamic> scholarship) async {
    final scholarshipId = (scholarship['id'] ?? '').toString();
    final doc = _doc(scholarshipId);
    if (doc == null || scholarshipId.isEmpty) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invalid-argument',
        message: 'Missing scholarship id',
      );
    }

    await doc.set(<String, dynamic>{
      'savedAt': FieldValue.serverTimestamp(),
      'title': (scholarship['title'] ?? '').toString(),
      'country': (scholarship['country'] ?? '').toString(),
      'degree': (scholarship['degree'] ?? '').toString(),
      'field': (scholarship['field'] ?? '').toString(),
      'deadline': (scholarship['deadline'] ?? '').toString(),
      'amount': (scholarship['amount'] ?? '').toString(),
      'image': (scholarship['image'] ?? '').toString(),
      'imageUrl': (scholarship['imageUrl'] ?? '').toString(),
      'university': (scholarship['university'] ?? '').toString(),
      'source': (scholarship['source'] ?? '').toString(),
    }, SetOptions(merge: true));
  }

  /// Removes a scholarship from the signed-in user's saved list.
  Future<void> unsaveScholarship(String scholarshipId) async {
    final doc = _doc(scholarshipId);
    if (doc == null || scholarshipId.isEmpty) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invalid-argument',
        message: 'Missing scholarship id',
      );
    }

    await doc.delete();
  }

  /// Saves or removes a scholarship depending on whether it already exists.
  Future<void> toggleSaved(Map<String, dynamic> scholarship) async {
    final scholarshipId = (scholarship['id'] ?? '').toString();
    final doc = _doc(scholarshipId);
    if (doc == null || scholarshipId.isEmpty) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invalid-argument',
        message: 'Missing scholarship id',
      );
    }

    final snapshot =
        await doc.get(const GetOptions(source: Source.serverAndCache));
    if (snapshot.exists) {
      await doc.delete();
      return;
    }

    await saveScholarship(scholarship);
  }

  /// Deletes every saved scholarship for the current user in one batch.
  Future<void> clearAllSaved() async {
    final collection = _collection();
    if (collection == null) return;
    final snapshot =
        await collection.get(const GetOptions(source: Source.serverAndCache));
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// Deletes a set of saved scholarships in a single batch request.
  Future<void> removeMany(Iterable<String> scholarshipIds) async {
    final collection = _collection();
    if (collection == null) return;

    final ids = scholarshipIds.where((id) => id.trim().isNotEmpty).toSet();
    if (ids.isEmpty) return;

    final batch = _firestore.batch();
    for (final id in ids) {
      batch.delete(collection.doc(id));
    }
    await batch.commit();
  }

  /// Resolves saved scholarships with a Firestore fallback for missing fields.
  ///
  /// The merged map also exposes the parent document's image under the
  /// ``parentImage`` / ``parentImageUrl`` aliases so downstream widgets
  /// (e.g. ``SavedScholarshipCard``) can prefer the latest parent
  /// image over the snapshot captured at save time. The aliases are
  /// only populated when the parent document actually carries an
  /// image — never with empty strings — so the consumer's "no image"
  /// guard remains authoritative.
  Stream<List<Map<String, dynamic>>> watchSavedScholarshipsWithFallback() =>
      watchSavedScholarships().asyncMap((savedItems) async {
        final resolved = <Map<String, dynamic>>[];
        for (final savedItem in savedItems) {
          final scholarshipDoc =
              await _firestore.collection('scholarships').doc(savedItem.id).get(
                    const GetOptions(source: Source.serverAndCache),
                  );
          final parentData = scholarshipDoc.data() ?? const <String, dynamic>{};
          String? parentImage;
          for (final key in const ['image', 'imageUrl']) {
            final raw = parentData[key];
            if (raw == null) continue;
            final trimmed = raw.toString().trim();
            if (trimmed.isNotEmpty) {
              parentImage = trimmed;
              break;
            }
          }
          resolved.add(<String, dynamic>{
            ...savedItem.data,
            if (parentData.isNotEmpty) ...parentData,
            if (parentImage != null) 'parentImage': parentImage,
            'id': savedItem.id,
            'savedAt': savedItem.data['savedAt'],
          });
        }
        return resolved;
      });
}
