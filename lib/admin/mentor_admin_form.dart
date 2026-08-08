/// Add / edit form for a single **Reference Point** entry in the admin panel.
///
/// Reference Point stores professors, researchers, labs and universities in
/// the Firestore `reference_points` collection. This screen does not touch
/// the `mentors_marketplace` collection used by the Mentor Hub.
///
/// When [mentor] is null the form is in "create" mode and the page
/// generates a fresh doc id on save. Otherwise it edits the existing
/// Firestore document in place.
///
/// Photo upload goes through [MentorImageService] → Supabase Storage
/// `reference-points/{entryId}.jpg`. The public URL is written back into
/// the reference document in the same transaction.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/mentor.dart';
import '../services/firestore_collections.dart';
import '../services/mentor_image_service.dart';
import '../theme/scholarbird_theme.dart';
import 'admin_ui.dart';
import 'widgets/admin_dialogs.dart';
import 'widgets/admin_image_upload.dart';

class MentorFormScreen extends StatefulWidget {
  const MentorFormScreen({super.key, this.mentor});

  /// Existing reference entry (edit mode). `null` → create a new
  /// reference point in the `reference_points` collection.
  final Mentor? mentor;

  @override
  State<MentorFormScreen> createState() => _MentorFormScreenState();
}

class _MentorFormScreenState extends State<MentorFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirebaseFirestore.instance;

  late final TextEditingController _name;
  late final TextEditingController _designation;
  late final TextEditingController _university;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _officeRoom;
  late final TextEditingController _researchInterests;
  late final TextEditingController _bio;
  late final TextEditingController _availableTime;

  MentorDepartment _department = MentorDepartment.computerScience;
  final Set<String> _selectedDays = <String>{};

  String? _photoUrl;
  late final String _docId;
  late final bool _isNew;

  bool _saving = false;

  static const _dayChoices = <String>['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  void initState() {
    super.initState();
    final mentor = widget.mentor;
    _isNew = mentor == null;
    _docId = mentor?.id ?? _firestore.collection(kCollectionReferencePoints).doc().id;

    _name = TextEditingController(text: mentor?.name ?? '');
    _designation = TextEditingController(text: mentor?.designation ?? '');
    _university = TextEditingController(text: mentor?.university ?? '');
    _email = TextEditingController(text: mentor?.email ?? '');
    _phone = TextEditingController(text: mentor?.phone ?? '');
    _officeRoom = TextEditingController(text: mentor?.officeRoom ?? '');
    _researchInterests = TextEditingController(
      text: (mentor?.researchInterests ?? const []).join(', '),
    );
    _bio = TextEditingController(text: mentor?.bio ?? '');
    _availableTime = TextEditingController(text: mentor?.availableTime ?? '');
    _department = mentor?.department ?? MentorDepartment.computerScience;
    _selectedDays.addAll(mentor?.availableDays ?? const []);
    _photoUrl = mentor?.photoUrl;
  }

  @override
  void dispose() {
    _name.dispose();
    _designation.dispose();
    _university.dispose();
    _email.dispose();
    _phone.dispose();
    _officeRoom.dispose();
    _researchInterests.dispose();
    _bio.dispose();
    _availableTime.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedDays.isEmpty) {
      AdminDialogs.error(context, 'Pick at least one available day.');
      return;
    }
    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{
        'id': _docId,
        'name': _name.text.trim(),
        'designation': _designation.text.trim(),
        'department': _department.label,
        'university': _university.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'officeRoom': _officeRoom.text.trim(),
        'researchInterests': _researchInterests.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        'bio': _bio.text.trim(),
        'availableDays': _selectedDays.toList(growable: false),
        'availableTime': _availableTime.text.trim(),
        'photoUrl': _photoUrl,
      };
      await _firestore
          .collection(kCollectionReferencePoints)
          .doc(_docId)
          .set(data, SetOptions(merge: true));
      if (!mounted) return;
      AdminDialogs.success(context, _isNew ? 'Reference added' : 'Reference updated');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      AdminDialogs.error(context, 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await AdminDialogs.confirm(
      context: context,
      title: 'Delete reference entry?',
      message:
          'This will remove the reference (professor/researcher/lab) from Firestore. The portrait in Supabase Storage will also be deleted.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    setState(() => _saving = true);
    try {
      await MentorImageService.instance.removeMentorImage(_docId);
      await _firestore.collection(kCollectionReferencePoints).doc(_docId).delete();
      if (!mounted) return;
      AdminDialogs.success(context, 'Reference entry deleted');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      AdminDialogs.error(context, 'Delete failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? Theme.of(context).colorScheme.surface
          : Colors.white,
      appBar: AppBar(
        title: Text(_isNew ? 'Add reference' : 'Edit reference'),
        actions: [
          if (!_isNew)
            IconButton(
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete reference entry',
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Form(
              key: _formKey,
              child: ListView(
            padding: const EdgeInsets.fromLTRB(
              ScholarBirdSpacing.medium,
              ScholarBirdSpacing.medium,
              ScholarBirdSpacing.medium,
              96,
            ),
            children: [
              AdminImageUpload(
                mentorId: _docId,
                photoUrl: _photoUrl,
                name: _name.text,
                onChanged: (url) => setState(() => _photoUrl = url),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  _isNew
                      ? 'Tap the avatar to upload a portrait.'
                      : 'Tap the avatar to update or remove the portrait.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AdminPalette.body,
                  ),
                ),
              ),
              const SizedBox(height: ScholarBirdSpacing.large),
              _Field(
                child: TextFormField(
                  controller: _name,
                  decoration: _inputDecoration('Full name', Icons.person),
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              _Field(
                child: TextFormField(
                  controller: _designation,
                  decoration: _inputDecoration(
                    'Designation (e.g. Professor)',
                    Icons.school_outlined,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Designation is required'
                      : null,
                ),
              ),
              _Field(
                child: DropdownButtonFormField<MentorDepartment>(
                  initialValue: _department,
                  decoration: _inputDecoration('Department', Icons.label),
                  items: [
                    for (final d in MentorDepartment.values)
                      if (d != MentorDepartment.all)
                        DropdownMenuItem(value: d, child: Text(d.label)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _department = v);
                  },
                ),
              ),
              _Field(
                child: TextFormField(
                  controller: _university,
                  decoration: _inputDecoration('University', Icons.account_balance),
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'University is required'
                      : null,
                ),
              ),
              _Field(
                child: TextFormField(
                  controller: _email,
                  decoration: _inputDecoration('Email', Icons.mail_outline),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email is required';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
              ),
              _Field(
                child: TextFormField(
                  controller: _phone,
                  decoration: _inputDecoration('Phone (optional)', Icons.call),
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                ),
              ),
              _Field(
                child: TextFormField(
                  controller: _officeRoom,
                  decoration: _inputDecoration(
                    'Office room (optional)',
                    Icons.room_outlined,
                  ),
                  textInputAction: TextInputAction.next,
                ),
              ),
              _Field(
                child: TextFormField(
                  controller: _researchInterests,
                  decoration: _inputDecoration(
                    'Research interests (comma-separated)',
                    Icons.science_outlined,
                  ),
                  textInputAction: TextInputAction.next,
                ),
              ),
              _Field(
                child: TextFormField(
                  controller: _availableTime,
                  decoration: _inputDecoration(
                    'Available time (e.g. 10:00 AM – 1:00 PM)',
                    Icons.access_time,
                  ),
                  textInputAction: TextInputAction.next,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Available days',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final day in _dayChoices)
                    FilterChip(
                      label: Text(day),
                      selected: _selectedDays.contains(day),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedDays.add(day);
                          } else {
                            _selectedDays.remove(day);
                          }
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: ScholarBirdSpacing.medium),
              _Field(
                child: TextFormField(
                  controller: _bio,
                  decoration: _inputDecoration('Short biography', Icons.notes),
                  minLines: 3,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                ),
              ),
              const SizedBox(height: ScholarBirdSpacing.large),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_isNew ? 'Add reference' : 'Save changes'),
                style: FilledButton.styleFrom(
                  backgroundColor: AdminPalette.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      isDense: true,
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: child,
      );
}

