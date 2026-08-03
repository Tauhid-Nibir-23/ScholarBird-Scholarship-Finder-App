import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/saved_scholarships_service.dart';
import '../../widgets/saved_empty_state.dart';
import '../../widgets/saved_scholarship_card.dart';
import '../scholarship/scholarship_details.dart';
import 'profile_widgets.dart';

enum _SavedSortOption { newest, deadline, country, degree }

class SavedScholarshipsScreen extends StatefulWidget {
  const SavedScholarshipsScreen({super.key});

  @override
  State<SavedScholarshipsScreen> createState() => _SavedScholarshipsScreenState();
}

class _SavedScholarshipsScreenState extends State<SavedScholarshipsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedIds = <String>{};

  _SavedSortOption _sortOption = _SavedSortOption.newest;
  String _countryFilter = '';
  String _degreeFilter = '';
  String _searchQuery = '';
  bool _gridMode = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
  }

  List<Map<String, dynamic>> _filterAndSort(List<Map<String, dynamic>> items) {
    final filtered = items.where((item) {
      final title = (item['title'] ?? '').toString().toLowerCase();
      final country = (item['country'] ?? '').toString().toLowerCase();
      final degree = (item['degree'] ?? '').toString().toLowerCase();
      final field = (item['field'] ?? '').toString().toLowerCase();

      if (_searchQuery.isNotEmpty &&
          !title.contains(_searchQuery) &&
          !country.contains(_searchQuery) &&
          !degree.contains(_searchQuery) &&
          !field.contains(_searchQuery)) {
        return false;
      }

      if (_countryFilter.isNotEmpty && country != _countryFilter.toLowerCase()) {
        return false;
      }

      if (_degreeFilter.isNotEmpty && degree != _degreeFilter.toLowerCase()) {
        return false;
      }

      return true;
    }).toList();

    filtered.sort((a, b) {
      switch (_sortOption) {
        case _SavedSortOption.newest:
          return _parseSavedAt(b['savedAt']).compareTo(_parseSavedAt(a['savedAt']));
        case _SavedSortOption.deadline:
          return _parseDeadline(a['deadline']).compareTo(_parseDeadline(b['deadline']));
        case _SavedSortOption.country:
          return (a['country'] ?? '').toString().toLowerCase().compareTo((b['country'] ?? '').toString().toLowerCase());
        case _SavedSortOption.degree:
          return (a['degree'] ?? '').toString().toLowerCase().compareTo((b['degree'] ?? '').toString().toLowerCase());
      }
    });

    return filtered;
  }

  DateTime _parseSavedAt(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime _parseDeadline(dynamic value) {
    final parsed = DateTime.tryParse((value ?? '').toString().trim());
    return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _removeSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;

    await SavedScholarshipsService.instance.removeMany(ids);
    if (!mounted) return;
    setState(() {
      _selectedIds.clear();
    });
  }

  Future<void> _clearAll() async {
    await SavedScholarshipsService.instance.clearAllSaved();
    if (!mounted) return;
    setState(() {
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: sbBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Saved Scholarships',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: sbText),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: sbText),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_selectedIds.isNotEmpty)
            IconButton(
              tooltip: 'Remove selected',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Remove selected?'),
                    content: const Text('This removes the selected saved scholarships from your account.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await _removeSelected();
                }
              },
            ),
          IconButton(
            tooltip: _gridMode ? 'List view' : 'Grid view',
            icon: Icon(_gridMode ? Icons.view_list_outlined : Icons.grid_view_outlined),
            onPressed: () => setState(() => _gridMode = !_gridMode),
          ),
        ],
      ),
      body: currentUser == null
          ? const Center(
              child: Text(
                'Please log in to view saved scholarships.',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: sbSecondaryText),
              ),
            )
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: SavedScholarshipsService.instance.watchSavedScholarshipsWithFallback(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const ProfileEmptyState(
                    title: 'Unable to load saved scholarships',
                    message: 'Please check your connection and try again.',
                    icon: Icons.error_outline,
                  );
                }

                final rawItems = snapshot.data ?? const <Map<String, dynamic>>[];
                final items = _filterAndSort(rawItems);

                if (rawItems.isEmpty) {
                  return SavedEmptyState(
                    onBrowse: () => Navigator.of(context).maybePop(),
                  );
                }

                if (items.isEmpty) {
                  return const ProfileEmptyState(
                    title: 'No matches found',
                    message: 'Try adjusting search or filters.',
                    icon: Icons.search_off_outlined,
                  );
                }

                final countryOptions = rawItems
                    .map((item) => (item['country'] ?? '').toString())
                    .where((value) => value.trim().isNotEmpty)
                    .toSet()
                    .toList()
                  ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                final degreeOptions = rawItems
                    .map((item) => (item['degree'] ?? '').toString())
                    .where((value) => value.trim().isNotEmpty)
                    .toSet()
                    .toList()
                  ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: 'Search saved scholarships',
                                  prefixIcon: const Icon(Icons.search),
                                  suffixIcon: _searchController.text.isEmpty
                                      ? null
                                      : IconButton(
                                          icon: const Icon(Icons.close),
                                          onPressed: _searchController.clear,
                                        ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _filterChip('Newest saved', _sortOption == _SavedSortOption.newest, () => setState(() => _sortOption = _SavedSortOption.newest)),
                                  _filterChip('Deadline', _sortOption == _SavedSortOption.deadline, () => setState(() => _sortOption = _SavedSortOption.deadline)),
                                  _filterChip('Country', _sortOption == _SavedSortOption.country, () => setState(() => _sortOption = _SavedSortOption.country)),
                                  _filterChip('Degree', _sortOption == _SavedSortOption.degree, () => setState(() => _sortOption = _SavedSortOption.degree)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _dropdownFilter(
                                      label: 'Country',
                                      value: _countryFilter,
                                      options: countryOptions,
                                      onChanged: (value) => setState(() => _countryFilter = value ?? ''),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _dropdownFilter(
                                      label: 'Degree',
                                      value: _degreeFilter,
                                      options: degreeOptions,
                                      onChanged: (value) => setState(() => _degreeFilter = value ?? ''),
                                    ),
                                  ),
                                ],
                              ),
                              if (_selectedIds.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${_selectedIds.length} selected',
                                        style: const TextStyle(fontWeight: FontWeight.w600, color: sbText),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        final confirmed = await showDialog<bool>(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text('Clear all saved?'),
                                            content: const Text('This removes every saved scholarship from your account.'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear all')),
                                            ],
                                          ),
                                        );
                                        if (confirmed == true) {
                                          await _clearAll();
                                        }
                                      },
                                      child: const Text('Clear all saved'),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (_gridMode)
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.72,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final item = items[index];
                                final id = (item['id'] ?? '').toString();
                                return SavedScholarshipCard(
                                  data: item,
                                  isSelected: _selectedIds.contains(id),
                                  selectionMode: _selectedIds.isNotEmpty,
                                  onTap: () => _openScholarshipDetails(context, id, item),
                                  onLongPress: () => _toggleSelection(id),
                                );
                              },
                              childCount: items.length,
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final item = items[index];
                                final id = (item['id'] ?? '').toString();
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: SavedScholarshipCard(
                                    data: item,
                                    isSelected: _selectedIds.contains(id),
                                    selectionMode: _selectedIds.isNotEmpty,
                                    onTap: () => _openScholarshipDetails(context, id, item),
                                    onLongPress: () => _toggleSelection(id),
                                  ),
                                );
                              },
                              childCount: items.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }

  Widget _dropdownFilter({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value.isEmpty ? null : value,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      items: [
        const DropdownMenuItem<String>(value: '', child: Text('All')),
        ...options.map((option) => DropdownMenuItem<String>(value: option, child: Text(option))),
      ],
      onChanged: onChanged,
    );
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

    try {
      final doc = await FirebaseFirestore.instance.collection('scholarships').doc(scholarshipId).get();
      if (!context.mounted) return;

      final data = <String, dynamic>{
        ...fallbackData,
        if (doc.data() != null) ...doc.data()!,
        'id': scholarshipId,
      };

      if (!doc.exists && data.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scholarship not found')),
        );
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ScholarshipDetailsScreen(data: data),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load scholarship')),
      );
    }
  }
}