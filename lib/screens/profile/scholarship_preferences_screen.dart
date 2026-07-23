import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profile_widgets.dart';

class ScholarshipPreferencesScreen extends StatefulWidget {
  const ScholarshipPreferencesScreen({super.key});

  @override
  State<ScholarshipPreferencesScreen> createState() => _ScholarshipPreferencesScreenState();
}

class _ScholarshipPreferencesScreenState extends State<ScholarshipPreferencesScreen> {
  final Set<String> _preferredCountries = {};
  final Set<String> _interestedFields = {};
  final Set<String> _fundingTypes = {};
  final Set<String> _intakes = {};
  String? _preferredDegree;

  bool _isLoading = true;
  bool _isSaving = false;

  final List<String> _countries = [
    'Australia',
    'Austria',
    'Bangladesh',
    'Belgium',
    'Brazil',
    'Canada',
    'China',
    'Denmark',
    'Finland',
    'France',
    'Germany',
    'Greece',
    'Hungary',
    'India',
    'Ireland',
    'Italy',
    'Japan',
    'Malaysia',
    'Netherlands',
    'New Zealand',
    'Norway',
    'Poland',
    'Portugal',
    'Qatar',
    'Saudi Arabia',
    'Singapore',
    'South Korea',
    'Spain',
    'Sweden',
    'Switzerland',
    'Turkey',
    'UAE',
    'UK',
    'USA',
  ];
  final List<String> _degrees = ['Undergraduate', 'Masters', 'PhD', 'Research', 'Exchange'];
  final List<String> _fundingTypeOptions = [
    'Fully Funded',
    'Partial Funded',
    'Self Funded',
  ];
  final List<String> _intakeOptions = ['Spring', 'Summer', 'Fall'];
  final List<String> _fields = [
    'AI',
    'Architecture',
    'Bioinformatics',
    'Biotechnology',
    'Business Analytics',
    'Chemical Engineering',
    'Civil Engineering',
    'Cyber Security',
    'Data Science',
    'Design',
    'EEE',
    'Environmental Science',
    'Finance',
    'HCI',
    'Healthcare',
    'International Relations',
    'Law',
    'MBA',
    'Mechanical Engineering',
    'Marketing',
    'Mathematics',
    'Physics',
    'Public Policy',
    'Robotics',
    'Software Engineering',
  ];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();

      final data = snapshot.data();
      if (data != null) {
        final countries = (data['preferredCountries'] as List?)?.cast<String>() ?? [];
        final fields = (data['interestedFields'] as List?)?.cast<String>() ?? [];
        final fundingTypes = (data['fundingTypes'] as List?)?.cast<String>() ?? [];
        final intakes = (data['intakes'] as List?)?.cast<String>() ?? [];
        _preferredCountries
          ..clear()
          ..addAll(countries);
        _interestedFields
          ..clear()
          ..addAll(fields);
        _fundingTypes
          ..clear()
          ..addAll(fundingTypes);
        _intakes
          ..clear()
          ..addAll(intakes);
        _preferredDegree = data['preferredDegree'] as String?;
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Unable to load preferences. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _savePreferences() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showMessage('Please log in to update preferences.');
      return;
    }

    if (_preferredCountries.isEmpty) {
      _showMessage('Select at least one preferred country');
      return;
    }

    if (_preferredCountries.length > 10) {
      _showMessage('Select up to 10 countries');
      return;
    }

    if (_preferredDegree == null) {
      _showMessage('Select a preferred degree');
      return;
    }

    if (_interestedFields.isEmpty) {
      _showMessage('Select at least one field of interest');
      return;
    }

    if (_interestedFields.length > 10) {
      _showMessage('Select up to 10 fields');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .set({
        'preferredCountries': _preferredCountries.toList(),
        'preferredDegree': _preferredDegree,
        'interestedFields': _interestedFields.toList(),
        'fundingTypes': _fundingTypes.toList(),
        'intakes': _intakes.toList(),
        'preferencesCompleted': true,
        'preferencesUpdatedAt': Timestamp.now(),
      }, SetOptions(merge: true));

      if (mounted) {
        _showMessage('Preferences saved.');
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Failed to save preferences.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: sbBackground,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Scholarship Preferences',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: sbText,
            ),
          ),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: sbText),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: sbPrimary))
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Personalize your feed',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: sbText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Choose your preferences to get tailored scholarships.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: sbSecondaryText,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildMultiSelectField(
                        label: 'Preferred Countries',
                        hintText: 'Select countries',
                        icon: Icons.public_outlined,
                        options: _countries,
                        selected: _preferredCountries,
                      ),
                      const SizedBox(height: 24),
                      ProfileDropdownField(
                        label: 'Preferred Degree',
                        hint: 'Select degree',
                        value: _preferredDegree,
                        items: _degrees,
                        prefixIcon: Icons.school_outlined,
                        onChanged: (value) => setState(() => _preferredDegree = value),
                      ),
                      const SizedBox(height: 24),
                      _buildMultiSelectField(
                        label: 'Interested Fields',
                        hintText: 'Select fields',
                        icon: Icons.tune_outlined,
                        options: _fields,
                        selected: _interestedFields,
                      ),
                      const SizedBox(height: 24),
                      _buildMultiSelectField(
                        label: 'Funding Type',
                        hintText: 'Select funding type',
                        icon: Icons.account_balance_wallet_outlined,
                        options: _fundingTypeOptions,
                        selected: _fundingTypes,
                      ),
                      const SizedBox(height: 24),
                      _buildMultiSelectField(
                        label: 'Intake',
                        hintText: 'Select intake',
                        icon: Icons.event_outlined,
                        options: _intakeOptions,
                        selected: _intakes,
                      ),
                      const SizedBox(height: 28),
                      ProfilePrimaryButton(
                        title: 'Save',
                        onPressed: _savePreferences,
                        isLoading: _isSaving,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
      );

  Widget _buildMultiSelectField({
    required String label,
    required String hintText,
    required IconData icon,
    required List<String> options,
    required Set<String> selected,
  }) {
    final selectedText = selected.isEmpty ? hintText : selected.join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileSectionLabel(label),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _openMultiSelectSheet(
            title: label,
            options: options,
            selected: selected,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sbBorder, width: 1.5),
            ),
            child: Row(
              children: [
                Icon(icon, color: sbPrimary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    selectedText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: selected.isEmpty ? sbHintText : sbText,
                    ),
                  ),
                ),
                const Icon(
                  Icons.expand_more,
                  color: sbPrimary,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openMultiSelectSheet({
    required String title,
    required List<String> options,
    required Set<String> selected,
  }) async {
    final searchController = TextEditingController();
    final localSelected = Set<String>.from(selected);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final query = searchController.text.trim().toLowerCase();
          final filtered = options
              .where((item) => item.toLowerCase().contains(query))
              .toList();

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: sbText,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: sbPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search',
                      hintStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: sbHintText,
                      ),
                      prefixIcon: const Icon(Icons.search, color: sbPrimary),
                      filled: true,
                      fillColor: sbBackground,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: sbBorder),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final isSelected = localSelected.contains(item);
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (value) {
                            setSheetState(() {
                              if (value == true) {
                                localSelected.add(item);
                              } else {
                                localSelected.remove(item);
                              }
                            });
                          },
                          activeColor: sbPrimary,
                          title: Text(
                            item,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: sbText,
                            ),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  ProfilePrimaryButton(
                    title: 'Apply Selection',
                    onPressed: () {
                      setState(() {
                        selected
                          ..clear()
                          ..addAll(localSelected);
                      });
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
