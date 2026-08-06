/// Admin user management page.
///
/// Streams the Firestore `users` collection, supports:
///   * Free-text search across name / email / phone
///   * Filter chips: country, premium, verified, suspended
///   * Sort: newest, name, country, last login
///   * Profile-completeness indicator
///   * Avatar + verification / premium / suspended badges
///   * Quick actions: view, verify, toggle premium, suspend, restore, delete
///   * Confirmation dialogs for destructive actions
///   * Empty state + loading skeleton
///   * Pagination (10 per page)
///   * Responsive desktop table / mobile card layout
///
/// All existing CRUD behaviour is preserved — only the UI layer is
/// upgraded.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/scholarbird_theme.dart';
import 'admin_ui.dart';
import 'widgets/admin_badge.dart';
import 'widgets/admin_data_table.dart';
import 'widgets/admin_dialogs.dart';
import 'widgets/admin_empty_state.dart';
import 'widgets/admin_filter_bar.dart';
import 'widgets/admin_search_bar.dart';
import 'widgets/admin_section.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

enum _UserSort { newest, name, country, lastLogin }
enum _UserPremium { all, premium, free }
enum _UserVerified { all, verified, unverified }
enum _UserStatus { all, suspended, active }

bool _isPremium(Map<String, dynamic> data) {
  if (data['premium'] == true) return true;
  if (data['subscriptionStatus']?.toString().toLowerCase() != 'premium') return false;
  final value = data['subscriptionExpiry'];
  final expiry = value is Timestamp
      ? value.toDate()
      : value is DateTime
          ? value
          : value is String
              ? DateTime.tryParse(value)
              : null;
  return expiry == null || expiry.isAfter(DateTime.now());
}

/// Mirrors the completion markers written by the three profile workflows.
/// A user who completed Basic Profile, Academic Profile, and Preferences is
/// complete even when optional fields such as an avatar or biography are blank.
int _profileCompletenessValue(Map<String, dynamic> data) {
  if (data['profileCompleted'] == true &&
      data['academicProfileCompleted'] == true &&
      data['preferencesCompleted'] == true) {
    return 100;
  }

  var filled = 0;
  const fields = [
    'name',
    'displayName',
    'email',
    'phone',
    'country',
    'university',
    'department',
    'degree',
  ];
  for (final field in fields) {
    final value = data[field];
    if (value is String && value.trim().isNotEmpty) filled++;
    if (value is num || value is Timestamp) filled++;
  }
  return ((filled / fields.length) * 100).round();
}

class _UsersPageState extends State<UsersPage> {
  final _firestore = FirebaseFirestore.instance;
  final _searchCtrl = TextEditingController();

  String _query = '';
  String? _countryFilter;
  _UserPremium _premiumFilter = _UserPremium.all;
  _UserVerified _verifiedFilter = _UserVerified.all;
  _UserStatus _statusFilter = _UserStatus.all;
  _UserSort _sort = _UserSort.newest;
  int _page = 0;
  static const int _pageSize = 10;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _updateFlag(
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

  Future<void> _delete(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final confirmed = await AdminDialogs.confirm(
      context: context,
      title: 'Delete user?',
      message:
          'This permanently removes the user document and revokes access. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    try {
      await document.reference.delete();
      if (!mounted) return;
      AdminDialogs.success(context, 'User deleted');
    } catch (e) {
      if (!mounted) return;
      AdminDialogs.error(context, 'Delete failed: $e');
    }
  }

  Future<void> _suspend(
    DocumentSnapshot<Map<String, dynamic>> document,
    bool suspended,
  ) async {
    await _updateFlag(document, 'suspended', suspended);
    if (!mounted) return;
    AdminDialogs.success(
      context,
      suspended ? 'User suspended' : 'User restored',
    );
  }

  Future<void> _verify(
    DocumentSnapshot<Map<String, dynamic>> document,
    bool verified,
  ) async {
    await _updateFlag(document, 'verified', verified);
    if (!mounted) return;
    AdminDialogs.success(
      context,
      verified ? 'User verified' : 'Verification removed',
    );
  }

  Future<void> _togglePremium(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final data = document.data() ?? <String, dynamic>{};
    final next = !_isPremium(data);
    try {
      await document.reference.update({
        // Keep the legacy flag for existing clients while updating the
        // canonical subscription fields consumed by SubscriptionService.
        'premium': next,
        'subscriptionStatus': next ? 'premium' : 'free',
        'subscriptionExpiry': next
            ? Timestamp.fromDate(DateTime.now().add(const Duration(days: 30)))
            : FieldValue.delete(),
        'premiumUpdatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) AdminDialogs.success(context, next ? 'Premium granted' : 'Premium removed');
    } catch (e) {
      if (mounted) AdminDialogs.error(context, 'Premium update failed: $e');
    }
  }

  Future<void> _copyEmail(Map<String, dynamic> data) async {
    final email = data['email']?.toString() ?? '';
    if (email.isEmpty) {
      AdminDialogs.error(context, 'No email to copy.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: email));
    if (!mounted) return;
    AdminDialogs.success(context, 'Email copied to clipboard');
  }

  Future<void> _toggleAdmin(DocumentSnapshot<Map<String, dynamic>> document) async {
    final role = document.data()?['role']?.toString();
    final next = role == 'admin' ? 'user' : 'admin';
    try {
      await document.reference.update({'role': next, 'roleUpdatedAt': FieldValue.serverTimestamp()});
      if (mounted) AdminDialogs.success(context, next == 'admin' ? 'Admin access granted' : 'Admin access removed');
    } catch (e) {
      if (mounted) AdminDialogs.error(context, 'Role update failed: $e');
    }
  }

  Future<void> _showUserProfile(Map<String, dynamic> data) async {
    await AdminDialogs.confirm(
        context: context,
        title: data['name']?.toString() ?? data['displayName']?.toString() ?? 'User profile',
        message: 'Email: ${data['email'] ?? '—'}\n'
            'Country: ${data['country'] ?? '—'}\n'
            'Role: ${data['role'] ?? 'user'}\n'
            'Subscription: ${_isPremium(data) ? 'Premium' : 'Free'}\n'
            'Status: ${data['suspended'] == true ? 'Suspended' : 'Active'}',
        confirmLabel: 'Close',
        cancelLabel: '',
      );
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
      data['name'],
      data['displayName'],
      data['email'],
      data['phone'],
      data['country'],
    ].whereType<Object>().map((e) => e.toString().toLowerCase()).join(' ');
    return haystack.contains(_query);
  }

  bool _matchesStatus(Map<String, dynamic> data) {
    switch (_statusFilter) {
      case _UserStatus.all:
        return true;
      case _UserStatus.suspended:
        return data['suspended'] == true;
      case _UserStatus.active:
        return data['suspended'] != true;
    }
  }

  bool _matchesPremium(Map<String, dynamic> data) {
    switch (_premiumFilter) {
      case _UserPremium.all:
        return true;
      case _UserPremium.premium:
        return _isPremium(data);
      case _UserPremium.free:
        return !_isPremium(data);
    }
  }

  bool _matchesVerified(Map<String, dynamic> data) {
    switch (_verifiedFilter) {
      case _UserVerified.all:
        return true;
      case _UserVerified.verified:
        return data['verified'] == true;
      case _UserVerified.unverified:
        return data['verified'] != true;
    }
  }

  int _profileCompleteness(Map<String, dynamic> data) {
    return _profileCompletenessValue(data);
  }

  List<Map<String, dynamic>> _applyFilters(
    List<DocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final list = docs
        .map((d) => <String, dynamic>{'id': d.id, ...?d.data()})
        .where(_matchesSearch)
        .where(_matchesStatus)
        .where(_matchesPremium)
        .where(_matchesVerified)
        .where((m) {
          if (_countryFilter == null) return true;
          return m['country']?.toString().toLowerCase() ==
              _countryFilter!.toLowerCase();
        })
        .toList();

    switch (_sort) {
      case _UserSort.newest:
        list.sort((a, b) {
          final ad = _dateValue(a, 'createdAt');
          final bd = _dateValue(b, 'createdAt');
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return bd.compareTo(ad);
        });
        break;
      case _UserSort.name:
        list.sort((a, b) =>
            (a['name']?.toString() ?? a['displayName']?.toString() ?? '')
                .compareTo(
              b['name']?.toString() ?? b['displayName']?.toString() ?? '',
            ));
        break;
      case _UserSort.country:
        list.sort((a, b) =>
            (a['country']?.toString() ?? '').compareTo(
              b['country']?.toString() ?? '',
            ));
        break;
      case _UserSort.lastLogin:
        list.sort((a, b) {
          final ad = _dateValue(a, 'lastLogin');
          final bd = _dateValue(b, 'lastLogin');
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return bd.compareTo(ad);
        });
        break;
    }
    return list;
  }

  bool get _hasActiveFilters =>
      _countryFilter != null ||
      _premiumFilter != _UserPremium.all ||
      _verifiedFilter != _UserVerified.all ||
      _statusFilter != _UserStatus.all;

  void _clearFilters() => setState(() {
        _countryFilter = null;
        _premiumFilter = _UserPremium.all;
        _verifiedFilter = _UserVerified.all;
        _statusFilter = _UserStatus.all;
        _page = 0;
      });

  Future<void> _showFilters({required List<String> countries}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => SafeArea(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 500),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFFD7DDEA), borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 18),
              Row(children: [
                const Icon(Icons.tune_rounded, color: AdminPalette.primary),
                const SizedBox(width: 10),
                const Expanded(child: Text('Filter users', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                TextButton(onPressed: _clearFilters, child: const Text('Reset')),
              ]),
              const SizedBox(height: 8),
              Expanded(child: SingleChildScrollView(child: _FilterRow(
                countries: countries,
                country: _countryFilter, premium: _premiumFilter,
                verified: _verifiedFilter, status: _statusFilter,
                onCountry: (v) => setState(() { _countryFilter = v; _page = 0; }),
                onPremium: (v) => setState(() { _premiumFilter = v; _page = 0; }),
                onVerified: (v) => setState(() { _verifiedFilter = v; _page = 0; }),
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
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // Local sorting keeps older profiles with no `createdAt` visible.
        stream: _firestore.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(ScholarBirdSpacing.large),
                child: Text('Could not load users: ${snapshot.error}'),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: AdminLoadingSkeleton(itemCount: 6, itemHeight: 88),
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

          return SingleChildScrollView(
            padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdminPageHeader(
                  title: 'Users',
                  subtitle:
                      '${filtered.length} of ${docs.length} users shown',
                  actions: [
                    FilledButton.icon(
                      onPressed: () => AdminDialogs.success(
                        context,
                        'Users are created via signup. Use search to find one.',
                      ),
                      icon: const Icon(Icons.info_outline),
                      label: const Text('How to add'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AdminPalette.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                AdminSection(
                  title: 'All users',
                  subtitle:
                      'Manage profiles, verify accounts, handle suspensions.',
                  icon: Icons.people_alt_outlined,
                  action: PopupMenuButton<_UserSort>(
                    tooltip: 'Sort',
                    icon: const Icon(Icons.sort, color: AdminPalette.heading),
                    onSelected: (value) => setState(() => _sort = value),
                    itemBuilder: (_) => [
                      for (final s in _UserSort.values)
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
                        onFilterTap: () => _showFilters(countries: countries),
                        hintText: 'Search by name, email, phone, or country…',
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
                          icon: Icons.person_search_outlined,
                          title: 'No users match the filters',
                          message:
                              'Try clearing the filters or searching with a different term.',
                        )
                      else
                        AdminDataTable<Map<String, dynamic>>(
                          columns: const [
                            AdminTableColumn(label: 'User'),
                            AdminTableColumn(label: 'Country'),
                            AdminTableColumn(label: 'Status'),
                            AdminTableColumn(label: 'Profile'),
                            AdminTableColumn(label: 'Last login'),
                            AdminTableColumn(label: 'Actions'),
                          ],
                          rows: pageItems,
                          cardBuilder: (m) => _UserCard(
                            data: m,
                            onView: () => _showUserProfile(m),
                            onVerify: () => _verify(
                              docs.firstWhere((d) => d.id == m['id']),
                              m['verified'] != true,
                            ),
                            onTogglePremium: () => _togglePremium(
                              docs.firstWhere((d) => d.id == m['id']),
                            ),
                            onSuspend: (suspended) => _suspend(
                              docs.firstWhere((d) => d.id == m['id']),
                              suspended,
                            ),
                            onDelete: () => _delete(
                              docs.firstWhere((d) => d.id == m['id']),
                            ),
                            onCopyEmail: () => _copyEmail(m),
                            onToggleAdmin: () => _toggleAdmin(docs.firstWhere((d) => d.id == m['id'])),
                          ),
                          rowBuilder: (m) => [
                            DataCell(
                              _UserCell(data: m),
                              onTap: () => _showUserProfile(m),
                            ),
                            DataCell(AdminBadge(
                              label: m['country']?.toString() ?? '—',
                              color: const Color(0xFF0F766E),
                              icon: Icons.public,
                            )),
                            DataCell(_StatusBadges(data: m)),
                            DataCell(_Completeness(value: _profileCompleteness(m))),
                            DataCell(_LastLoginCell(data: m)),
                            DataCell(_QuickActions(
                              data: m,
                              onView: () => _showUserProfile(m),
                              onVerify: () => _verify(
                                docs.firstWhere((d) => d.id == m['id']),
                                m['verified'] != true,
                              ),
                              onTogglePremium: () => _togglePremium(
                                docs.firstWhere((d) => d.id == m['id']),
                              ),
                              onSuspend: (suspended) => _suspend(
                                docs.firstWhere((d) => d.id == m['id']),
                                suspended,
                              ),
                              onDelete: () => _delete(
                                docs.firstWhere((d) => d.id == m['id']),
                              ),
                              onCopyEmail: () => _copyEmail(m),
                              onToggleAdmin: () => _toggleAdmin(docs.firstWhere((d) => d.id == m['id'])),
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

  static String _sortLabel(_UserSort s) {
    switch (s) {
      case _UserSort.newest:
        return 'Newest first';
      case _UserSort.name:
        return 'Sort by name';
      case _UserSort.country:
        return 'Sort by country';
      case _UserSort.lastLogin:
        return 'Last login';
    }
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.countries,
    required this.country,
    required this.premium,
    required this.verified,
    required this.status,
    required this.onCountry,
    required this.onPremium,
    required this.onVerified,
    required this.onStatus,
    required this.onClear,
  });

  final List<String> countries;
  final String? country;
  final _UserPremium premium;
  final _UserVerified verified;
  final _UserStatus status;
  final ValueChanged<String?> onCountry;
  final ValueChanged<_UserPremium> onPremium;
  final ValueChanged<_UserVerified> onVerified;
  final ValueChanged<_UserStatus> onStatus;
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
        _filterRow<_UserPremium>(
          label: 'Plan',
          options: const [
            AdminFilterOption<_UserPremium>(
              _UserPremium.all,
              'All',
              icon: Icons.all_inclusive,
            ),
            AdminFilterOption<_UserPremium>(
              _UserPremium.premium,
              'Premium',
              icon: Icons.workspace_premium,
            ),
            AdminFilterOption<_UserPremium>(
              _UserPremium.free,
              'Free',
              icon: Icons.person_outline,
            ),
          ],
          selected: {premium},
          onChanged: (v) => onPremium(v.isEmpty ? _UserPremium.all : v.first),
          singleSelect: true,
        ),
        const SizedBox(height: 6),
        _filterRow<_UserVerified>(
          label: 'Verified',
          options: const [
            AdminFilterOption<_UserVerified>(
              _UserVerified.all,
              'All',
              icon: Icons.all_inclusive,
            ),
            AdminFilterOption<_UserVerified>(
              _UserVerified.verified,
              'Verified',
              icon: Icons.verified_outlined,
            ),
            AdminFilterOption<_UserVerified>(
              _UserVerified.unverified,
              'Unverified',
              icon: Icons.help_outline,
            ),
          ],
          selected: {verified},
          onChanged: (v) =>
              onVerified(v.isEmpty ? _UserVerified.all : v.first),
          singleSelect: true,
        ),
        const SizedBox(height: 6),
        _filterRow<_UserStatus>(
          label: 'Status',
          options: const [
            AdminFilterOption<_UserStatus>(
              _UserStatus.all,
              'All',
              icon: Icons.all_inclusive,
            ),
            AdminFilterOption<_UserStatus>(
              _UserStatus.active,
              'Active',
              icon: Icons.check_circle_outline,
            ),
            AdminFilterOption<_UserStatus>(
              _UserStatus.suspended,
              'Suspended',
              icon: Icons.block_outlined,
            ),
          ],
          selected: {status},
          onChanged: (v) => onStatus(v.isEmpty ? _UserStatus.all : v.first),
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
}

class _UserCell extends StatelessWidget {
  const _UserCell({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final name = data['name']?.toString() ??
        data['displayName']?.toString() ??
        'Unnamed';
    final email = data['email']?.toString() ?? '';
    final avatar = data['avatar']?.toString() ?? '';
    final initials = _initials(name);
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AdminPalette.primary.withValues(alpha: 0.12),
          backgroundImage: avatar.isEmpty ? null : NetworkImage(avatar),
          onBackgroundImageError: avatar.isEmpty
              ? null
              : (_, __) {},
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
              if (email.isNotEmpty)
                Text(
                  email,
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

class _StatusBadges extends StatelessWidget {
  const _StatusBadges({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (data['verified'] == true) {
      chips.add(const AdminBadge(
        label: 'Verified',
        color: Color(0xFF16A34A),
        icon: Icons.verified_outlined,
      ));
    } else {
      chips.add(const AdminBadge(
        label: 'Unverified',
        color: Color(0xFF6B7A95),
        icon: Icons.help_outline,
      ));
    }
    if (_isPremium(data)) {
      chips.add(const AdminBadge(
        label: 'Premium',
        color: Color(0xFF7C3AED),
        icon: Icons.workspace_premium,
      ));
    }
    if (data['suspended'] == true) {
      chips.add(const AdminBadge(
        label: 'Suspended',
        color: Color(0xFFDC2626),
        icon: Icons.block_outlined,
      ));
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: chips,
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

class _LastLoginCell extends StatelessWidget {
  const _LastLoginCell({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final dynamic raw = data['lastLogin'];
    DateTime? parsed;
    if (raw is Timestamp) {
      parsed = raw.toDate();
    } else if (raw is DateTime) {
      parsed = raw;
    } else if (raw is String) {
      parsed = DateTime.tryParse(raw);
    }
    if (parsed == null) {
      return const Text('Never', style: TextStyle(color: AdminPalette.body));
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

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.data,
    required this.onView,
    required this.onVerify,
    required this.onTogglePremium,
    required this.onSuspend,
    required this.onDelete,
    required this.onCopyEmail,
    required this.onToggleAdmin,
  });

  final Map<String, dynamic> data;
  final VoidCallback onView;
  final VoidCallback onVerify;
  final VoidCallback onTogglePremium;
  final ValueChanged<bool> onSuspend;
  final VoidCallback onDelete;
  final VoidCallback onCopyEmail;
  final VoidCallback onToggleAdmin;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'View profile',
          icon: const Icon(Icons.visibility_outlined),
          onPressed: onView,
        ),
        IconButton(
          tooltip: data['verified'] == true ? 'Unverify' : 'Verify',
          icon: Icon(
            data['verified'] == true
                ? Icons.verified_outlined
                : Icons.verified_outlined,
            color: data['verified'] == true
                ? const Color(0xFF16A34A)
                : AdminPalette.body,
          ),
          onPressed: onVerify,
        ),
        IconButton(
          tooltip: _isPremium(data) ? 'Remove premium' : 'Grant premium',
          icon: Icon(
            Icons.workspace_premium,
            color: _isPremium(data)
                ? const Color(0xFF7C3AED)
                : AdminPalette.body,
          ),
          onPressed: onTogglePremium,
        ),
        PopupMenuButton<String>(
          itemBuilder: (_) => [
            if (data['suspended'] == true)
              const PopupMenuItem(
                value: 'restore',
                child: ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('Restore'),
                ),
              )
            else
              const PopupMenuItem(
                value: 'suspend',
                child: ListTile(
                  leading: Icon(Icons.block_outlined),
                  title: Text('Suspend'),
                ),
              ),
            const PopupMenuItem(
              value: 'copy',
              child: ListTile(
                leading: Icon(Icons.email_outlined),
                title: Text('Copy email'),
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'role',
              child: ListTile(
                leading: Icon(data['role'] == 'admin' ? Icons.person_remove_outlined : Icons.admin_panel_settings_outlined),
                title: Text(data['role'] == 'admin' ? 'Remove admin role' : 'Make admin'),
              ),
            ),
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
              case 'restore':
                onSuspend(false);
                break;
              case 'suspend':
                onSuspend(true);
                break;
              case 'copy':
                onCopyEmail();
                break;
              case 'delete':
                onDelete();
                break;
              case 'role':
                onToggleAdmin();
                break;
            }
          },
        ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.data,
    required this.onView,
    required this.onVerify,
    required this.onTogglePremium,
    required this.onSuspend,
    required this.onDelete,
    required this.onCopyEmail,
    required this.onToggleAdmin,
  });

  final Map<String, dynamic> data;
  final VoidCallback onView;
  final VoidCallback onVerify;
  final VoidCallback onTogglePremium;
  final ValueChanged<bool> onSuspend;
  final VoidCallback onDelete;
  final VoidCallback onCopyEmail;
  final VoidCallback onToggleAdmin;

  @override
  Widget build(BuildContext context) {
    final name = data['name']?.toString() ??
        data['displayName']?.toString() ??
        'Unnamed';
    final completeness = _profileCompletenessInline(data);
    final avatar = data['avatar']?.toString() ?? '';
    return AdminSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AdminPalette.primary.withValues(alpha: 0.12),
                backgroundImage: avatar.isEmpty ? null : NetworkImage(avatar),
                onBackgroundImageError: avatar.isEmpty ? null : (_, __) {},
                child: avatar.isEmpty
                    ? Text(
                        _UserCell._initials(name.substring(
                          0,
                          name.length > 1 ? 1 : name.length,
                        )),
                        style: const TextStyle(
                          color: AdminPalette.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AdminPalette.heading,
                      ),
                    ),
                    if ((data['email']?.toString().isNotEmpty ?? false))
                      Text(
                        data['email'].toString(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AdminPalette.body,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              AdminBadge(
                label: data['country']?.toString() ?? 'No country',
                color: const Color(0xFF0F766E),
                icon: Icons.public,
              ),
              AdminBadge(
                label: _isPremium(data) ? 'Premium' : 'Free',
                color: _isPremium(data)
                    ? const Color(0xFF7C3AED)
                    : const Color(0xFF6B7A95),
                icon: Icons.workspace_premium,
              ),
              AdminBadge(
                label: data['verified'] == true ? 'Verified' : 'Unverified',
                color: data['verified'] == true
                    ? const Color(0xFF16A34A)
                    : const Color(0xFF6B7A95),
                icon: Icons.verified_outlined,
              ),
              if (data['suspended'] == true)
                const AdminBadge(
                  label: 'Suspended',
                  color: Color(0xFFDC2626),
                  icon: Icons.block_outlined,
                ),
            ],
          ),
          const SizedBox(height: 12),
          _Completeness(value: completeness),
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
                      onPressed: onVerify,
                      icon: const Icon(Icons.verified_outlined, size: 16),
                      label: Text(
                        data['verified'] == true ? 'Unverify' : 'Verify',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onTogglePremium,
                      icon: const Icon(Icons.workspace_premium, size: 16),
                      label: Text(
                        _isPremium(data)
                            ? 'Remove premium'
                            : 'Grant premium',
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: data['role'] == 'admin' ? 'Remove admin role' : 'Make admin',
                icon: const Icon(Icons.admin_panel_settings_outlined),
                onPressed: onToggleAdmin,
              ),
              IconButton(
                tooltip: data['suspended'] == true ? 'Restore' : 'Suspend',
                icon: Icon(
                  data['suspended'] == true
                      ? Icons.check_circle_outline
                      : Icons.block_outlined,
                ),
                onPressed: () => onSuspend(data['suspended'] != true),
              ),
              IconButton(
                tooltip: 'Copy email',
                icon: const Icon(Icons.email_outlined),
                onPressed: onCopyEmail,
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

  static int _profileCompletenessInline(Map<String, dynamic> data) {
    return _profileCompletenessValue(data);
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
