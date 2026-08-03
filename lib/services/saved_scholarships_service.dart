import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

class SavedScholarshipsService {
  SavedScholarshipsService._();

  static final SavedScholarshipsService instance = SavedScholarshipsService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>>? _collection() {
    final user = _auth.currentUser;
    if (user == null) return null;
    return _firestore.collection('users').doc(user.uid).collection('savedScholarships');
  }

  DocumentReference<Map<String, dynamic>>? _doc(String scholarshipId) {
    final collection = _collection();
    if (collection == null || scholarshipId.isEmpty) return null;
    return collection.doc(scholarshipId);
  }

  Stream<bool> watchSavedStatus(String scholarshipId) {
    final doc = _doc(scholarshipId);
    if (doc == null) return Stream.value(false);
    return doc.snapshots(includeMetadataChanges: true).map((snapshot) => snapshot.exists);
  }

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

    final snapshot = await doc.get(const GetOptions(source: Source.serverAndCache));
    if (snapshot.exists) {
      await doc.delete();
      return;
    }

    await saveScholarship(scholarship);
  }

  Future<void> clearAllSaved() async {
    final collection = _collection();
    if (collection == null) return;
    final snapshot = await collection.get(const GetOptions(source: Source.serverAndCache));
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

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

  Stream<List<Map<String, dynamic>>> watchSavedScholarshipsWithFallback() {
    return watchSavedScholarships().asyncMap((savedItems) async {
      final resolved = <Map<String, dynamic>>[];
      for (final savedItem in savedItems) {
        final scholarshipDoc = await _firestore.collection('scholarships').doc(savedItem.id).get(
              const GetOptions(source: Source.serverAndCache),
            );
        resolved.add(<String, dynamic>{
          ...savedItem.data,
          if (scholarshipDoc.data() != null) ...scholarshipDoc.data()!,
          'id': savedItem.id,
          'savedAt': savedItem.data['savedAt'],
        });
      }
      return resolved;
    });
  }
}
