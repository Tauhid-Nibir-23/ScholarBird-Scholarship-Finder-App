/// Creates and validates scholarship applications.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ApplicationAccess {
  const ApplicationAccess({
    this.isLoggedIn = false,
    this.isPremium = false,
    this.alreadyApplied = false,
    this.missing = const [],
  });

  final bool isLoggedIn;
  final bool isPremium;
  final bool alreadyApplied;
  final List<String> missing;

  bool get canApply =>
      isLoggedIn && isPremium && missing.isEmpty && !alreadyApplied;
}

class ApplicationService {
  ApplicationService._();
  static final instance = ApplicationService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _applicationId(String uid, String scholarshipId) =>
      '${uid}_$scholarshipId';

  Future<ApplicationAccess> checkAccess(String scholarshipId) async {
    final user = _auth.currentUser;
    if (user == null) return const ApplicationAccess();
    final userRef = _db.collection('users').doc(user.uid);
    final results = await Future.wait(
        [userRef.get(), userRef.collection('documents').get()]);
    final profile =
        (results[0] as DocumentSnapshot<Map<String, dynamic>>).data() ?? {};
    final documents = (results[1] as QuerySnapshot<Map<String, dynamic>>).docs;
    final applicationId = _applicationId(user.uid, scholarshipId);
    final applied =
        await userRef.collection('applications').doc(applicationId).get();
    final expiry = _asDate(profile['subscriptionExpiry']);
    final premium =
        profile['subscriptionStatus']?.toString().toLowerCase() == 'premium' &&
            (expiry == null || expiry.isAfter(DateTime.now()));
    return ApplicationAccess(
      isLoggedIn: true,
      isPremium: premium,
      alreadyApplied: applied.exists,
      missing: _missing(profile, documents, user),
    );
  }

  Future<String> submit(Map<String, dynamic> scholarship) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Please login first');
    final scholarshipId = scholarship['id']?.toString().trim() ?? '';
    if (scholarshipId.isEmpty) throw StateError('Scholarship id is missing');
    final access = await checkAccess(scholarshipId);
    if (!access.isPremium)
      throw StateError('Premium subscription is required to apply.');
    if (access.missing.isNotEmpty)
      throw StateError(
          'Complete your profile before applying: ${access.missing.join(', ')}.');
    if (access.alreadyApplied) return (scholarship['link'] ?? '').toString();
    final id = _applicationId(user.uid, scholarshipId);
    final userRef = _db.collection('users').doc(user.uid);
    final appRef = _db.collection('applications').doc(id);
    final userAppRef = userRef.collection('applications').doc(id);
    final scholarshipRef = _db.collection('scholarships').doc(scholarshipId);
    final profile = (await userRef.get()).data() ?? {};
    final docs = await userRef.collection('documents').get();
    final record = <String, dynamic>{
      'applicationId': id,
      'userId': user.uid,
      'scholarshipId': scholarshipId,
      'scholarshipTitle': scholarship['title']?.toString() ?? '',
      'university': scholarship['university']?.toString() ?? '',
      'country': scholarship['country']?.toString() ?? '',
      'deadline': scholarship['deadline'],
      'status': 'IN_PROGRESS',
      'currentStep': 0,
      'progress': 0,
      'checklist': {
        'passport': false,
        'cv': false,
        'sop': false,
        'recommendationLetter': false,
        'transcript': false,
        'ielts': false,
        'researchProposal': false
      },
      'appliedDate': FieldValue.serverTimestamp(),
      'lastUpdated': FieldValue.serverTimestamp(),
      'notes': '',
      'adminNotes': '',
      'profileSnapshot': profile,
      'documentsSnapshot': {for (final doc in docs.docs) doc.id: doc.data()},
      'title': scholarship['title']?.toString() ?? '',
      'degree': scholarship['degree']?.toString() ?? '',
      'image': scholarship['image']?.toString() ?? '',
    };
    await _db.runTransaction((transaction) async {
      if ((await transaction.get(appRef)).exists) return;
      transaction.set(appRef, record);
      transaction.set(userAppRef, record);
      transaction.update(
          scholarshipRef, {'applicationCount': FieldValue.increment(1)});
    });
    return (scholarship['link'] ?? '').toString();
  }

  Future<void> updateTracking(String applicationId,
      {bool? submitted, Map<String, bool>? checklist}) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Please login first');
    final updates = <String, dynamic>{
      'lastUpdated': FieldValue.serverTimestamp()
    };
    if (submitted == true)
      updates.addAll({
        'status': 'SUBMITTED',
        'currentStep': 2,
        'progress': 30,
        'submittedAt': FieldValue.serverTimestamp()
      });
    if (checklist != null) {
      final completed = checklist.values.where((value) => value).length;
      updates.addAll({
        'checklist': checklist,
        'currentStep': completed == checklist.length ? 1 : 0,
        'progress': completed == checklist.length
            ? 25
            : (completed * 25 / checklist.length).round()
      });
    }
    final batch = _db.batch();
    batch.update(_db.collection('applications').doc(applicationId), updates);
    batch.update(
        _db
            .collection('users')
            .doc(user.uid)
            .collection('applications')
            .doc(applicationId),
        updates);
    await batch.commit();
  }

  List<String> _missing(Map<String, dynamic> profile,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> documents, User user) {
    final fields = <String, String>{
      'Full Name': _value(profile, 'name', user.displayName),
      'Email': _value(profile, 'email', user.email),
      'Phone': _value(profile, 'phone'),
      'Country': _value(profile, 'country'),
      'Nationality': _value(profile, 'nationality'),
      'Date of Birth': _value(profile, 'dateOfBirth'),
      'Gender': _value(profile, 'gender'),
      'Current Education': _value(profile, 'currentEducation',
          profile['education'] ?? profile['degree']),
      'CGPA': _meaningful(profile['cgpa']) ? 'present' : '',
      'University/College': _value(profile, 'university'),
      'Graduation Year':
          _meaningful(profile['graduationYear']) ? 'present' : '',
    };
    final uploaded = <String>{
      for (final document in documents)
        if (_value(document.data(), 'fileName', document.data()['downloadUrl'])
            .isNotEmpty)
          document.id,
    };
    for (final entry in const {
      'cv': 'CV',
      'sop': 'SOP',
      'transcript': 'Transcript'
    }.entries) {
      if (!uploaded.contains(entry.key)) fields[entry.value] = '';
    }
    return fields.entries
        .where((entry) => entry.value.trim().isEmpty)
        .map((entry) => entry.key)
        .toList();
  }

  String _value(Map<String, dynamic> map, String key, [Object? fallback]) =>
      (map[key] ?? fallback ?? '').toString().trim();
  bool _meaningful(Object? value) =>
      value != null &&
      value.toString().trim().isNotEmpty &&
      value.toString() != '0';
  DateTime? _asDate(Object? value) => value is Timestamp
      ? value.toDate()
      : value is DateTime
          ? value
          : DateTime.tryParse('${value ?? ''}');
}
