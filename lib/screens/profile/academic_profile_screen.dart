import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profile_widgets.dart';

class AcademicProfileScreen extends StatefulWidget {
  const AcademicProfileScreen({super.key});

  @override
  State<AcademicProfileScreen> createState() => _AcademicProfileScreenState();
}

class _AcademicProfileScreenState extends State<AcademicProfileScreen> {
  final _currentYearController = TextEditingController();
  final _cgpaController = TextEditingController();
  final _cgpaScaleController = TextEditingController();
  final _ieltsController = TextEditingController();
  final _toeflController = TextEditingController();
  final _researchController = TextEditingController();
  final _publicationsController = TextEditingController();
  final _workController = TextEditingController();
  final _graduationYearController = TextEditingController();
  final _backlogsController = TextEditingController();
  final _englishMediumController = TextEditingController();
  final _awardsController = TextEditingController();
  final _targetDegreeController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  final List<String> _yesNoOptions = ['Yes', 'No'];
  final List<String> _targetDegreeOptions = [
    'Masters',
    'PhD',
    'Research',
    'Exchange',
  ];

  @override
  void initState() {
    super.initState();
    _loadAcademicProfile();
  }

  @override
  void dispose() {
    _currentYearController.dispose();
    _cgpaController.dispose();
    _cgpaScaleController.dispose();
    _ieltsController.dispose();
    _toeflController.dispose();
    _researchController.dispose();
    _publicationsController.dispose();
    _workController.dispose();
    _graduationYearController.dispose();
    _backlogsController.dispose();
    _englishMediumController.dispose();
    _awardsController.dispose();
    _targetDegreeController.dispose();
    super.dispose();
  }

  Future<void> _loadAcademicProfile() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      final data = snapshot.data();
      if (data != null) {
        _currentYearController.text = (data['currentYear'] ?? '').toString();
        _cgpaController.text = (data['cgpa'] ?? '').toString();
        _cgpaScaleController.text = (data['cgpaScale'] ?? '').toString();
        _ieltsController.text = (data['ielts'] ?? '').toString();
        _toeflController.text = (data['toefl'] ?? '').toString();
        final researchValue = data['researchExperience'];
        if (researchValue is bool) {
          _researchController.text = researchValue ? 'Yes' : 'No';
        } else {
          _researchController.text = (researchValue ?? '').toString();
        }
        _publicationsController.text = (data['publicationCount'] ?? '').toString();
        _workController.text = (data['workExperienceYears'] ?? '').toString();
        _graduationYearController.text = (data['graduationYear'] ?? '').toString();
        _backlogsController.text = (data['backlogs'] ?? '').toString();
        final englishMediumValue = data['englishMedium'];
        if (englishMediumValue is bool) {
          _englishMediumController.text = englishMediumValue ? 'Yes' : 'No';
        } else {
          _englishMediumController.text = (englishMediumValue ?? '').toString();
        }
        _awardsController.text = (data['awardsCount'] ?? '').toString();
        _targetDegreeController.text = (data['targetDegree'] ?? '').toString();
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Unable to load academic profile. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveAcademicProfile() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showMessage('Please log in to update your academic profile.');
      return;
    }

    final currentYear = int.tryParse(_currentYearController.text.trim()) ?? 0;
    if (currentYear < 1 || currentYear > 8) {
      _showMessage('Current year must be between 1 and 8');
      return;
    }

    final cgpa = double.tryParse(_cgpaController.text.trim()) ?? 0;
    final cgpaScale = double.tryParse(_cgpaScaleController.text.trim()) ?? 4.0;
    if (cgpaScale <= 0) {
      _showMessage('CGPA scale must be greater than 0.');
      return;
    }
    if (cgpa < 0) {
      _showMessage('CGPA cannot be negative');
      return;
    }
    if (cgpa > cgpaScale) {
      _showMessage('CGPA cannot exceed $cgpaScale');
      return;
    }

    final ielts = double.tryParse(_ieltsController.text.trim()) ?? 0;
    if (ielts > 9.0) {
      _showMessage('IELTS score cannot exceed 9');
      return;
    }

    final toefl = int.tryParse(_toeflController.text.trim()) ?? 0;
    if (toefl < 0 || toefl > 120) {
      _showMessage('TOEFL score must be between 0 and 120');
      return;
    }

    final graduationYear =
        int.tryParse(_graduationYearController.text.trim()) ?? 0;
    final currentCalendarYear = DateTime.now().year;
    if (graduationYear < currentCalendarYear - 10 ||
        graduationYear > currentCalendarYear + 10) {
      _showMessage('Enter a valid graduation year');
      return;
    }

    final backlogs = int.tryParse(_backlogsController.text.trim()) ?? 0;
    if (backlogs < 0) {
      _showMessage('Backlogs cannot be negative');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .set({
        'currentYear': currentYear,
        'cgpa': cgpa,
        'cgpaScale': cgpaScale,
        'ielts': double.tryParse(_ieltsController.text.trim()) ?? 0,
        'toefl': toefl,
        'researchExperience': _researchController.text.trim().toLowerCase() == 'yes',
        'publicationCount': int.tryParse(_publicationsController.text.trim()) ?? 0,
        'workExperienceYears':
            double.tryParse(_workController.text.trim()) ?? 0,
        'graduationYear': graduationYear,
        'backlogs': backlogs,
        'englishMedium':
            _englishMediumController.text.trim().toLowerCase() == 'yes',
        'awardsCount': int.tryParse(_awardsController.text.trim()) ?? 0,
        'targetDegree': _targetDegreeController.text.trim(),
        'academicProfileCompleted': true,
        'academicUpdatedAt': Timestamp.now(),
      }, SetOptions(merge: true));

      if (mounted) {
        _showMessage('Academic profile saved.');
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Failed to save academic profile.');
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
            'Academic Profile',
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
                        'Boost your scholarship matches',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: sbText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Add your academic details for AI-driven matching.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: sbSecondaryText,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ProfileTextField(
                        controller: _currentYearController,
                        hintText: 'Current Year',
                        prefixIcon: Icons.calendar_today_outlined,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      ProfileTextField(
                        controller: _cgpaController,
                        hintText: 'CGPA',
                        prefixIcon: Icons.grade_outlined,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 16),
                      ProfileTextField(
                        controller: _cgpaScaleController,
                        hintText: 'CGPA Scale (e.g., 4.0, 5.0)',
                        prefixIcon: Icons.tune_outlined,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 16),
                      ProfileTextField(
                        controller: _ieltsController,
                        hintText: 'IELTS Score',
                        prefixIcon: Icons.record_voice_over_outlined,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 16),
                      ProfileTextField(
                        controller: _toeflController,
                        hintText: 'TOEFL Score',
                        prefixIcon: Icons.headphones_outlined,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      ProfileDropdownField(
                        label: 'Research Experience',
                        hint: 'Select Yes or No',
                        value: _yesNoOptions.contains(_researchController.text.trim())
                            ? _researchController.text.trim()
                            : null,
                        items: _yesNoOptions,
                        prefixIcon: Icons.science_outlined,
                        onChanged: (value) {
                          _researchController.text = value ?? '';
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 16),
                      ProfileTextField(
                        controller: _publicationsController,
                        hintText: 'Number of Publications',
                        prefixIcon: Icons.menu_book_outlined,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      ProfileTextField(
                        controller: _workController,
                        hintText: 'Work Experience (Years)',
                        prefixIcon: Icons.work_outline,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 16),
                      ProfileTextField(
                        controller: _backlogsController,
                        hintText: 'Backlogs',
                        prefixIcon: Icons.error_outline,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      ProfileDropdownField(
                        label: 'English Medium',
                        hint: 'Select Yes or No',
                        value: _yesNoOptions.contains(_englishMediumController.text.trim())
                            ? _englishMediumController.text.trim()
                            : null,
                        items: _yesNoOptions,
                        prefixIcon: Icons.language_outlined,
                        onChanged: (value) {
                          _englishMediumController.text = value ?? '';
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 16),
                      ProfileTextField(
                        controller: _awardsController,
                        hintText: 'Awards Count',
                        prefixIcon: Icons.emoji_events_outlined,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      ProfileTextField(
                        controller: _graduationYearController,
                        hintText: 'Graduation Year',
                        prefixIcon: Icons.school_outlined,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      ProfileDropdownField(
                        label: 'Target Degree',
                        hint: 'Select your scholarship target',
                        value: _targetDegreeOptions
                                .contains(_targetDegreeController.text.trim())
                            ? _targetDegreeController.text.trim()
                            : null,
                        items: _targetDegreeOptions,
                        prefixIcon: Icons.flag_outlined,
                        onChanged: (value) {
                          _targetDegreeController.text = value ?? '';
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 28),
                      ProfilePrimaryButton(
                        title: 'Save',
                        onPressed: _saveAcademicProfile,
                        isLoading: _isSaving,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
      );
}
