/// Search and browse screen for the full scholarship catalog.
library;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ScholarBird/screens/scholarship/scholarship_details.dart';
import 'package:ScholarBird/widgets/scholarship_ui.dart';
import '../../widgets/premium_feature.dart';
import '../../widgets/premium_guard.dart';
import '../../widgets/saved_scholarship_controls.dart';

/// Builds a fast, 200ms fade page route to replace MaterialPageRoute's default
/// 300ms slide. Keeps the rest of the app snappier without changing UX flow.
PageRouteBuilder<T> _fastPageRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    );

/// Manages filtering, sorting, and navigation for scholarship search results.
class ScholarshipsScreen extends StatefulWidget {
  const ScholarshipsScreen({super.key, this.onMenuTap});

  final VoidCallback? onMenuTap;

  @override
  State<ScholarshipsScreen> createState() => _ScholarshipsScreenState();
}

class _ScholarshipsScreenState extends State<ScholarshipsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _cachedDocuments;
  List<Map<String, dynamic>> _cachedScholarships = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _cachedOptionDocuments;
  final Map<String, List<String>> _optionCache = {};

  String _selectedField = '';
  String _selectedDegree = '';
  String _selectedCountry = '';
  String _selectedFunding = '';
  String _selectedDeadline = '';
  int? _selectedDeadlineMonth;
  String _selectedIelts = '';
  String _selectedEnglishMedium = '';
  String _selectedResearch = '';
  double? _maximumMinCgpa;
  int? _maximumBacklogs;
  List<String> _searchTokens = const [];
  String _selectedSort = 'Deadline: Ascending';

  // Memoization for the filter pipeline. _lastFilterSignature lets us skip the
  // filter pass entirely when the user toggles between two filter combinations
  // that produce the same result set (e.g. clearing a chip that was already
  // empty). _cachedFiltered keeps the previous result list around for the
  // signature match path.
  String _lastFilterSignature = '';
  List<Map<String, dynamic>> _cachedFiltered = const [];

  // Debounce timer for search input. Without it, every keystroke triggers a
  // full filter+sort pass over the entire scholarships list, which makes the
  // UI feel laggy on large datasets.
  Timer? _searchDebounce;

  static const List<String> sortOptions = [
    'Most Relevant',
    'Newest',
    'Deadline: Ascending',
    'Deadline: Descending',
    'Deadline Soon',
    'Fully Funded First',
    'Alphabetical',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final raw = _searchController.text.trim().toLowerCase();
      setState(() {
        _searchTokens = raw.isEmpty
            ? const []
            : raw.split(RegExp(r'\s+'));
      });
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  List<String> _collectOptions(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, String key) {
    if (!identical(_cachedOptionDocuments, docs)) {
      _cachedOptionDocuments = docs;
      _optionCache.clear();
    }
    final cached = _optionCache[key];
    if (cached != null) return cached;
    final values = <String>{};
    for (final doc in docs) {
      final data = doc.data();
      final raw = data[key];
      if (raw == null) continue;
      final value = raw.toString().trim();
      if (value.isNotEmpty) {
        values.add(value);
      }
    }
    final list = values.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return _optionCache[key] = list;
  }

  List<String> _withSelected(List<String> options, String selected) {
    if (selected.isEmpty || options.contains(selected)) {
      return options;
    }
    final merged = List<String>.from(options)..add(selected);
    merged.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return merged;
  }

  String _formatDegree(String value) {
    if (value.trim().toLowerCase() == "master's") {
      return 'Postgraduate';
    }
    return value;
  }

  String _normalizeDegree(String value) {
    final cleaned = value.trim().toLowerCase();
    if (cleaned == "master's" ||
        cleaned == 'masters' ||
        cleaned == 'postgraduate') {
      return 'postgraduate';
    }
    return cleaned;
  }

  List<String> _collectDegreeOptions(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final raw = _collectOptions(docs, 'degree');
    final mapped = raw.map(_formatDegree).toSet().toList();
    mapped.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return mapped;
  }

  bool _matchesFilters(Map<String, dynamic> scholarship) {
    if (_searchTokens.isNotEmpty) {
      // The upload pipeline supplies search_tokens. Fall back to the existing
      // document fields so older Firestore records remain searchable too.
      // Tokens are precomputed once per keystroke (debounced) instead of
      // recomputed per scholarship, so the filter stays O(n) without an
      // extra regex evaluation per row.
      final searchableValues = [
        scholarship['title'],
        scholarship['university'],
        scholarship['country'],
        scholarship['field'],
        scholarship['provider'],
        scholarship['description'],
        scholarship['keywords'],
        scholarship['tags'],
        scholarship['search_tokens'],
      ];
      final haystack = searchableValues
          .whereType<Object?>()
          .expand((value) => value is Iterable
              ? value.map((item) => item.toString())
              : [value.toString()])
          .join(' ')
          .toLowerCase();
      for (final token in _searchTokens) {
        if (!haystack.contains(token)) return false;
      }
    }

    if (_selectedField.isNotEmpty) {
      if (scholarship['field'].toString().toLowerCase() !=
          _selectedField.toLowerCase()) {
        return false;
      }
    }

    if (_selectedDegree.isNotEmpty) {
      if (_normalizeDegree(scholarship['degree'].toString()) !=
          _normalizeDegree(_selectedDegree)) {
        return false;
      }
    }

    if (_selectedCountry.isNotEmpty) {
      if (scholarship['country'].toString().toLowerCase() !=
          _selectedCountry.toLowerCase()) {
        return false;
      }
    }

    if (!_matchesText(scholarship, 'funding', _selectedFunding,
        fallbacks: const ['fundingType', 'amount'])) {
      return false;
    }
    if (!_matchesBoolean(scholarship, 'ieltsRequired', _selectedIelts)) {
      return false;
    }
    if (!_matchesBoolean(
        scholarship, 'englishMediumAccepted', _selectedEnglishMedium)) {
      return false;
    }
    if (!_matchesBoolean(scholarship, 'researchRequired', _selectedResearch)) {
      return false;
    }
    if (_maximumMinCgpa != null &&
        _number(scholarship['minCGPA'] ?? scholarship['minCgpa']) >
            _maximumMinCgpa!) {
      return false;
    }
    if (_maximumBacklogs != null &&
        _number(scholarship['maxBacklogs']).round() > _maximumBacklogs!) {
      return false;
    }
    if (_selectedDeadlineMonth != null &&
        _parseDeadline(scholarship['deadline']?.toString() ?? '')?.month !=
            _selectedDeadlineMonth) {
      return false;
    }

    return true;
  }

  bool _matchesText(Map<String, dynamic> value, String key, String selected,
      {List<String> fallbacks = const []}) {
    if (selected.isEmpty) return true;
    final candidates = [key, ...fallbacks]
        .map((field) => value[field]?.toString().toLowerCase() ?? '');
    return candidates.any((candidate) => candidate == selected.toLowerCase());
  }

  bool _matchesBoolean(
      Map<String, dynamic> value, String key, String selected) {
    if (selected.isEmpty) return true;
    return value[key] == (selected == 'Required' || selected == 'Accepted');
  }

  double _number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _selectedField =
          _selectedDegree = _selectedCountry = _selectedFunding = '';
      _selectedDeadline = '';
      _selectedDeadlineMonth = null;
      _selectedIelts = _selectedEnglishMedium = _selectedResearch = '';
      _maximumMinCgpa = null;
      _maximumBacklogs = null;
      _selectedSort = 'Deadline: Ascending';
    });
  }

  List<Map<String, dynamic>> _scholarshipsFor(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> documents) {
    // A filter/sort state change should not repeatedly deserialize a 10k item
    // Firestore snapshot. The cache is invalidated only by a new snapshot.
    if (!identical(_cachedDocuments, documents)) {
      _cachedDocuments = documents;
      _cachedScholarships =
          documents.map(_buildScholarshipData).toList(growable: false);
    }
    return _cachedScholarships;
  }

  /// Builds the filter options used by the chip row. Re-run only when the
  /// underlying document list identity changes, never on every keystroke.
  List<String> _fieldOptions(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) =>
      _withSelected(_collectOptions(docs, 'field'), _selectedField);

  List<String> _degreeOptions(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) =>
      _withSelected(_collectDegreeOptions(docs), _selectedDegree);

  List<String> _countryOptions(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) =>
      _withSelected(_collectOptions(docs, 'country'), _selectedCountry);

  List<String> _fundingOptions(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final merged = {
      ..._collectOptions(docs, 'funding'),
      ..._collectOptions(docs, 'fundingType'),
      ..._collectOptions(docs, 'amount'),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return _withSelected(merged, _selectedFunding);
  }

  /// Stable composite key for the dependencies that affect filter/sort output.
  /// Returning a single string lets us cheaply detect "nothing changed" without
  /// comparing the whole filter state field by field.
  String _filterSignature() => [
        _selectedField,
        _selectedDegree,
        _selectedCountry,
        _selectedFunding,
        _selectedDeadline,
        _selectedDeadlineMonth,
        _selectedIelts,
        _selectedEnglishMedium,
        _selectedResearch,
        _maximumMinCgpa,
        _maximumBacklogs,
        _selectedSort,
        _searchTokens.join(' '),
      ].join('|');

  /// Applies the active filter+sort to the cached scholarships list. Memoizes
  /// the output by filter signature, so flipping chips that don't change the
  /// result set skips the entire filter pass.
  List<Map<String, dynamic>> _applyFiltersAndSort() {
    final signature = _filterSignature();
    if (signature == _lastFilterSignature && _cachedFiltered.isNotEmpty) {
      return _cachedFiltered;
    }
    final all = _cachedScholarships;
    final filtered = all.where(_matchesFilters).toList(growable: false);
    final sorted = List<Map<String, dynamic>>.from(filtered);

    switch (_selectedSort) {
      case 'Deadline: Ascending':
      case 'Deadline: Descending':
      case 'Deadline Soon':
        sorted.sort((a, b) {
          final aDate = _parseDeadline(a['deadline'].toString());
          final bDate = _parseDeadline(b['deadline'].toString());
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          // Ascending = soonest first; Descending = furthest deadline first.
          final ascending =
              _selectedSort != 'Deadline: Descending';
          return ascending ? aDate.compareTo(bDate) : bDate.compareTo(aDate);
        });
        break;
      case 'Alphabetical':
        sorted.sort((a, b) => a['title']
            .toString()
            .toLowerCase()
            .compareTo(b['title'].toString().toLowerCase()));
        break;
      case 'Fully Funded First':
        sorted.sort((a, b) => _fundingRank(b).compareTo(_fundingRank(a)));
        break;
      case 'Newest':
        sorted.sort((a, b) => _newestValue(b).compareTo(_newestValue(a)));
        break;
    }

    _lastFilterSignature = signature;
    _cachedFiltered = sorted;
    return sorted;
  }

  String _getStatusBadge(Map<String, dynamic> s) {
    final amount = s['amount'].toString().toLowerCase();
    final deadline = s['deadline'].toString();

    if (amount.contains('full')) return 'FULL FUNDING';
    if (amount.contains('partial')) return 'PARTIAL GRANT';
    if (amount.contains('research')) return 'RESEARCH FELLOWSHIP';

    final deadlineDate = _parseDeadline(deadline);
    if (deadlineDate != null) {
      final daysLeft = deadlineDate.difference(DateTime.now()).inDays;
      if (daysLeft >= 0 && daysLeft <= 30) return 'CLOSING SOON';
    }

    return '';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'FULL FUNDING':
        return const Color(0xFF4CAF50);
      case 'PARTIAL GRANT':
        return const Color(0xFFFFC107);
      case 'RESEARCH FELLOWSHIP':
        return const Color(0xFF2196F3);
      case 'CLOSING SOON':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  DateTime? _parseDeadline(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final direct = DateTime.tryParse(trimmed);
    if (direct != null) return direct;

    final monthMap = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };

    final monthFirst = RegExp(
        r'^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2}),?\s*(\d{4})$');
    final dayFirst = RegExp(
        r'^(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s*(\d{4})$');

    final monthMatch = monthFirst.firstMatch(trimmed);
    if (monthMatch != null) {
      final month = monthMap[monthMatch.group(1)!.toLowerCase()];
      final day = int.tryParse(monthMatch.group(2) ?? '');
      final year = int.tryParse(monthMatch.group(3) ?? '');
      if (month != null && day != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    final dayMatch = dayFirst.firstMatch(trimmed);
    if (dayMatch != null) {
      final day = int.tryParse(dayMatch.group(1) ?? '');
      final month = monthMap[dayMatch.group(2)!.toLowerCase()];
      final year = int.tryParse(dayMatch.group(3) ?? '');
      if (month != null && day != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        body: SafeArea(
          child: Column(
            children: [
              Container(
                height: 72,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        tooltip: 'Open navigation menu',
                        onPressed: widget.onMenuTap,
                        icon: const Icon(Icons.menu_rounded),
                      ),
                    ),
                    const Text(
                      'Scholarships',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF5B7AE8)
                                  .withValues(alpha: 0.1),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search scholarships, majors...',
                            hintStyle: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 15,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: Colors.grey[400],
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? GestureDetector(
                                    onTap: _searchController.clear,
                                    child: Icon(Icons.close,
                                        color: Colors.grey[400]),
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildMoreFiltersButton(),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('scholarships')
                      .snapshots(),
                  builder: (context, snapshot) {
                    // Admin hide/unhide is an operational publishing control;
                    // retain legacy documents that do not yet carry the flag.
                    final allData = (snapshot.data?.docs ?? const [])
                        .where((doc) => doc.data()['isHidden'] != true)
                        .toList();

                    Widget listContent;
                    if (snapshot.hasError) {
                      listContent = ScholarshipState(
                          icon: Icons.cloud_off_outlined,
                          title: 'Unable to load scholarships',
                          description: 'Check your connection and try again.',
                          onRetry: () => setState(() {}));
                    } else if (snapshot.connectionState ==
                            ConnectionState.waiting &&
                        allData.isEmpty) {
                      listContent = const ScholarshipSkeletonList();
                    } else if (allData.isEmpty) {
                      listContent = const ScholarshipState(
                          icon: Icons.school_outlined,
                          title: 'No scholarships yet',
                          description:
                              'New opportunities will appear here as they are published.');
                    } else {
                      // Keep the scholarships cache in sync with the stream;
                      // _applyFiltersAndSort uses the cached list so the filter
                      // pass doesn't re-run every time the user types or taps a
                      // chip that doesn't change the filter signature.
                      _scholarshipsFor(allData);
                      final sortedData = _applyFiltersAndSort();

                      if (sortedData.isEmpty) {
                        listContent = ScholarshipState(
                            icon: Icons.search_off_outlined,
                            title: 'No matches found',
                            description:
                                'Try a different keyword or clear one of your filters.',
                            onRetry: _resetFilters);
                      } else {
                        listContent = ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          itemCount: sortedData.length,
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _buildScholarshipCard(sortedData[index]),
                          ),
                        );
                      }
                    }

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildFilterButton(
                                  'Country',
                                  _selectedCountry,
                                  _countryOptions(allData),
                                  (value) =>
                                      setState(() => _selectedCountry = value),
                                ),
                                const SizedBox(width: 10),
                                _buildFilterButton(
                                  'Degree',
                                  _selectedDegree,
                                  _degreeOptions(allData),
                                  (value) =>
                                      setState(() => _selectedDegree = value),
                                ),
                                const SizedBox(width: 10),
                                _buildFilterButton(
                                  'Funding',
                                  _selectedFunding,
                                  _fundingOptions(allData),
                                  (value) =>
                                      setState(() => _selectedFunding = value),
                                ),
                                const SizedBox(width: 10),
                                _buildFilterButton(
                                    'Deadline',
                                    _selectedDeadline,
                                    const [
                                      'Deadline Ascending',
                                      'Deadline Descending',
                                    ],
                                    (value) => setState(() {
                                      if (value == 'Deadline Ascending') {
                                        _selectedDeadline = '';
                                        _selectedSort = 'Deadline: Ascending';
                                      } else if (value == 'Deadline Descending') {
                                        _selectedDeadline = '';
                                        _selectedSort = 'Deadline: Descending';
                                      } else {
                                        _selectedDeadline = value;
                                      }
                                    })),
                                const SizedBox(width: 10),
                                _buildFilterButton(
                                    'Field',
                                    _selectedField,
                                    _fieldOptions(allData),
                                    (value) =>
                                        setState(() => _selectedField = value)),
                                const SizedBox(width: 10),
                                _buildFilterButton(
                                    'Sort',
                                    _selectedSort,
                                    sortOptions,
                                    (value) =>
                                        setState(() => _selectedSort = value)),
                                const SizedBox(width: 10),
                                _buildPremiumFiltersChip(),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Expanded(child: listContent),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );

  bool _isFullyFunded(Map<String, dynamic> s) =>
      '${s['funding'] ?? s['fundingType'] ?? s['amount'] ?? ''}'
          .toLowerCase()
          .contains('full');

  int _fundingRank(Map<String, dynamic> scholarship) =>
      _isFullyFunded(scholarship) ? 1 : 0;

  DateTime _newestValue(Map<String, dynamic> s) {
    final raw = s['createdAt'] ?? s['updatedAt'] ?? s['publishedAt'];
    if (raw is Timestamp) return raw.toDate();
    return DateTime.tryParse(raw?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  Widget _buildMoreFiltersButton() => ActionChip(
        avatar: const Icon(Icons.tune, size: 18),
        label: Text(_advancedFilterCount == 0
            ? 'Filters'
            : 'Filters ($_advancedFilterCount)'),
        onPressed: () => _showAdvancedFilters(_cachedDocuments ?? const []),
        shape: StadiumBorder(side: BorderSide(color: Colors.grey.shade300)),
        backgroundColor:
            _advancedFilterCount == 0 ? Colors.white : const Color(0xFFE8EDFF),
      );

  int get _advancedFilterCount =>
      [
        _selectedIelts,
        _selectedEnglishMedium,
        _selectedResearch,
      ].where((value) => value.isNotEmpty).length +
      (_maximumMinCgpa == null ? 0 : 1) +
      (_maximumBacklogs == null ? 0 : 1) +
      (_selectedDeadlineMonth == null ? 0 : 1);

  Future<void> _showAdvancedFilters(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    var selectedIelts = _selectedIelts;
    var selectedEnglish = _selectedEnglishMedium,
        selectedResearch = _selectedResearch;
    var cgpa = _maximumMinCgpa;
    var backlogs = _maximumBacklogs;
    var deadlineMonth = _selectedDeadlineMonth;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .78,
              child: Column(children: [
                Row(children: [
                  const Expanded(
                      child: Text('More filters',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700))),
                  TextButton(
                      onPressed: () => setSheetState(() {
                            selectedIelts =
                                selectedEnglish = selectedResearch = '';
                            cgpa = null;
                            backlogs = null;
                            deadlineMonth = null;
                          }),
                      child: const Text('Reset')),
                ]),
                Expanded(
                    child: ListView(children: [
                  _sheetSelect(
                      'IELTS Required',
                      selectedIelts,
                      const ['Required', 'Not Required'],
                      (v) => setSheetState(() => selectedIelts = v)),
                  _sheetSelect(
                      'English Medium Accepted',
                      selectedEnglish,
                      const ['Accepted', 'Not Accepted'],
                      (v) => setSheetState(() => selectedEnglish = v)),
                  _sheetSelect(
                      'Research Required',
                      selectedResearch,
                      const ['Required', 'Not Required'],
                      (v) => setSheetState(() => selectedResearch = v)),
                  _sheetSelect(
                      'Deadline Month',
                      deadlineMonth == null ? '' : _monthName(deadlineMonth!),
                      _monthNames,
                      (v) => setSheetState(() => deadlineMonth =
                          v.isEmpty ? null : _monthNames.indexOf(v) + 1)),
                  _sheetSelect(
                      'Minimum CGPA',
                      cgpa?.toString() ?? '',
                      const ['2.0', '2.5', '3.0', '3.5'],
                      (v) => setSheetState(
                          () => cgpa = v.isEmpty ? null : double.parse(v))),
                  _sheetSelect(
                      'Maximum Backlogs',
                      backlogs?.toString() ?? '',
                      const ['0', '1', '2', '3', '5'],
                      (v) => setSheetState(
                          () => backlogs = v.isEmpty ? null : int.parse(v))),
                ])),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        setState(() {
                          _selectedIelts = selectedIelts;
                          _selectedEnglishMedium = selectedEnglish;
                          _selectedResearch = selectedResearch;
                          _maximumMinCgpa = cgpa;
                          _maximumBacklogs = backlogs;
                          _selectedDeadlineMonth = deadlineMonth;
                        });
                        Navigator.pop(sheetContext);
                      },
                      child: const Text('Show results'),
                    )),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetSelect(String label, String selected, List<String> values,
          ValueChanged<String> onChanged) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: DropdownButtonFormField<String>(
          initialValue: selected.isEmpty ? null : selected,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
          items: [
            const DropdownMenuItem(value: '', child: Text('Any')),
            ...values.map((value) => DropdownMenuItem(
                value: value,
                child: Text(value, overflow: TextOverflow.ellipsis)))
          ],
          onChanged: (value) => onChanged(value ?? ''),
        ),
      );

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _monthName(int month) => _monthNames[month - 1];

  Widget _buildFilterButton(
    String label,
    String selectedValue,
    List<String> options,
    ValueChanged<String> onSelect,
  ) =>
      PopupMenuButton<String>(
        constraints: BoxConstraints(
          maxWidth: 280,
          maxHeight: MediaQuery.sizeOf(context).height * 0.65,
        ),
        onSelected: (value) {
          if (value == 'Clear') {
            onSelect('');
          } else {
            onSelect(value);
          }
        },
        itemBuilder: (BuildContext context) => [
          if (label != 'Sort') ...[
            const PopupMenuItem(
              value: 'Clear',
              child: Row(
                children: [
                  Icon(Icons.close, size: 18),
                  SizedBox(width: 8),
                  Text('Clear'),
                ],
              ),
            ),
            const PopupMenuDivider(),
          ],
          ...options.map((option) => PopupMenuItem(
                value: option,
                child: Row(
                  children: [
                    if (selectedValue == option)
                      const Icon(Icons.check,
                          size: 18, color: Color(0xFF5B7AE8))
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        option,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selectedValue.isNotEmpty
                ? const Color(0xFF5B7AE8)
                : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: selectedValue.isEmpty
                ? Border.all(color: Colors.grey[300]!)
                : null,
            boxShadow: selectedValue.isNotEmpty
                ? [
                    BoxShadow(
                      color: const Color(0xFF5B7AE8).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                selectedValue.isEmpty ? label : selectedValue,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color:
                      selectedValue.isNotEmpty ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color:
                    selectedValue.isNotEmpty ? Colors.white : Colors.grey[600],
              ),
            ],
          ),
        ),
      );

  /// Pill that opens the upgrade dialog when a free user taps it.
  ///
  /// Premium filters are intentionally gated behind a single CTA rather than
  /// re-skinned inline chips so the existing filter row stays untouched for
  /// paying users.
  Widget _buildPremiumFiltersChip() => Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => PremiumGuard.promptUpgrade(
          context,
          feature: PremiumFeature.premiumFilters,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune, size: 16, color: Colors.amber),
              SizedBox(width: 6),
              Text(
                'Pro Filters',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );

  Widget _buildScholarshipCard(Map<String, dynamic> s) {
    final status = _getStatusBadge(s);
    final statusColor = _getStatusColor(status);
    final scholarshipId = (s['id'] ?? '').toString();

    return Semantics(
        button: true,
        label: 'Scholarship: ${(s['title'] ?? 'Untitled').toString()}',
        child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openScholarshipDetails(context, scholarshipId, s),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                clipBehavior: Clip.hardEdge,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(16)),
                            child: ScholarshipImage(
                                url: (s['image'] ?? '').toString(),
                                height: 180,
                                heroTag: 'scholarship-image-$scholarshipId')),
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.95),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: SavedScholarshipIconButton(
                              scholarship: {
                                ...s,
                                'id': scholarshipId,
                              },
                              iconSize: 22,
                            ),
                          ),
                        ),
                        if (status.isNotEmpty)
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                status,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (s['title'] ?? 'Untitled').toString(),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A2E),
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            if ((s['country'] ?? '').toString().isNotEmpty)
                              InfoPill(
                                  label: s['country'].toString(),
                                  icon: Icons.public_outlined),
                            if ((s['degree'] ?? '').toString().isNotEmpty)
                              InfoPill(
                                  label: _formatDegree(s['degree'].toString()),
                                  icon: Icons.school_outlined,
                                  color: const Color(0xFF6A1B9A)),
                            if ((s['field'] ?? '').toString().isNotEmpty)
                              InfoPill(
                                  label: s['field'].toString(),
                                  icon: Icons.menu_book_outlined,
                                  color: const Color(0xFF1565C0)),
                          ]),
                          const SizedBox(height: 8),
                          const SizedBox.shrink(),
                          const SizedBox(height: 12),
                          Container(
                            height: 1,
                            color: Colors.grey[200],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'AWARD VALUE',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[500],
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    (s['amount'] ?? 'N/A').toString(),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF5B7AE8),
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'DEADLINE',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[500],
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    (s['deadline'] ?? 'N/A').toString(),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                _openScholarshipDetails(
                                    context, scholarshipId, s);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF5B7AE8),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'View Details',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            )));
  }

  Map<String, dynamic> _buildScholarshipData(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final s = doc.data();
    return {
      ...s,
      'id': doc.id,
      'title': (s['title'] ?? '').toString(),
      'country': (s['country'] ?? '').toString(),
      'degree': (s['degree'] ?? '').toString(),
      'amount': (s['amount'] ?? '').toString(),
      'field': (s['field'] ?? '').toString(),
      'deadline': (s['deadline'] ?? '').toString(),
      'description': (s['description'] ?? '').toString(),
      'image': (s['image'] ?? '').toString(),
      'link': (s['link'] ?? '').toString(),
    };
  }

  Future<void> _openScholarshipDetails(
    BuildContext context,
    String scholarshipId,
    Map<String, dynamic> fallbackData,
  ) async {
    if (scholarshipId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing scholarship id')),
      );
      return;
    }

    // The list already has the full scholarship data, so skip the extra
    // Firestore round-trip and push the details screen immediately. The
    // details screen still uses Firestore snapshots to stay up to date.
    Navigator.push(
      context,
      _fastPageRoute(
        ScholarshipDetailsScreen(data: fallbackData),
      ),
    );
  }
}
