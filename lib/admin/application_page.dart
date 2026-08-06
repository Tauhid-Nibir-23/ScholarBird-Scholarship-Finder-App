/// Admin application management page.
///
/// Streams scholarship applications via a Firestore `collectionGroup`
/// (looks for `applications` on any path), supports:
///   * Free-text search across applicant / scholarship / country
///   * Filter chips: status, country
///   * Sort: newest, applicant, status, deadline
///   * Applicant avatar, document count, profile completeness indicator
///   * Quick actions: accept, reject, view application
///   * Confirmation dialogs for destructive actions
///   * Empty state + loading skeleton
///   * Pagination (10 per page)
///   * Responsive desktop table / mobile card layout
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/scholarbird_theme.dart';
import 'admin_ui.dart';
import 'widgets/admin_badge.dart';
import 'widgets/admin_data_table.dart';
import 'widgets/admin_dialogs.dart';
import 'widgets/admin_empty_state.dart';
import 'widgets/admin_filter_bar.dart';
import 'widgets/admin_search_bar.dart';
import 'widgets/admin_section.dart';

class ApplicationPage extends StatefulWidget {
  const ApplicationPage({super.key});

  @override
  State<ApplicationPage> createState() => _ApplicationPageState();
}

enum _ApplicationSort { newest, applicant, status, deadline }

enum _ApplicationStatus {
  all,
  applied,
  pending,
  reviewing,
  accepted,
  rejected,
  awarded,
}

class _ApplicationPageState extends State<ApplicationPage> {
  final _firestore = FirebaseFirestore.instance;
  final _searchCtrl = TextEditingController();

  String _query = '';
  _ApplicationStatus _statusFilter = _ApplicationStatus.all;
  String? _countryFilter;
  _ApplicationSort _sort = _ApplicationSort.newest;
  int _page = 0;
  static const int _pageSize = 10;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(
    DocumentSnapshot<Map<String, dynamic>> document,
    String status,
  ) async {
    final data = document.data() ?? const <String, dynamic>{};
    final uid = _uidFor(document);
    if (uid == null) {
      if (mounted)
        AdminDialogs.error(context, 'This application has no applicant id.');
      return;
    }
    try {
      final batch = _firestore.batch();
      batch.update(document.reference, {
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
        if (status == 'applied') 'adminAppliedAt': FieldValue.serverTimestamp(),
      });
      final scholarshipId = (data['scholarshipId'] ?? document.id).toString();
      final scholarshipTitle =
          (data['scholarshipTitle'] ?? data['title'] ?? 'this scholarship')
              .toString();
      batch.set(
          _firestore
              .collection('users')
              .doc(uid)
              .collection('notifications')
              .doc(),
          {
            'type': 'application_status',
            'title': 'Application status updated',
            'body': 'Your application for $scholarshipTitle was $status.',
            'scholarshipId': scholarshipId,
            'applicationId': document.id,
            'status': status,
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
      await batch.commit();
      if (!mounted) return;
      AdminDialogs.success(
          context, 'Application $status and applicant notified.');
    } catch (e) {
      if (!mounted) return;
      AdminDialogs.error(context, 'Update failed: $e');
    }
  }

  String? _uidFor(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data() ?? const <String, dynamic>{};
    final uid = data['userId']?.toString() ??
        data['applicantId']?.toString() ??
        document.reference.parent.parent?.id;
    return uid == null || uid.isEmpty ? null : uid;
  }

  Future<Map<String, dynamic>> _hydrateApplication(
      DocumentSnapshot<Map<String, dynamic>> application) async {
    final applicationData = application.data() ?? const <String, dynamic>{};
    final uid = _uidFor(application);
    if (uid == null)
      return {
        ...applicationData,
        'id': application.id,
        '_document': application,
        'documentCount': _documentCount(applicationData)
      };
    final userRef = _firestore.collection('users').doc(uid);
    final results = await Future.wait(
        [userRef.get(), userRef.collection('documents').get()]);
    final user =
        (results[0] as DocumentSnapshot<Map<String, dynamic>>).data() ??
            const <String, dynamic>{};
    final documentCount =
        (results[1] as QuerySnapshot<Map<String, dynamic>>).docs.length;
    final name = user['name'] ??
        user['displayName'] ??
        applicationData['applicantName'] ??
        applicationData['userName'];
    final email = user['email'] ?? applicationData['userEmail'];
    final avatar = user['avatar'] ??
        user['photoURL'] ??
        applicationData['applicantAvatar'] ??
        applicationData['userAvatar'];
    return {
      ...applicationData,
      ...user,
      'id': application.id,
      '_document': application,
      'uid': uid,
      'applicantName': name,
      'userName': name,
      'userEmail': email,
      'applicantAvatar': avatar,
      'userAvatar': avatar,
      'country': user['country'] ?? applicationData['country'],
      'documentCount': documentCount
    };
  }

  Future<void> _viewApplicant(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final data = document.data() ?? <String, dynamic>{};
    final uid = data['userId']?.toString() ??
        data['applicantId']?.toString() ??
        document.reference.parent.parent?.id;
    if (uid == null || uid.isEmpty) {
      AdminDialogs.error(context, 'No applicant id on this application.');
      return;
    }
    try {
      final snap = await _firestore.collection('users').doc(uid).get();
      if (!mounted) return;
      final user = snap.data() ?? const <String, dynamic>{};
      final userDocuments = await _firestore
          .collection('users')
          .doc(uid)
          .collection('documents')
          .get();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _ApplicationDetailsDialog(
          application: data,
          user: user,
          documents: userDocuments.docs.map((doc) => doc.data()).toList(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AdminDialogs.error(context, 'Lookup failed: $e');
    }
  }

  // ----------------------- Filtering / sorting ----------------------

  DateTime? _dateValue(Map<String, dynamic> data, String field) {
    final dynamic d = data[field];
    if (d is Timestamp) return d.toDate();
    if (d is DateTime) return d;
    if (d is String) return DateTime.tryParse(d);
    return null;
  }

  bool _matchesSearch(Map<String, dynamic> data) {
    if (_query.isEmpty) return true;
    final haystack = [
      data['applicantName'],
      data['userName'],
      data['userEmail'],
      data['scholarshipTitle'],
      data['title'],
      data['country'],
    ].whereType<Object>().map((e) => e.toString().toLowerCase()).join(' ');
    return haystack.contains(_query);
  }

  bool _matchesStatusFilter(Map<String, dynamic> data) {
    if (_statusFilter == _ApplicationStatus.all) return true;
    final status = data['status']?.toString().toLowerCase() ?? 'pending';
    // Older submissions used `pending`; treat them as Applied in this filter.
    if (_statusFilter == _ApplicationStatus.applied) {
      return status == 'applied' || status == 'pending';
    }
    return status == _statusFilter.name.toLowerCase();
  }

  int _profileCompleteness(Map<String, dynamic> data) {
    var filled = 0;
    const fields = [
      'name',
      'displayName',
      'email',
      'phone',
      'country',
      'avatar',
      'bio',
    ];
    for (final f in fields) {
      final v = data[f];
      if (v is String && v.trim().isNotEmpty) filled++;
      if (v is Timestamp) filled++;
    }
    return ((filled / fields.length) * 100).round();
  }

  int _documentCount(Map<String, dynamic> data) {
    final docs = data['documents'];
    if (docs is List) return docs.length;
    if (docs is Map) return docs.length;
    return 0;
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> docs) {
    final list = docs
        .map((d) => Map<String, dynamic>.from(d))
        .where(_matchesSearch)
        .where(_matchesStatusFilter)
        .where((m) {
      if (_countryFilter == null) return true;
      return m['country']?.toString().toLowerCase() ==
          _countryFilter!.toLowerCase();
    }).toList();

    switch (_sort) {
      case _ApplicationSort.newest:
        list.sort((a, b) {
          final ad = _dateValue(a, 'appliedAt') ?? _dateValue(a, 'createdAt');
          final bd = _dateValue(b, 'appliedAt') ?? _dateValue(b, 'createdAt');
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return bd.compareTo(ad);
        });
        break;
      case _ApplicationSort.applicant:
        list.sort((a, b) =>
            (a['applicantName']?.toString() ?? a['userName']?.toString() ?? '')
                .compareTo(
              b['applicantName']?.toString() ?? b['userName']?.toString() ?? '',
            ));
        break;
      case _ApplicationSort.status:
        list.sort((a, b) => (a['status']?.toString() ?? '').compareTo(
              b['status']?.toString() ?? '',
            ));
        break;
      case _ApplicationSort.deadline:
        list.sort((a, b) {
          final ad = _dateValue(a, 'deadline');
          final bd = _dateValue(b, 'deadline');
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return ad.compareTo(bd);
        });
        break;
    }
    return list;
  }

  // --------------------------- Build -------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? Theme.of(context).colorScheme.surface : Colors.white,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // The page sorts client-side. Avoiding orderBy here prevents a
        // collection-group index requirement and includes old submissions
        // that did not persist `appliedAt`.
        stream: _firestore.collectionGroup('applications').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(ScholarBirdSpacing.large),
                child: Text('Could not load applications: ${snapshot.error}'),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: AdminLoadingSkeleton(itemCount: 6, itemHeight: 88),
            );
          }
          final applicationDocs = snapshot.data?.docs ?? const [];
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: Future.wait(applicationDocs.map(_hydrateApplication)),
            builder: (context, hydrated) {
              if (hydrated.hasError)
                return Center(
                    child: Text(
                        'Could not load applicant details: ${hydrated.error}'));
              if (!hydrated.hasData)
                return const Padding(
                    padding: EdgeInsets.all(24),
                    child: AdminLoadingSkeleton(itemCount: 6, itemHeight: 88));
              final docs = hydrated.data!;
              final filtered = _applyFilters(docs);
              _page = _page.clamp(
                0,
                (filtered.length / _pageSize).floor().clamp(0, 1 << 30),
              );
              final pageStart = _page * _pageSize;
              final pageEnd = (pageStart + _pageSize).clamp(0, filtered.length);
              final pageItems = filtered.sublist(pageStart, pageEnd);

              final countries = {
                for (final d in docs)
                  if ((d['country']?.toString().isNotEmpty ?? false))
                    d['country'].toString(),
              }.toList()
                ..sort();

              return SingleChildScrollView(
                padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AdminPageHeader(
                      title: 'Applications',
                      subtitle:
                          '${filtered.length} of ${docs.length} applications shown',
                    ),
                    const SizedBox(height: 20),
                    AdminSection(
                      title: 'All applications',
                      subtitle:
                          'Review applications submitted across all scholarships.',
                      icon: Icons.assignment_outlined,
                      action: PopupMenuButton<_ApplicationSort>(
                        tooltip: 'Sort',
                        icon:
                            const Icon(Icons.sort, color: AdminPalette.heading),
                        onSelected: (value) => setState(() => _sort = value),
                        itemBuilder: (_) => [
                          for (final s in _ApplicationSort.values)
                            PopupMenuItem(
                              value: s,
                              child: Row(
                                children: [
                                  Icon(
                                    _sort == s
                                        ? Icons.check
                                        : Icons.radio_button_unchecked,
                                    size: 16,
                                    color: AdminPalette.body,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(_sortLabel(s)),
                                ],
                              ),
                            ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AdminSearchBar(
                            controller: _searchCtrl,
                            hintText:
                                'Search by applicant, scholarship, email, or countryÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¦',
                            onChanged: (value) {
                              setState(() {
                                _query = value.trim().toLowerCase();
                                _page = 0;
                              });
                            },
                            filterMenuBuilder: (_) => [
                              PopupMenuItem<void>(
                                enabled: false,
                                child: SizedBox(
                                  width: 340,
                                  child: _FilterRow(
                                    countries: countries,
                                    country: _countryFilter,
                                    status: _statusFilter,
                                    onCountry: (v) => setState(() {
                                      _countryFilter = v;
                                      _page = 0;
                                    }),
                                    onStatus: (v) => setState(() {
                                      _statusFilter = v;
                                      _page = 0;
                                    }),
                                    onClear: () => setState(() {
                                      _countryFilter = null;
                                      _statusFilter = _ApplicationStatus.all;
                                      _searchCtrl.clear();
                                      _query = '';
                                      _page = 0;
                                    }),
                                  ),
                                ),
                              ),
                            ],
                            hasActiveFilters: _countryFilter != null ||
                                _statusFilter != _ApplicationStatus.all,
                          ),
                          const SizedBox(height: 12),
                          if (filtered.isEmpty)
                            AdminEmptyState(
                              icon: Icons.assignment_late_outlined,
                              title: 'No applications match the filters',
                              message:
                                  'Clear the filters or wait for new applications to arrive.',
                            )
                          else
                            AdminDataTable<Map<String, dynamic>>(
                              columns: const [
                                AdminTableColumn(label: 'Applicant'),
                                AdminTableColumn(label: 'Scholarship'),
                                AdminTableColumn(label: 'Country'),
                                AdminTableColumn(label: 'Applied'),
                                AdminTableColumn(label: 'Status'),
                                AdminTableColumn(label: 'Docs'),
                                AdminTableColumn(label: 'Profile'),
                                AdminTableColumn(label: 'Actions'),
                              ],
                              rows: pageItems,
                              cardBuilder: (m) => _ApplicationCard(
                                data: m,
                                onView: () => _viewApplicant(
                                  m['_document']
                                      as DocumentSnapshot<Map<String, dynamic>>,
                                ),
                                onPending: () => _updateStatus(
                                  m['_document']
                                      as DocumentSnapshot<Map<String, dynamic>>,
                                  'applied',
                                ),
                                onAccept: () => _updateStatus(
                                  m['_document']
                                      as DocumentSnapshot<Map<String, dynamic>>,
                                  'accepted',
                                ),
                                onReject: () => _updateStatus(
                                  m['_document']
                                      as DocumentSnapshot<Map<String, dynamic>>,
                                  'rejected',
                                ),
                              ),
                              rowBuilder: (m) => [
                                DataCell(_ApplicantCell(
                                  data: m,
                                  completeness: _profileCompleteness(m),
                                )),
                                DataCell(_ScholarshipCell(data: m)),
                                DataCell(AdminBadge(
                                  label: m['country']?.toString() ??
                                      'ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â',
                                  color: const Color(0xFF0F766E),
                                  icon: Icons.public,
                                )),
                                DataCell(_AppliedCell(data: m)),
                                DataCell(_StatusBadge(data: m)),
                                DataCell(_DocsCell(
                                    count: (m['documentCount'] as int?) ??
                                        _documentCount(m))),
                                DataCell(_Completeness(
                                  value: _profileCompleteness(m),
                                )),
                                DataCell(_QuickActions(
                                  data: m,
                                  onView: () => _viewApplicant(
                                    m['_document'] as DocumentSnapshot<
                                        Map<String, dynamic>>,
                                  ),
                                  onPending: () => _updateStatus(
                                    m['_document'] as DocumentSnapshot<
                                        Map<String, dynamic>>,
                                    'applied',
                                  ),
                                  onAccept: () => _updateStatus(
                                    m['_document'] as DocumentSnapshot<
                                        Map<String, dynamic>>,
                                    'accepted',
                                  ),
                                  onReject: () => _updateStatus(
                                    m['_document'] as DocumentSnapshot<
                                        Map<String, dynamic>>,
                                    'rejected',
                                  ),
                                )),
                              ],
                            ),
                          if (filtered.length > _pageSize) ...[
                            const SizedBox(height: 12),
                            _Pagination(
                              page: _page,
                              pageSize: _pageSize,
                              total: filtered.length,
                              onChanged: (p) => setState(() => _page = p),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  static String _sortLabel(_ApplicationSort s) {
    switch (s) {
      case _ApplicationSort.newest:
        return 'Newest first';
      case _ApplicationSort.applicant:
        return 'Sort by applicant';
      case _ApplicationSort.status:
        return 'Sort by status';
      case _ApplicationSort.deadline:
        return 'Sort by deadline';
    }
  }
}

class _ApplicationDetailsDialog extends StatelessWidget {
  const _ApplicationDetailsDialog({
    required this.application,
    required this.user,
    required this.documents,
  });

  final Map<String, dynamic> application;
  final Map<String, dynamic> user;
  final List<Map<String, dynamic>> documents;

  String _text(String key,
          [String fallback =
              'ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â']) =>
      application[key]?.toString().trim().isNotEmpty == true
          ? application[key].toString()
          : fallback;

  List<Map<String, dynamic>> get _allDocuments {
    final attached = application['documents'];
    final fromApplication = <Map<String, dynamic>>[];
    if (attached is List) {
      for (final item in attached) {
        if (item is Map) fromApplication.add(Map<String, dynamic>.from(item));
      }
    } else if (attached is Map) {
      for (final entry in attached.entries) {
        if (entry.value is Map) {
          fromApplication.add(Map<String, dynamic>.from(entry.value as Map));
        }
      }
    }
    return [...fromApplication, ...documents];
  }

  Future<void> _openDocument(
      BuildContext context, Map<String, dynamic> doc) async {
    final raw =
        doc['downloadUrl'] ?? doc['url'] ?? doc['fileUrl'] ?? doc['publicUrl'];
    final uri = Uri.tryParse(raw?.toString() ?? '');
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('This document does not have an accessible link.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = _allDocuments;
    final applicant = user['name']?.toString() ??
        user['displayName']?.toString() ??
        application['applicantName']?.toString() ??
        application['userName']?.toString() ??
        'Unknown applicant';
    return AlertDialog(
      title: const Text('Application details'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(applicant,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if ((user['email'] ?? application['userEmail'])
                    ?.toString()
                    .isNotEmpty ==
                true)
              Text((user['email'] ?? application['userEmail']).toString()),
            const SizedBox(height: 18),
            _DetailRow(
                'Scholarship', _text('scholarshipTitle', _text('title'))),
            _DetailRow(
                'Country',
                (user['country'] ??
                        application['country'] ??
                        'ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â')
                    .toString()),
            _DetailRow('Degree', _text('degree')),
            _DetailRow('Status', _text('status', 'Pending')),
            _DetailRow(
                'Applied',
                _formatApplicationDate(
                    application['appliedAt'] ?? application['createdAt'])),
            const SizedBox(height: 18),
            const Text('Documents',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (docs.isEmpty)
              const Text('No documents uploaded with this application.',
                  style: TextStyle(color: AdminPalette.body))
            else
              ...docs.map((doc) {
                final name = doc['fileName'] ??
                    doc['name'] ??
                    doc['documentType'] ??
                    'Uploaded document';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(name.toString()),
                  subtitle: doc['uploadedAt'] == null
                      ? null
                      : Text(_formatApplicationDate(doc['uploadedAt'])),
                  trailing: IconButton(
                    tooltip: 'Open document',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => _openDocument(context, doc),
                  ),
                );
              }),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'))
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 96,
              child: Text(label,
                  style: const TextStyle(color: AdminPalette.body))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}

String _formatApplicationDate(dynamic value) {
  final date = value is Timestamp
      ? value.toDate()
      : value is DateTime
          ? value
          : value is String
              ? DateTime.tryParse(value)
              : null;
  return date == null
      ? 'ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â'
      : adminFormatDate(date);
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.countries,
    required this.country,
    required this.status,
    required this.onCountry,
    required this.onStatus,
    required this.onClear,
  });

  final List<String> countries;
  final String? country;
  final _ApplicationStatus status;
  final ValueChanged<String?> onCountry;
  final ValueChanged<_ApplicationStatus> onStatus;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _filterRow(
          label: 'Country',
          options: [
            for (final c in countries)
              AdminFilterOption<String>(c, c, icon: Icons.public),
          ],
          selected: country == null ? <String>{} : {country!},
          onChanged: (v) => onCountry(v.isEmpty ? null : v.first),
          singleSelect: true,
        ),
        const SizedBox(height: 6),
        _filterRow<_ApplicationStatus>(
          label: 'Status',
          options: [
            for (final s in _ApplicationStatus.values)
              AdminFilterOption<_ApplicationStatus>(
                s,
                _statusLabel(s),
                icon: _statusIcon(s),
              ),
          ],
          selected: {status},
          onChanged: (v) =>
              onStatus(v.isEmpty ? _ApplicationStatus.all : v.first),
          singleSelect: true,
          onClear: onClear,
        ),
      ],
    );
  }

  Widget _filterRow<T>({
    required String label,
    required List<AdminFilterOption<T>> options,
    required Set<T> selected,
    required ValueChanged<Set<T>> onChanged,
    required bool singleSelect,
    VoidCallback? onClear,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AdminPalette.body,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Expanded(
          child: AdminFilterBar<T>(
            options: options,
            selected: selected,
            onChanged: onChanged,
            singleSelect: singleSelect,
            onClear: onClear,
          ),
        ),
      ],
    );
  }

  static String _statusLabel(_ApplicationStatus s) {
    switch (s) {
      case _ApplicationStatus.all:
        return 'All';
      case _ApplicationStatus.applied:
        return 'Applied';
      case _ApplicationStatus.pending:
        return 'Pending';
      case _ApplicationStatus.reviewing:
        return 'Reviewing';
      case _ApplicationStatus.accepted:
        return 'Accepted';
      case _ApplicationStatus.rejected:
        return 'Rejected';
      case _ApplicationStatus.awarded:
        return 'Awarded';
    }
  }

  static IconData _statusIcon(_ApplicationStatus s) {
    switch (s) {
      case _ApplicationStatus.all:
        return Icons.all_inclusive;
      case _ApplicationStatus.applied:
        return Icons.assignment_turned_in_outlined;
      case _ApplicationStatus.pending:
        return Icons.schedule_outlined;
      case _ApplicationStatus.reviewing:
        return Icons.visibility_outlined;
      case _ApplicationStatus.accepted:
        return Icons.check_circle_outline;
      case _ApplicationStatus.rejected:
        return Icons.cancel_outlined;
      case _ApplicationStatus.awarded:
        return Icons.emoji_events_outlined;
    }
  }
}

class _ApplicantCell extends StatelessWidget {
  const _ApplicantCell({required this.data, required this.completeness});

  final Map<String, dynamic> data;
  final int completeness;

  @override
  Widget build(BuildContext context) {
    final name = data['applicantName']?.toString() ??
        data['userName']?.toString() ??
        'Unknown applicant';
    final avatar = data['applicantAvatar']?.toString() ??
        data['userAvatar']?.toString() ??
        '';
    final initials = _initials(name);
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AdminPalette.primary.withValues(alpha: 0.12),
          backgroundImage: avatar.isEmpty ? null : NetworkImage(avatar),
          onBackgroundImageError: avatar.isEmpty ? null : (_, __) {},
          child: avatar.isEmpty
              ? Text(
                  initials,
                  style: const TextStyle(
                    color: AdminPalette.primary,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AdminPalette.heading,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (data['userEmail']?.toString().isNotEmpty ?? false)
                Text(
                  data['userEmail'].toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminPalette.body,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _ScholarshipCell extends StatelessWidget {
  const _ScholarshipCell({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final title = data['scholarshipTitle']?.toString() ??
        data['title']?.toString() ??
        'Untitled';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AdminPalette.heading,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (data['scholarshipId']?.toString().isNotEmpty ?? false)
          Text(
            data['scholarshipId'].toString(),
            style: const TextStyle(
              fontSize: 11,
              color: AdminPalette.body,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

class _AppliedCell extends StatelessWidget {
  const _AppliedCell({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final dynamic raw = data['appliedAt'] ?? data['createdAt'];
    DateTime? parsed;
    if (raw is Timestamp) {
      parsed = raw.toDate();
    } else if (raw is DateTime) {
      parsed = raw;
    } else if (raw is String) {
      parsed = DateTime.tryParse(raw);
    }
    if (parsed == null) {
      return const Text(
          'ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â',
          style: TextStyle(color: AdminPalette.body));
    }
    return Text(
      adminFormatDate(parsed),
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        color: AdminPalette.heading,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final status = data['status']?.toString().toLowerCase() ?? 'pending';
    switch (status) {
      case 'accepted':
        return const AdminBadge(
          label: 'Accepted',
          color: Color(0xFF16A34A),
          icon: Icons.check_circle_outline,
        );
      case 'rejected':
        return const AdminBadge(
          label: 'Rejected',
          color: Color(0xFFDC2626),
          icon: Icons.cancel_outlined,
        );
      case 'applied':
        return const AdminBadge(
          label: 'Applied',
          color: Color(0xFFD97706),
          icon: Icons.assignment_turned_in_outlined,
        );
      case 'reviewing':
        return const AdminBadge(
          label: 'Reviewing',
          color: Color(0xFF2563EB),
          icon: Icons.visibility_outlined,
        );
      case 'awarded':
        return const AdminBadge(
          label: 'Awarded',
          color: Color(0xFFD97706),
          icon: Icons.emoji_events_outlined,
        );
      case 'pending':
      default:
        return const AdminBadge(
          label: 'Pending',
          color: Color(0xFF6B7A95),
          icon: Icons.schedule_outlined,
        );
    }
  }
}

class _DocsCell extends StatelessWidget {
  const _DocsCell({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          count > 0 ? Icons.attach_file : Icons.attach_file_outlined,
          size: 16,
          color: count > 0 ? AdminPalette.primary : AdminPalette.body,
        ),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: TextStyle(
            color: count > 0 ? AdminPalette.heading : AdminPalette.body,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _Completeness extends StatelessWidget {
  const _Completeness({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    Color color;
    if (value >= 80) {
      color = const Color(0xFF16A34A);
    } else if (value >= 50) {
      color = const Color(0xFFD97706);
    } else {
      color = const Color(0xFFDC2626);
    }
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: LinearProgressIndicator(
            value: value / 100,
            backgroundColor: color.withValues(alpha: 0.15),
            color: color,
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$value%',
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.data,
    required this.onView,
    required this.onPending,
    required this.onAccept,
    required this.onReject,
  });

  final Map<String, dynamic> data;
  final VoidCallback onView;
  final VoidCallback onPending;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'View applicant',
          icon: const Icon(Icons.person_outline),
          onPressed: onView,
        ),
        IconButton(
          tooltip: 'View application documents',
          icon: const Icon(Icons.attach_file_outlined),
          onPressed: onView,
        ),
        IconButton(
          tooltip: 'Accept',
          icon: const Icon(
            Icons.check_circle_outline,
            color: Color(0xFF16A34A),
          ),
          onPressed: onAccept,
        ),
        PopupMenuButton<String>(
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'reject',
              child: ListTile(
                leading: Icon(
                  Icons.cancel_outlined,
                  color: Color(0xFFDC2626),
                ),
                title: Text(
                  'Reject',
                  style: TextStyle(color: Color(0xFFDC2626)),
                ),
              ),
            ),
          ],
          onSelected: (value) {
            switch (value) {
              case 'reject':
                onReject();
                break;
            }
          },
        ),
      ],
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    required this.data,
    required this.onView,
    required this.onPending,
    required this.onAccept,
    required this.onReject,
  });

  final Map<String, dynamic> data;
  final VoidCallback onView;
  final VoidCallback onPending;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final name = data['applicantName']?.toString() ?? 'Unknown applicant';
    return AdminSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AdminPalette.heading,
                  ),
                ),
              ),
              _StatusBadge(data: data),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            data['scholarshipTitle']?.toString() ??
                data['title']?.toString() ??
                'Untitled scholarship',
            style: const TextStyle(
              fontSize: 12,
              color: AdminPalette.body,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              AdminBadge(
                label: data['country']?.toString() ??
                    'ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â',
                color: const Color(0xFF0F766E),
                icon: Icons.public,
              ),
              _DocsCell(
                count: (data['documentCount'] as int?) ?? 0,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  children: [
                    TextButton.icon(
                      onPressed: onView,
                      icon: const Icon(Icons.person_outline, size: 16),
                      label: const Text('View'),
                    ),
                    TextButton.icon(
                      onPressed: onView,
                      icon: const Icon(Icons.attach_file_outlined, size: 16),
                      label: const Text('Documents'),
                    ),
                    TextButton.icon(
                      onPressed: onPending,
                      icon: const Icon(Icons.assignment_turned_in_outlined,
                          size: 16),
                      label: const Text('Applied'),
                    ),
                    TextButton.icon(
                      onPressed: onAccept,
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Accept'),
                    ),
                    TextButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('Reject'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.onChanged,
  });

  final int page;
  final int pageSize;
  final int total;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final totalPages = (total / pageSize).ceil().clamp(1, 1 << 30);
    final current = page + 1;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          'Showing ${page * pageSize + 1}ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ'
          '${((page + 1) * pageSize).clamp(0, total)} of $total',
          style: const TextStyle(color: AdminPalette.body, fontSize: 12),
        ),
        const SizedBox(width: 12),
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: page == 0 ? null : () => onChanged(page - 1),
        ),
        Text('$current / $totalPages'),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: page >= totalPages - 1 ? null : () => onChanged(page + 1),
        ),
      ],
    );
  }
}
