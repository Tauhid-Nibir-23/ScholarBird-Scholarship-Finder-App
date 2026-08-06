import 'package:cloud_firestore/cloud_firestore.dart';

import '../profile_analysis/profile_analysis_report.dart';
import 'sop_draft.dart';

/// Persists AI Hub drafts (currently SOPs) to Firestore.
///
/// Storage layout:
///   users/{uid}/aiHub/sops/{draftId}
///   users/{uid}/aiHub/profileAnalyses/{analysisId}
///
/// Keeping the layout flat under `aiHub` means future AI Hub features
/// (chat threads, profile analysis reports) can each have their own
/// subcollection without colliding.
class AiHistoryService {
  AiHistoryService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _sopCollection(String userId) =>
      _firestore.collection('users').doc(userId).collection('aiHub').doc('sops')
          .collection('items');

  CollectionReference<Map<String, dynamic>> _analysisCollection(String userId) =>
      _firestore
          .collection('users')
          .doc(userId)
          .collection('aiHub')
          .doc('profileAnalyses')
          .collection('items');

  /// Streams the user's SOP history, newest first.
  Stream<List<SopDraftRecord>> streamSopDrafts(String userId) {
    return _sopCollection(userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => SopDraftRecord(
                  id: doc.id,
                  data: doc.data(),
                  createdAt: (doc.data()['createdAt'] as Timestamp?)?.toDate() ??
                      DateTime.now(),
                ))
            .toList());
  }

  /// Persists a draft. Returns the document id (always equal to [draft.id]
  /// when provided so callers can rebuild the same document reference).
  Future<String> saveSopDraft({
    required String userId,
    required SopDraft draft,
  }) async {
    final payload = SopDraftRecord.fromDraft(draft, now: DateTime.now());
    await _sopCollection(userId).doc(draft.id).set(payload, SetOptions(merge: true));
    return draft.id;
  }

  /// Increments the regeneration counter so the UI can warn after several
  /// regenerations (helps prevent runaway token usage).
  Future<void> bumpRegenerations({
    required String userId,
    required String draftId,
  }) async {
    await _sopCollection(userId).doc(draftId).update({
      'regenerations': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes a draft.
  Future<void> deleteSopDraft({
    required String userId,
    required String draftId,
  }) async {
    await _sopCollection(userId).doc(draftId).delete();
  }

  /// Reads a single draft (used by the PDF generator when re-opening a
  /// history entry).
  Future<SopDraftRecord?> getSopDraft({
    required String userId,
    required String draftId,
  }) async {
    final snapshot = await _sopCollection(userId).doc(draftId).get();
    if (!snapshot.exists) return null;
    final data = snapshot.data() ?? const <String, dynamic>{};
    return SopDraftRecord(
      id: snapshot.id,
      data: data,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // ---------------------------------------------------------------------------
  // Profile analysis history
  // ---------------------------------------------------------------------------

  /// Streams the user's profile analysis history, newest first.
  Stream<List<ProfileAnalysisRecord>> streamProfileAnalyses(String userId) =>
      _analysisCollection(userId)
          .orderBy('generatedAt', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => ProfileAnalysisRecord(
                    id: doc.id,
                    data: doc.data(),
                    createdAt: (doc.data()['createdAt'] as Timestamp?)?.toDate() ??
                        DateTime.now(),
                  ))
              .toList());

  /// Persists a profile analysis. Returns the document id (always equal to
  /// the report's id so the UI can rebuild the same reference).
  Future<String> saveProfileAnalysis({
    required String userId,
    required ProfileAnalysisReport report,
  }) async {
    final payload = ProfileAnalysisRecord.fromReport(report);
    await _analysisCollection(userId)
        .doc(report.id)
        .set(payload, SetOptions(merge: true));
    return report.id;
  }

  /// Reads a single profile analysis record (used when re-opening a history
  /// entry — not yet surfaced in UI but kept symmetric with SOPs).
  Future<ProfileAnalysisRecord?> getProfileAnalysis({
    required String userId,
    required String analysisId,
  }) async {
    final snapshot = await _analysisCollection(userId).doc(analysisId).get();
    if (!snapshot.exists) {
      return null;
    }
    final data = snapshot.data() ?? const <String, dynamic>{};
    return ProfileAnalysisRecord(
      id: snapshot.id,
      data: data,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Deletes a stored profile analysis.
  Future<void> deleteProfileAnalysis({
    required String userId,
    required String analysisId,
  }) async {
    await _analysisCollection(userId).doc(analysisId).delete();
  }
}
