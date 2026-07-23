import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ScholarBird/screens/scholarship/scholarship_details.dart';

class ScholarshipsScreen extends StatefulWidget {
  const ScholarshipsScreen({super.key});

  @override
  State<ScholarshipsScreen> createState() => _ScholarshipsScreenState();
}

class _ScholarshipsScreenState extends State<ScholarshipsScreen> {
  final TextEditingController _searchController = TextEditingController();
  Set<String> _savedScholarshipIds = <String>{};

  String _selectedField = '';
  String _selectedDegree = '';
  String _selectedCountry = '';
  String _searchQuery = '';
  String _selectedSort = 'Deadline (Soonest)';

  final List<String> sortOptions = ['Deadline (Soonest)', 'Deadline (Latest)'];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    _loadSavedScholarships();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedScholarships() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('savedScholarships')
        .get();

    if (!mounted) return;

    setState(() {
      _savedScholarshipIds = snapshot.docs.map((doc) => doc.id).toSet();
    });
  }

  Future<void> _toggleSave(Map<String, dynamic> s) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login first')),
      );
      return;
    }

    final scholarshipId = (s['id'] ?? '').toString();
    if (scholarshipId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing scholarship id')),
      );
      return;
    }

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('savedScholarships')
        .doc(scholarshipId);

    final wasSaved = _savedScholarshipIds.contains(scholarshipId);

    setState(() {
      if (wasSaved) {
        _savedScholarshipIds.remove(scholarshipId);
      } else {
        _savedScholarshipIds.add(scholarshipId);
      }
    });

    try {
      if (wasSaved) {
        await docRef.delete();
      } else {
        await docRef.set({
          'title': s['title'],
          'country': s['country'],
          'degree': s['degree'],
          'image': s['image'],
          'savedAt': Timestamp.now(),
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (wasSaved) {
          _savedScholarshipIds.add(scholarshipId);
        } else {
          _savedScholarshipIds.remove(scholarshipId);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update saved status')),
      );
    }
  }

  List<String> _collectOptions(List<QueryDocumentSnapshot<Object?>> docs, String key) {
    final values = <String>{};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final raw = data[key];
      if (raw == null) continue;
      final value = raw.toString().trim();
      if (value.isNotEmpty) {
        values.add(value);
      }
    }
    final list = values.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
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
    if (cleaned == "master's" || cleaned == 'masters' || cleaned == 'postgraduate') {
      return 'postgraduate';
    }
    return cleaned;
  }

  List<String> _collectDegreeOptions(List<QueryDocumentSnapshot<Object?>> docs) {
    final raw = _collectOptions(docs, 'degree');
    final mapped = raw.map(_formatDegree).toSet().toList();
    mapped.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return mapped;
  }

  bool _matchesFilters(Map<String, dynamic> scholarship) {
    if (_searchQuery.isNotEmpty) {
      final title = scholarship['title'].toString().toLowerCase();
      final field = scholarship['field'].toString().toLowerCase();
      final country = scholarship['country'].toString().toLowerCase();
      final degree = _normalizeDegree(scholarship['degree'].toString());
      if (!title.contains(_searchQuery) &&
          !field.contains(_searchQuery) &&
          !country.contains(_searchQuery) &&
          !degree.contains(_normalizeDegree(_searchQuery))) {
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

    return true;
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
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'ScholarBird',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                        letterSpacing: -0.5,
                      ),
                    ),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF5B7AE8), Color(0xFF3D5AC1)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF5B7AE8).withOpacity(0.1),
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
                              child: Icon(
                                Icons.close,
                                color: Colors.grey[400],
                              ),
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
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

                    Widget listContent;
                    if (snapshot.hasError) {
                      listContent = Center(
                        child: Text(
                          'Error: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red),
                        ),
                      );
                    } else if (snapshot.connectionState == ConnectionState.waiting &&
                        allData.isEmpty) {
                      listContent = const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF5B7AE8),
                        ),
                      );
                    } else if (allData.isEmpty) {
                      listContent = Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 64,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No scholarships found',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      );
                    } else {
                      final filteredData = allData
                          .map(_buildScholarshipData)
                          .where(_matchesFilters)
                          .toList();

                      final sortedData = List<Map<String, dynamic>>.from(filteredData);
                      if (_selectedSort == 'Deadline (Soonest)' ||
                          _selectedSort == 'Deadline (Latest)') {
                        sortedData.sort((a, b) {
                          final aDate = _parseDeadline(a['deadline'].toString());
                          final bDate = _parseDeadline(b['deadline'].toString());
                          if (aDate == null && bDate == null) return 0;
                          if (aDate == null) return 1;
                          if (bDate == null) return -1;
                          return _selectedSort == 'Deadline (Soonest)'
                              ? aDate.compareTo(bDate)
                              : bDate.compareTo(aDate);
                        });
                      }

                      if (sortedData.isEmpty) {
                        listContent = Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.filter_alt_off,
                                size: 64,
                                color: Colors.grey[300],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No results match your filters',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        );
                      } else {
                        listContent = ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                                  'Field',
                                  _selectedField,
                                  fieldOptions,
                                  (value) => setState(() => _selectedField = value),
                                ),
                                const SizedBox(width: 10),
                                _buildFilterButton(
                                  'Degree',
                                  _selectedDegree,
                                  degreeOptions,
                                  (value) => setState(() => _selectedDegree = value),
                                ),
                                const SizedBox(width: 10),
                                _buildFilterButton(
                                  'Country',
                                  _selectedCountry,
                                  countryOptions,
                                  (value) => setState(() => _selectedCountry = value),
                                ),
                                const SizedBox(width: 10),
                                _buildFilterButton(
                                  'Sort',
                                  _selectedSort,
                                  sortOptions,
                                  (value) => setState(() => _selectedSort = value),
                                ),
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

  Widget _buildFilterButton(
    String label,
    String selectedValue,
    List<String> options,
    ValueChanged<String> onSelect,
  ) => PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'Clear') {
          onSelect('');
        } else {
          onSelect(value);
        }
      },
      itemBuilder: (BuildContext context) {
        return [
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
                  Text(option),
                ],
              ),
            );
          }).toList(),
        ];
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selectedValue.isNotEmpty ? const Color(0xFF5B7AE8) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: selectedValue.isEmpty
              ? Border.all(color: Colors.grey[300]!)
              : null,
          boxShadow: selectedValue.isNotEmpty
              ? [
                  BoxShadow(
                    color: const Color(0xFF5B7AE8).withOpacity(0.3),
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
                color: selectedValue.isNotEmpty ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: selectedValue.isNotEmpty ? Colors.white : Colors.grey[600],
            ),
          ],
        ),
      ),
    );

  Widget _buildScholarshipCard(Map<String, dynamic> s) {
    final status = _getStatusBadge(s);
    final statusColor = _getStatusColor(status);
    final scholarshipId = (s['id'] ?? '').toString();
    final isSaved = _savedScholarshipIds.contains(scholarshipId);

    return GestureDetector(
      onTap: () {
        _openScholarshipDetails(context, scholarshipId, s);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
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
                    top: Radius.circular(18),
                  ),
                  child: Image.network(
                    (s['image'] ?? 'https://via.placeholder.com/400x200').toString(),
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 180,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.grey.shade300,
                            Colors.grey.shade200,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Icon(
                        Icons.school,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(
                        isSaved ? Icons.bookmark : Icons.bookmark_border,
                        color: isSaved ? Colors.amber : Colors.grey,
                      ),
                      onPressed: () => _toggleSave(s),
                      tooltip: isSaved ? 'Saved' : 'Save',
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
              padding: const EdgeInsets.all(18),
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
                  Row(
                    children: [
                      Icon(
                        Icons.school_outlined,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        (s['field'] ?? 'N/A').toString(),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.public,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        (s['country'] ?? 'N/A').toString(),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.book_outlined,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatDegree((s['degree'] ?? 'N/A').toString()),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
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
                        _openScholarshipDetails(context, scholarshipId, s);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5B7AE8),
                        padding: const EdgeInsets.symmetric(vertical: 12),
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
    );
  }

  Map<String, dynamic> _buildScholarshipData(
      QueryDocumentSnapshot<Object?> doc) {
    final s = doc.data() as Map<String, dynamic>;
    return {
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
