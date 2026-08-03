import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ScholarBird/screens/scholarship/scholarship_details.dart';
import 'package:ScholarBird/widgets/scholarship_ui.dart';
import '../../widgets/saved_scholarship_controls.dart';

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
  String _searchQuery = '';
  String _selectedSort = 'Most Relevant';

  static const List<String> sortOptions = [
    'Most Relevant',
    'Newest',
    'Deadline Soon',
    'Fully Funded First',
    'Alphabetical',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
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
    if (_searchQuery.isNotEmpty) {
      // The upload pipeline supplies search_tokens. Fall back to the existing
      // document fields so older Firestore records remain searchable too.
      final searchableValues = [
        scholarship['title'], scholarship['university'], scholarship['country'],
        scholarship['field'], scholarship['provider'], scholarship['description'],
        scholarship['keywords'], scholarship['tags'], scholarship['search_tokens'],
      ];
      final haystack = searchableValues.whereType<Object?>().expand((value) => value is Iterable
          ? value.map((item) => item.toString()) : [value.toString()]).join(' ').toLowerCase();
      if (!_searchQuery.split(RegExp(r'\s+')).every(haystack.contains)) {
        return false;
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
        fallbacks: const ['fundingType', 'amount'])) return false;
    if (!_matchesBoolean(scholarship, 'ieltsRequired', _selectedIelts)) return false;
    if (!_matchesBoolean(scholarship, 'englishMediumAccepted', _selectedEnglishMedium)) return false;
    if (!_matchesBoolean(scholarship, 'researchRequired', _selectedResearch)) return false;
    if (_maximumMinCgpa != null && _number(scholarship['minCGPA'] ?? scholarship['minCgpa']) > _maximumMinCgpa!) return false;
    if (_maximumBacklogs != null && _number(scholarship['maxBacklogs']).round() > _maximumBacklogs!) return false;
    if (_selectedDeadline.isNotEmpty && !_matchesDeadline(scholarship)) return false;
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
    final candidates = [key, ...fallbacks].map((field) => value[field]?.toString().toLowerCase() ?? '');
    return candidates.any((candidate) => candidate == selected.toLowerCase());
  }

  bool _matchesBoolean(Map<String, dynamic> value, String key, String selected) {
    if (selected.isEmpty) return true;
    return value[key] == (selected == 'Required' || selected == 'Accepted');
  }

  double _number(dynamic value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;

  bool _matchesDeadline(Map<String, dynamic> scholarship) {
    final deadline = _parseDeadline(scholarship['deadline']?.toString() ?? '');
    if (_selectedDeadline == 'Open') return deadline == null || !deadline.isBefore(DateTime.now());
    if (deadline == null) return false;
    final days = deadline.difference(DateTime.now()).inDays;
    return _selectedDeadline == 'Next 30 days' ? days >= 0 && days <= 30 : days >= 0 && days <= 90;
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _selectedField = _selectedDegree = _selectedCountry = _selectedFunding = '';
      _selectedDeadline = '';
      _selectedDeadlineMonth = null;
      _selectedIelts = _selectedEnglishMedium = _selectedResearch = '';
      _maximumMinCgpa = null;
      _maximumBacklogs = null;
      _selectedSort = 'Most Relevant';
    });
  }

  List<Map<String, dynamic>> _scholarshipsFor(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> documents) {
    // A filter/sort state change should not repeatedly deserialize a 10k item
    // Firestore snapshot. The cache is invalidated only by a new snapshot.
    if (!identical(_cachedDocuments, documents)) {
      _cachedDocuments = documents;
      _cachedScholarships = documents.map(_buildScholarshipData).toList(growable: false);
    }
    return _cachedScholarships;
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
                      'ScholarBird',
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
                    final allData = snapshot.data?.docs ?? [];
                    final fieldOptions = _withSelected(
                      _collectOptions(allData, 'field'),
                      _selectedField,
                    );
                    final degreeOptions = _withSelected(
                      _collectDegreeOptions(allData),
                      _selectedDegree,
                    );
                    final countryOptions = _withSelected(
                      _collectOptions(allData, 'country'),
                      _selectedCountry,
                    );
                    final fundingOptions = _withSelected(
                      {
                        ..._collectOptions(allData, 'funding'),
                        ..._collectOptions(allData, 'fundingType'),
                        ..._collectOptions(allData, 'amount'),
                      }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
                      _selectedFunding,
                    );

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
                      final filteredData = _scholarshipsFor(allData)
                          .where(_matchesFilters)
                          .toList(growable: false);

                      final sortedData =
                          List<Map<String, dynamic>>.from(filteredData);
                      if (_selectedSort == 'Deadline Soon') {
                        sortedData.sort((a, b) {
                          final aDate =
                              _parseDeadline(a['deadline'].toString());
                          final bDate =
                              _parseDeadline(b['deadline'].toString());
                          if (aDate == null && bDate == null) return 0;
                          if (aDate == null) return 1;
                          if (bDate == null) return -1;
                          return aDate.compareTo(bDate);
                        });
                      } else if (_selectedSort == 'Alphabetical') {
                        sortedData.sort((a, b) => a['title'].toString().toLowerCase().compareTo(b['title'].toString().toLowerCase()));
                      } else if (_selectedSort == 'Fully Funded First') {
                        sortedData.sort((a, b) =>
                            _fundingRank(b).compareTo(_fundingRank(a)));
                      } else if (_selectedSort == 'Newest') {
                        sortedData.sort((a, b) => _newestValue(b).compareTo(_newestValue(a)));
                      }

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
                                  'Country', _selectedCountry, countryOptions,
                                  (value) =>
                                      setState(() => _selectedCountry = value),
                                ),
                                const SizedBox(width: 10),
                                _buildFilterButton(
                                  'Degree', _selectedDegree, degreeOptions,
                                  (value) =>
                                      setState(() => _selectedDegree = value),
                                ),
                                const SizedBox(width: 10),
                                _buildFilterButton(
                                  'Funding', _selectedFunding, fundingOptions,
                                  (value) =>
                                      setState(() => _selectedFunding = value),
                                ),
                                const SizedBox(width: 10),
                                _buildFilterButton('Deadline', _selectedDeadline,
                                    const ['Next 30 days', 'Next 90 days', 'Open'],
                                    (value) => setState(() => _selectedDeadline = value)),
                                const SizedBox(width: 10),
                                _buildFilterButton('Field', _selectedField, fieldOptions,
                                    (value) => setState(() => _selectedField = value)),
                                const SizedBox(width: 10),
                                _buildFilterButton('Sort', _selectedSort, sortOptions,
                                    (value) => setState(() => _selectedSort = value)),
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
      '${s['funding'] ?? s['fundingType'] ?? s['amount'] ?? ''}'.toLowerCase().contains('full');

  int _fundingRank(Map<String, dynamic> scholarship) =>
      _isFullyFunded(scholarship) ? 1 : 0;

  DateTime _newestValue(Map<String, dynamic> s) {
    final raw = s['createdAt'] ?? s['updatedAt'] ?? s['publishedAt'];
    if (raw is Timestamp) return raw.toDate();
    return DateTime.tryParse(raw?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  Widget _buildMoreFiltersButton() =>
      ActionChip(
        avatar: const Icon(Icons.tune, size: 18),
        label: Text(_advancedFilterCount == 0 ? 'Filters' : 'Filters ($_advancedFilterCount)'),
        onPressed: () => _showAdvancedFilters(_cachedDocuments ?? const []),
        shape: StadiumBorder(side: BorderSide(color: Colors.grey.shade300)),
        backgroundColor: _advancedFilterCount == 0 ? Colors.white : const Color(0xFFE8EDFF),
      );

  int get _advancedFilterCount => [
        _selectedIelts, _selectedEnglishMedium, _selectedResearch,
      ].where((value) => value.isNotEmpty).length +
      (_maximumMinCgpa == null ? 0 : 1) +
      (_maximumBacklogs == null ? 0 : 1) +
      (_selectedDeadlineMonth == null ? 0 : 1);

  Future<void> _showAdvancedFilters(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    String selectedIelts = _selectedIelts;
    String selectedEnglish = _selectedEnglishMedium, selectedResearch = _selectedResearch;
    double? cgpa = _maximumMinCgpa;
    int? backlogs = _maximumBacklogs;
    int? deadlineMonth = _selectedDeadlineMonth;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .78,
              child: Column(children: [
                Row(children: [
                  const Expanded(child: Text('More filters', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
                  TextButton(onPressed: () => setSheetState(() { selectedIelts = selectedEnglish = selectedResearch = ''; cgpa = null; backlogs = null; deadlineMonth = null; }), child: const Text('Reset')),
                ]),
                Expanded(child: ListView(children: [
                  _sheetSelect('IELTS Required', selectedIelts, const ['Required', 'Not Required'], (v) => setSheetState(() => selectedIelts = v)),
                  _sheetSelect('English Medium Accepted', selectedEnglish, const ['Accepted', 'Not Accepted'], (v) => setSheetState(() => selectedEnglish = v)),
                  _sheetSelect('Research Required', selectedResearch, const ['Required', 'Not Required'], (v) => setSheetState(() => selectedResearch = v)),
                  _sheetSelect('Deadline Month', deadlineMonth == null ? '' : _monthName(deadlineMonth!), _monthNames, (v) => setSheetState(() => deadlineMonth = v.isEmpty ? null : _monthNames.indexOf(v) + 1)),
                  _sheetSelect('Minimum CGPA', cgpa?.toString() ?? '', const ['2.0', '2.5', '3.0', '3.5'], (v) => setSheetState(() => cgpa = v.isEmpty ? null : double.parse(v))),
                  _sheetSelect('Maximum Backlogs', backlogs?.toString() ?? '', const ['0', '1', '2', '3', '5'], (v) => setSheetState(() => backlogs = v.isEmpty ? null : int.parse(v))),
                ])),
                SizedBox(width: double.infinity, child: FilledButton(
                  onPressed: () { setState(() { _selectedIelts = selectedIelts; _selectedEnglishMedium = selectedEnglish; _selectedResearch = selectedResearch; _maximumMinCgpa = cgpa; _maximumBacklogs = backlogs; _selectedDeadlineMonth = deadlineMonth; }); Navigator.pop(sheetContext); },
                  child: const Text('Show results'),
                )),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetSelect(String label, String selected, List<String> values, ValueChanged<String> onChanged) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: DropdownButtonFormField<String>(
          value: selected.isEmpty ? null : selected,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          items: [const DropdownMenuItem(value: '', child: Text('Any')), ...values.map((value) => DropdownMenuItem(value: value, child: Text(value, overflow: TextOverflow.ellipsis)))],
          onChanged: (value) => onChanged(value ?? ''),
        ),
      );

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
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
            PopupMenuItem(
              value: 'Clear',
              child: Row(
                children: const [
                  Icon(Icons.close, size: 18),
                  SizedBox(width: 8),
                  Text('Clear'),
                ],
              ),
            ),
            const PopupMenuDivider(),
          ],
          ...options.map((option) {
            return PopupMenuItem(
              value: option,
              child: Row(
                children: [
                  if (selectedValue == option)
                    const Icon(Icons.check, size: 18, color: Color(0xFF5B7AE8))
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
            );
          }).toList(),
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF5B7AE8)),
      ),
    );

    try {
      final doc = await FirebaseFirestore.instance
          .collection('scholarships')
          .doc(scholarshipId)
          .get();

      if (!context.mounted) return;
      Navigator.of(context).pop();

      if (!doc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scholarship not found')),
        );
        return;
      }

      final data = doc.data() ?? {};
      data['id'] = scholarshipId;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScholarshipDetailsScreen(
            data: {
              ...fallbackData,
              ...data,
            },
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load scholarship')),
      );
    }
  }
}
