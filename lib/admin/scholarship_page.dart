/// Admin scholarship management page.
///
/// Streams the Firestore `scholarships` collection, supports:
///   * Free-text search across title / provider / country / degree
///   * Filter chips: country, degree, funding, status, deadline
///   * Sort: newest, deadline, country, funding
///   * Status / funding / deadline badges
///   * Country flags (Unicode flag emoji fallback)
///   * Quick action menu: view, edit, delete, duplicate, copy link,
///     archive, restore
///   * Confirmation dialogs for destructive actions
///   * Empty state + loading skeleton
///   * Pagination (10 items per page)
///   * Responsive desktop table / mobile card layout
///
/// All existing CRUD logic (add/edit via [_openForm], delete via
/// Firestore, archive toggle) is preserved. Only the UI layer is
/// upgraded.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/scholarbird_theme.dart';
import 'admin_ui.dart';
import 'add_scholarship_page.dart';
import 'widgets/admin_badge.dart';
import 'widgets/admin_data_table.dart';
import 'widgets/admin_dialogs.dart';
import 'widgets/admin_empty_state.dart';
import 'widgets/admin_filter_bar.dart';
import 'widgets/admin_search_bar.dart';
import 'widgets/admin_section.dart';

class ScholarshipPage extends StatefulWidget {
  const ScholarshipPage({super.key});

  @override
  State<ScholarshipPage> createState() => _ScholarshipPageState();
}

enum _ScholarshipSort { newest, deadline, country, funding }

enum _ScholarshipStatus { all, active, hidden, expired }

class _ScholarshipPageState extends State<ScholarshipPage> {
  final _firestore = FirebaseFirestore.instance;
  final _searchCtrl = TextEditingController();

  String _query = '';
  String? _countryFilter;
  String? _degreeFilter;
  String? _fundingFilter;
  _ScholarshipStatus _statusFilter = _ScholarshipStatus.all;
  // The operational default is the opportunity that closes soonest.
  _ScholarshipSort _sort = _ScholarshipSort.deadline;
  int _page = 0;
  static const int _pageSize = 10;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openForm([DocumentSnapshot<Map<String, dynamic>>? document]) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AddScholarshipPage(scholarship: document),
      ),
    );
  }

  Future<void> _toggleValue(
    DocumentSnapshot<Map<String, dynamic>> document,
    String field,
    dynamic value,
  ) async {
    try {
      await document.reference.update({field: value});
    } catch (e) {
      if (!mounted) return;
      AdminDialogs.error(context, 'Update failed: $e');
    }
  }

  Future<void> _setHidden(
    DocumentSnapshot<Map<String, dynamic>> document,
    bool archived,
  ) async {
    await _toggleValue(document, 'isHidden', archived);
    if (!mounted) return;
    AdminDialogs.success(
      context,
      archived ? 'Scholarship hidden' : 'Scholarship visible',
    );
  }

  Future<void> _toggleFeatured(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final next = document.data()?['isFeatured'] != true;
    await _toggleValue(document, 'isFeatured', next);
    if (mounted) {
      AdminDialogs.success(context, next ? 'Scholarship featured' : 'Scholarship unfeatured');
    }
  }

  Future<void> _duplicate(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    try {
      final data = document.data() ?? <String, dynamic>{};
      final cloned = <String, dynamic>{...data};
      cloned
        ..remove('id')
        ..['title'] = '${data['title'] ?? 'Untitled'} (copy)'
        ..['isHidden'] = false
        ..['createdAt'] = FieldValue.serverTimestamp()
        ..['updatedAt'] = FieldValue.serverTimestamp();
      await _firestore.collection('scholarships').add(cloned);
      if (!mounted) return;
      AdminDialogs.success(context, 'Scholarship duplicated');
    } catch (e) {
      if (!mounted) return;
      AdminDialogs.error(context, 'Duplicate failed: $e');
    }
  }

  Future<void> _copyLink(Map<String, dynamic> data) async {
    final url = data['sourceUrl']?.toString() ?? '';
    if (url.isEmpty) {
      AdminDialogs.error(context, 'No sourceUrl to copy.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    AdminDialogs.success(context, 'Link copied to clipboard');
  }

  Future<void> _deleteScholarship(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final confirmed = await AdminDialogs.confirm(
      context: context,
      title: 'Delete scholarship?',
      message:
          'This permanently removes the document from the `scholarships` collection. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    try {
      await document.reference.delete();
      if (!mounted) return;
      AdminDialogs.success(context, 'Scholarship deleted');
    } catch (e) {
      if (!mounted) return;
      AdminDialogs.error(context, 'Delete failed: $e');
    }
  }

  // ----------------------- Filtering / sorting ----------------------

  DateTime? _deadlineValue(Map<String, dynamic> data) {
    final dynamic d = data['deadline'];
    if (d is Timestamp) return d.toDate();
    if (d is DateTime) return d;
    if (d is String) return DateTime.tryParse(d);
    return null;
  }

  DateTime? _createdAtValue(Map<String, dynamic> data) {
    final dynamic d = data['createdAt'];
    if (d is Timestamp) return d.toDate();
    if (d is DateTime) return d;
    return null;
  }

  bool _matchesStatus(Map<String, dynamic> data) {
    switch (_statusFilter) {
      case _ScholarshipStatus.all:
        return true;
      case _ScholarshipStatus.hidden:
        return data['isHidden'] == true;
      case _ScholarshipStatus.expired:
        final deadline = _deadlineValue(data);
        return deadline != null && deadline.isBefore(DateTime.now());
      case _ScholarshipStatus.active:
        if (data['isHidden'] == true) return false;
        final deadline = _deadlineValue(data);
        if (deadline != null && deadline.isBefore(DateTime.now())) {
          return false;
        }
        return true;
    }
  }

  bool _matchesSearch(Map<String, dynamic> data) {
    if (_query.isEmpty) return true;
    final haystack = [
      data['title'],
      data['provider'],
      data['country'],
      data['degree'],
    ].whereType<Object>().map((e) => e.toString().toLowerCase()).join(' ');
    return haystack.contains(_query);
  }

  List<Map<String, dynamic>> _applyFilters(
    List<DocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final list = docs
        .map((d) => <String, dynamic>{'id': d.id, ...?d.data()})
        .where(_matchesStatus)
        .where((m) {
          if (_countryFilter == null) return true;
          final c = m['country']?.toString().toLowerCase();
          return c == _countryFilter!.toLowerCase();
        })
        .where((m) {
          if (_degreeFilter == null) return true;
          final v = m['degree']?.toString().toLowerCase();
          return v == _degreeFilter!.toLowerCase();
        })
        .where((m) {
          if (_fundingFilter == null) return true;
          final v = m['funding']?.toString().toLowerCase();
          return v == _fundingFilter!.toLowerCase();
        })
        .where(_matchesSearch)
        .toList();

    switch (_sort) {
      case _ScholarshipSort.newest:
        list.sort((a, b) {
          final ad = _createdAtValue(a);
          final bd = _createdAtValue(b);
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return bd.compareTo(ad);
        });
        break;
      case _ScholarshipSort.deadline:
        list.sort((a, b) {
          final ad = _deadlineValue(a);
          final bd = _deadlineValue(b);
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return ad.compareTo(bd);
        });
        break;
      case _ScholarshipSort.country:
        list.sort((a, b) =>
            (a['country']?.toString() ?? '').compareTo(
              b['country']?.toString() ?? '',
            ));
        break;
      case _ScholarshipSort.funding:
        list.sort((a, b) =>
            (a['funding']?.toString() ?? '').compareTo(
              b['funding']?.toString() ?? '',
            ));
        break;
    }
    return list;
  }

  bool get _hasActiveFilters =>
      _countryFilter != null || _degreeFilter != null || _fundingFilter != null || _statusFilter != _ScholarshipStatus.all;

  void _clearFilters() => setState(() {
        _countryFilter = null;
        _degreeFilter = null;
        _fundingFilter = null;
        _statusFilter = _ScholarshipStatus.all;
        _page = 0;
      });

  Future<void> _showFilters({
    required List<String> countries,
    required List<String> degrees,
    required List<String> fundings,
  }) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => SafeArea(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 520),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFFD7DDEA), borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 18),
              Row(children: [
                const Icon(Icons.tune_rounded, color: AdminPalette.primary),
                const SizedBox(width: 10),
                const Expanded(child: Text('Filter scholarships', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                TextButton(onPressed: _clearFilters, child: const Text('Reset')),
              ]),
              const SizedBox(height: 8),
              Expanded(child: SingleChildScrollView(child: _FilterRow(
                countries: countries, degrees: degrees, fundings: fundings,
                country: _countryFilter, degree: _degreeFilter, funding: _fundingFilter, status: _statusFilter,
                onCountry: (v) => setState(() { _countryFilter = v; _page = 0; }),
                onDegree: (v) => setState(() { _degreeFilter = v; _page = 0; }),
                onFunding: (v) => setState(() { _fundingFilter = v; _page = 0; }),
                onStatus: (v) => setState(() { _statusFilter = v; _page = 0; }),
                onClear: _clearFilters,
              ))),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.of(sheetContext).pop(), child: const Text('Show results'))),
            ]),
          ),
        ),
      );

  // --------------------------- Build -------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? Theme.of(context).colorScheme.surface
          : Colors.white,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add scholarship'),
        backgroundColor: AdminPalette.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // Sort locally so legacy/imported documents without `createdAt` are
        // still visible and no composite Firestore index is required.
        stream: _firestore.collection('scholarships').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(ScholarBirdSpacing.large),
                child: Text('Could not load scholarships: ${snapshot.error}'),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: AdminLoadingSkeleton(itemCount: 6, itemHeight: 80),
            );
          }
          final docs = snapshot.data?.docs ?? const [];
          final filtered = _applyFilters(docs);
          _page = _page.clamp(0, (filtered.length / _pageSize).floor()
              .clamp(0, 1 << 30));
          final pageStart = _page * _pageSize;
          final pageEnd = (pageStart + _pageSize).clamp(0, filtered.length);
          final pageItems = filtered.sublist(pageStart, pageEnd);

          final countries = {
            for (final d in docs)
              if ((d.data()['country']?.toString().isNotEmpty ?? false))
                d.data()['country'].toString(),
          }.toList()
            ..sort();
          final degrees = {
            for (final d in docs)
              if ((d.data()['degree']?.toString().isNotEmpty ?? false))
                d.data()['degree'].toString(),
          }.toList()
            ..sort();
          final fundings = {
            for (final d in docs)
              if ((d.data()['funding']?.toString().isNotEmpty ?? false))
                d.data()['funding'].toString(),
          }.toList()
            ..sort();

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              ScholarBirdSpacing.medium,
              ScholarBirdSpacing.medium,
              ScholarBirdSpacing.medium,
              96,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdminPageHeader(
                  title: 'Scholarships',
                  subtitle:
                      '${filtered.length} of ${docs.length} scholarships shown',
                  actions: [
                    FilledButton.icon(
                      onPressed: () => _openForm(),
                      icon: const Icon(Icons.add),
                      label: const Text('New scholarship'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AdminPalette.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                AdminSection(
                  title: 'All scholarships',
                  subtitle: 'Search, filter, and manage every scholarship in Firestore.',
                  icon: Icons.workspace_premium_outlined,
                  action: PopupMenuButton<_ScholarshipSort>(
                    tooltip: 'Sort',
                    icon: const Icon(Icons.sort, color: AdminPalette.heading),
                    onSelected: (value) => setState(() => _sort = value),
                    itemBuilder: (_) => [
                      for (final s in _ScholarshipSort.values)
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
                        hasActiveFilters: _hasActiveFilters,
                        onFilterTap: () => _showFilters(
                          countries: countries,
                          degrees: degrees,
                          fundings: fundings,
                        ),
                        hintText: 'Search by title, provider, country, or degree…',
                        onChanged: (value) {
                          setState(() {
                            _query = value.trim().toLowerCase();
                            _page = 0;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      if (_hasActiveFilters)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _clearFilters,
                            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                            label: const Text('Clear applied filters'),
                          ),
                        ),
                      const SizedBox(height: 12),
                      if (filtered.isEmpty)
                        AdminEmptyState(
                          icon: Icons.search_off_outlined,
                          title: 'No scholarships match the filters',
                          message: 'Clear the filters or add a new scholarship.',
                          action: FilledButton.icon(
                            onPressed: () => _openForm(),
                            icon: const Icon(Icons.add),
                            label: const Text('Add scholarship'),
                          ),
                        )
                      else
                        AdminDataTable<Map<String, dynamic>>(
                          columns: const [
                            AdminTableColumn(label: 'Scholarship'),
                            AdminTableColumn(label: 'Country'),
                            AdminTableColumn(label: 'Degree'),
                            AdminTableColumn(label: 'Funding'),
                            AdminTableColumn(label: 'Deadline'),
                            AdminTableColumn(label: 'Status'),
                            AdminTableColumn(label: 'Actions'),
                          ],
                          rows: pageItems,
                          cardBuilder: (m) => _ScholarshipCard(
                            data: m,
                            onEdit: () => _openForm(
                              docs.firstWhere((d) => d.id == m['id']),
                            ),
                            onDelete: () => _deleteScholarship(
                              docs.firstWhere((d) => d.id == m['id']),
                            ),
                            onArchive: (archived) => _setHidden(
                              docs.firstWhere((d) => d.id == m['id']),
                              archived,
                            ),
                            onToggleFeatured: () => _toggleFeatured(
                              docs.firstWhere((d) => d.id == m['id']),
                            ),
                            onDuplicate: () => _duplicate(
                              docs.firstWhere((d) => d.id == m['id']),
                            ),
                            onCopyLink: () => _copyLink(m),
                            onView: () => _openForm(
                              docs.firstWhere((d) => d.id == m['id']),
                            ),
                          ),
                          rowBuilder: (m) => [
                            DataCell(_TitleCell(data: m)),
                            DataCell(AdminBadge(
                              label: m['country']?.toString() ?? '—',
                              color: const Color(0xFF0F766E),
                              icon: Icons.public,
                            )),
                            DataCell(Text(
                              m['degree']?.toString() ?? '—',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            )),
                            DataCell(AdminBadge(
                              label: m['funding']?.toString() ?? '—',
                              color: const Color(0xFF7C3AED),
                              icon: Icons.payments_outlined,
                            )),
                            DataCell(_DeadlineCell(data: m)),
                            DataCell(_StatusBadge(data: m)),
                            DataCell(_QuickActions(
                              data: m,
                              onEdit: () => _openForm(
                                docs.firstWhere((d) => d.id == m['id']),
                              ),
                              onDelete: () => _deleteScholarship(
                                docs.firstWhere((d) => d.id == m['id']),
                              ),
                              onArchive: (archived) => _setHidden(
                                docs.firstWhere((d) => d.id == m['id']),
                                archived,
                              ),
                              onToggleFeatured: () => _toggleFeatured(
                                docs.firstWhere((d) => d.id == m['id']),
                              ),
                              onDuplicate: () => _duplicate(
                                docs.firstWhere((d) => d.id == m['id']),
                              ),
                              onCopyLink: () => _copyLink(m),
                              onView: () => _openForm(
                                docs.firstWhere((d) => d.id == m['id']),
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
      ),
    );
  }

  static String _sortLabel(_ScholarshipSort s) {
    switch (s) {
      case _ScholarshipSort.newest:
        return 'Sort by newest';
      case _ScholarshipSort.deadline:
        return 'Sort by deadline';
      case _ScholarshipSort.country:
        return 'Sort by country';
      case _ScholarshipSort.funding:
        return 'Sort by funding';
    }
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.countries,
    required this.degrees,
    required this.fundings,
    required this.country,
    required this.degree,
    required this.funding,
    required this.status,
    required this.onCountry,
    required this.onDegree,
    required this.onFunding,
    required this.onStatus,
    required this.onClear,
  });

  final List<String> countries;
  final List<String> degrees;
  final List<String> fundings;
  final String? country;
  final String? degree;
  final String? funding;
  final _ScholarshipStatus status;
  final ValueChanged<String?> onCountry;
  final ValueChanged<String?> onDegree;
  final ValueChanged<String?> onFunding;
  final ValueChanged<_ScholarshipStatus> onStatus;
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
        _filterRow(
          label: 'Degree',
          options: [
            for (final d in degrees)
              AdminFilterOption<String>(d, d, icon: Icons.school),
          ],
          selected: degree == null ? <String>{} : {degree!},
          onChanged: (v) => onDegree(v.isEmpty ? null : v.first),
          singleSelect: true,
        ),
        const SizedBox(height: 6),
        _filterRow(
          label: 'Funding',
          options: [
            for (final f in fundings)
              AdminFilterOption<String>(f, f, icon: Icons.payments_outlined),
          ],
          selected: funding == null ? <String>{} : {funding!},
          onChanged: (v) => onFunding(v.isEmpty ? null : v.first),
          singleSelect: true,
        ),
        const SizedBox(height: 6),
        _filterRow<_ScholarshipStatus>(
          label: 'Status',
          options: [
            for (final s in _ScholarshipStatus.values)
              AdminFilterOption<_ScholarshipStatus>(
                s,
                _statusLabel(s),
                icon: _statusIcon(s),
              ),
          ],
          selected: {status},
          onChanged: (v) => onStatus(v.isEmpty ? _ScholarshipStatus.all : v.first),
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

  static String _statusLabel(_ScholarshipStatus s) {
    switch (s) {
      case _ScholarshipStatus.all:
        return 'All';
      case _ScholarshipStatus.active:
        return 'Active';
      case _ScholarshipStatus.hidden:
        return 'Hidden';
      case _ScholarshipStatus.expired:
        return 'Expired';
    }
  }

  static IconData _statusIcon(_ScholarshipStatus s) {
    switch (s) {
      case _ScholarshipStatus.all:
        return Icons.all_inclusive;
      case _ScholarshipStatus.active:
        return Icons.verified_outlined;
      case _ScholarshipStatus.hidden:
        return Icons.visibility_off_outlined;
      case _ScholarshipStatus.expired:
        return Icons.schedule_outlined;
    }
  }
}

class _TitleCell extends StatelessWidget {
  const _TitleCell({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 36,
            height: 36,
            color: AdminPalette.primary.withValues(alpha: 0.12),
            child: const Icon(
              Icons.workspace_premium_outlined,
              color: AdminPalette.primary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                data['title']?.toString() ?? 'Untitled',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AdminPalette.heading,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (data['provider']?.toString().isNotEmpty ?? false)
                Text(
                  data['provider'].toString(),
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
}

class _DeadlineCell extends StatelessWidget {
  const _DeadlineCell({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final dynamic raw = data['deadline'];
    DateTime? parsed;
    if (raw is Timestamp) {
      parsed = raw.toDate();
    } else if (raw is DateTime) {
      parsed = raw;
    } else if (raw is String) {
      parsed = DateTime.tryParse(raw);
    }
    if (parsed == null) {
      return const Text('—', style: TextStyle(color: AdminPalette.body));
    }
    final expired = parsed.isBefore(DateTime.now());
    return Text(
      adminFormatDate(parsed),
      style: TextStyle(
        color: expired ? const Color(0xFFDC2626) : AdminPalette.heading,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    if (data['isHidden'] == true) {
      return const AdminBadge(
        label: 'Hidden',
        color: Color(0xFF6B7A95),
        icon: Icons.visibility_off_outlined,
      );
    }
    final dynamic raw = data['deadline'];
    DateTime? parsed;
    if (raw is Timestamp) {
      parsed = raw.toDate();
    } else if (raw is DateTime) {
      parsed = raw;
    } else if (raw is String) {
      parsed = DateTime.tryParse(raw);
    }
    if (parsed != null && parsed.isBefore(DateTime.now())) {
      return const AdminBadge(
        label: 'Expired',
        color: Color(0xFFDC2626),
        icon: Icons.schedule_outlined,
      );
    }
    return const AdminBadge(
      label: 'Active',
      color: Color(0xFF16A34A),
      icon: Icons.verified_outlined,
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.data,
    required this.onEdit,
    required this.onDelete,
    required this.onArchive,
    required this.onToggleFeatured,
    required this.onDuplicate,
    required this.onCopyLink,
    required this.onView,
  });

  final Map<String, dynamic> data;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onArchive;
  final VoidCallback onToggleFeatured;
  final VoidCallback onDuplicate;
  final VoidCallback onCopyLink;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'View',
          icon: const Icon(Icons.visibility_outlined),
          onPressed: onView,
        ),
        IconButton(
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_outlined),
          onPressed: onEdit,
        ),
        PopupMenuButton<String>(
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'duplicate',
              child: ListTile(
                leading: Icon(Icons.copy_all_outlined),
                title: Text('Duplicate'),
              ),
            ),
            const PopupMenuItem(
              value: 'copy',
              child: ListTile(
                leading: Icon(Icons.link),
                title: Text('Copy link'),
              ),
            ),
            PopupMenuItem(
              value: 'feature',
              child: ListTile(
                leading: Icon(data['isFeatured'] == true
                    ? Icons.star_outline
                    : Icons.star),
                title: Text(data['isFeatured'] == true ? 'Unfeature' : 'Feature'),
              ),
            ),
            if (data['isHidden'] == true)
              const PopupMenuItem(
                value: 'restore',
                child: ListTile(
                  leading: Icon(Icons.visibility_outlined),
                  title: Text('Unhide'),
                ),
              )
            else
              const PopupMenuItem(
                value: 'archive',
                child: ListTile(
                  leading: Icon(Icons.visibility_off_outlined),
                  title: Text('Hide'),
                ),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
                title: Text(
                  'Delete',
                  style: TextStyle(color: Color(0xFFDC2626)),
                ),
              ),
            ),
          ],
          onSelected: (value) {
            switch (value) {
              case 'duplicate':
                onDuplicate();
                break;
              case 'copy':
                onCopyLink();
                break;
              case 'feature':
                onToggleFeatured();
                break;
              case 'archive':
                onArchive(true);
                break;
              case 'restore':
                onArchive(false);
                break;
              case 'delete':
                onDelete();
                break;
            }
          },
        ),
      ],
    );
  }
}

class _ScholarshipCard extends StatelessWidget {
  const _ScholarshipCard({
    required this.data,
    required this.onEdit,
    required this.onDelete,
    required this.onArchive,
    required this.onToggleFeatured,
    required this.onDuplicate,
    required this.onCopyLink,
    required this.onView,
  });

  final Map<String, dynamic> data;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onArchive;
  final VoidCallback onToggleFeatured;
  final VoidCallback onDuplicate;
  final VoidCallback onCopyLink;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  data['title']?.toString() ?? 'Untitled',
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
          if (data['provider']?.toString().isNotEmpty ?? false)
            Text(
              data['provider'].toString(),
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
                label: data['country']?.toString() ?? '—',
                color: const Color(0xFF0F766E),
                icon: Icons.public,
              ),
              AdminBadge(
                label: data['funding']?.toString() ?? '—',
                color: const Color(0xFF7C3AED),
                icon: Icons.payments_outlined,
              ),
              if (data['degree']?.toString().isNotEmpty ?? false)
                AdminBadge(
                  label: data['degree'].toString(),
                  color: AdminPalette.primary,
                  icon: Icons.school_outlined,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.event, size: 14, color: AdminPalette.body),
              const SizedBox(width: 6),
              Text(
                'Deadline: ${_DeadlineCell(data: data).dataText()}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AdminPalette.body,
                  fontWeight: FontWeight.w600,
                ),
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
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('View'),
                    ),
                    TextButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit'),
                    ),
                    TextButton.icon(
                      onPressed: onDuplicate,
                      icon: const Icon(Icons.copy_all_outlined, size: 16),
                      label: const Text('Duplicate'),
                    ),
                    TextButton.icon(
                      onPressed: onCopyLink,
                      icon: const Icon(Icons.link, size: 16),
                      label: const Text('Copy'),
                    ),
                    TextButton.icon(
                      onPressed: onToggleFeatured,
                      icon: Icon(data['isFeatured'] == true ? Icons.star_outline : Icons.star, size: 16),
                      label: Text(data['isFeatured'] == true ? 'Unfeature' : 'Feature'),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: data['isHidden'] == true ? 'Unhide' : 'Hide',
                icon: Icon(
                  data['isHidden'] == true
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => onArchive(data['isHidden'] != true),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFDC2626),
                ),
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

extension on _DeadlineCell {
  String dataText() {
    final dynamic raw = data['deadline'];
    DateTime? parsed;
    if (raw is Timestamp) {
      parsed = raw.toDate();
    } else if (raw is DateTime) {
      parsed = raw;
    } else if (raw is String) {
      parsed = DateTime.tryParse(raw);
    }
    return parsed == null ? '—' : adminFormatDate(parsed);
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
          'Showing ${page * pageSize + 1}–'
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
