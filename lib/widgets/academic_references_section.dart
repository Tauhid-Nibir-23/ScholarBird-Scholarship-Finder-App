/// Renders the "Academic References" section on the profile screen.
///
/// Streams the user's references subcollection and renders a
/// [ReferenceCard] for every existing reference. To enforce the
/// "Reference 1 / Reference 2" requirement the section keeps two named
/// slots — if a slot has no record yet the card is rendered in empty
/// state with an "Add Reference" button.
library;

import 'package:flutter/material.dart';

import '../models/reference_model.dart';
import '../services/references_service.dart';
import '../theme/scholarbird_theme.dart';
import 'reference_card.dart';

/// Section widget that renders the two academic reference slots.
class AcademicReferencesSection extends StatefulWidget {
  const AcademicReferencesSection({super.key});

  @override
  State<AcademicReferencesSection> createState() =>
      _AcademicReferencesSectionState();
}

class _AcademicReferencesSectionState extends State<AcademicReferencesSection> {
  static const _slotIds = ['reference1', 'reference2'];
  static const _slotLabels = ['Reference 1', 'Reference 2'];

  final _service = ReferencesService.instance;
  late final Stream<List<ReferenceModel>> _stream;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _stream = _service.streamReferences();
  }

  Future<void> _onEdit(ReferenceModel reference) async {
    final updated = await _promptForReference(reference);
    if (updated == null) return;
    await _persist(updated);
  }

  Future<void> _onAdd(String slotId, String slotLabel) async {
    final initial = ReferenceModel.empty(slotId);
    final updated = await _promptForReference(
      initial,
      title: 'Add $slotLabel',
    );
    if (updated == null) return;
    await _persist(updated);
  }

  Future<void> _onDelete(ReferenceModel reference) async {
    final confirm = await _confirmDelete(reference);
    if (confirm != true) return;
    setState(() => _busyId = reference.id);
    try {
      await _service.deleteReference(reference.id);
      if (mounted) _toast('Reference deleted.');
    } catch (e) {
      if (mounted) _toast('Failed to delete reference: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<ReferenceModel?> _promptForReference(
    ReferenceModel reference, {
    String? title,
  }) {
    return showModalBottomSheet<ReferenceModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: _ReferenceSheet(reference: reference, title: title),
      ),
    );
  }

  Future<void> _persist(ReferenceModel reference) async {
    setState(() => _busyId = reference.id);
    try {
      await _service.saveReference(reference);
      if (mounted) _toast('Reference saved.');
    } catch (e) {
      if (mounted) _toast('Failed to save reference: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<bool?> _confirmDelete(ReferenceModel reference) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete reference'),
        content: Text(
          'Remove ${reference.fullName.isEmpty ? 'this reference' : reference.fullName}? '
          'You can add it again at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFDC2626)),
            ),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Map<String, ReferenceModel> _slotMap(List<ReferenceModel> records) {
    final map = <String, ReferenceModel>{};
    for (final record in records) {
      map[record.id] = record;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final containerColor = isDark ? scheme.surface : ScholarBirdColors.surface;
    final borderColor = isDark
        ? scheme.outlineVariant.withValues(alpha: .6)
        : ScholarBirdColors.border;
    final subtleTextColor =
        isDark ? scheme.onSurfaceVariant : ScholarBirdColors.body;

    return StreamBuilder<List<ReferenceModel>>(
      stream: _stream,
      initialData: const <ReferenceModel>[],
      builder: (context, snapshot) {
        final records = snapshot.data ?? const <ReferenceModel>[];
        final byId = _slotMap(records);
        final filledCount = _slotIds
            .where((id) => byId[id]?.isComplete == true)
            .length;

        return Container(
          decoration: BoxDecoration(
            color: containerColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: ScholarBirdColors.primary.withValues(alpha: .04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(
                horizontal: ScholarBirdSpacing.medium,
                vertical: 4,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(
                ScholarBirdSpacing.medium,
                0,
                ScholarBirdSpacing.medium,
                ScholarBirdSpacing.medium,
              ),
              initiallyExpanded: false,
              iconColor: ScholarBirdColors.primary,
              collapsedIconColor: ScholarBirdColors.primary,
              title: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: ScholarBirdColors.primary.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.people_alt_outlined,
                      color: ScholarBirdColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: ScholarBirdSpacing.small),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Academic References',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: ScholarBirdColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$filledCount of 2 references added',
                          style: TextStyle(
                            fontSize: 12,
                            color: subtleTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              children: List<Widget>.generate(_slotIds.length, (index) {
                final slotId = _slotIds[index];
                final slotLabel = _slotLabels[index];
                final reference = byId[slotId] ?? ReferenceModel.empty(slotId);
                return Padding(
                  padding: const EdgeInsets.only(
                    bottom: ScholarBirdSpacing.small,
                  ),
                  child: ReferenceCard(
                    reference: reference,
                    slotLabel: slotLabel,
                    isBusy: _busyId == slotId,
                    onAdd: () => _onAdd(slotId, slotLabel),
                    onEdit: () => _onEdit(reference),
                    onDelete: () => _onDelete(reference),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}

// ─── Reference edit / add sheet ───────────────────────────────────────────

class _ReferenceSheet extends StatefulWidget {
  const _ReferenceSheet({required this.reference, this.title});

  final ReferenceModel reference;
  final String? title;

  @override
  State<_ReferenceSheet> createState() => _ReferenceSheetState();
}

class _ReferenceSheetState extends State<_ReferenceSheet> {
  late final TextEditingController _fullName;
  late final TextEditingController _designation;
  late final TextEditingController _department;
  late final TextEditingController _university;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _customRelationship;
  RelationshipType? _relationship;
  String? _relationshipError;

  @override
  void initState() {
    super.initState();
    _fullName = TextEditingController(text: widget.reference.fullName);
    _designation = TextEditingController(text: widget.reference.designation);
    _department = TextEditingController(text: widget.reference.department);
    _university = TextEditingController(text: widget.reference.university);
    _email = TextEditingController(text: widget.reference.email);
    _phone = TextEditingController(text: widget.reference.phone);
    _customRelationship = TextEditingController(
      text: widget.reference.customRelationship ?? '',
    );
    _relationship = widget.reference.relationship;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _designation.dispose();
    _department.dispose();
    _university.dispose();
    _email.dispose();
    _phone.dispose();
    _customRelationship.dispose();
    super.dispose();
  }

  bool _isEmailValid(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed);
  }

  void _save() {
    final fullName = _fullName.text.trim();
    final email = _email.text.trim();
    final university = _university.text.trim();

    if (fullName.isEmpty) {
      setState(() => _relationshipError = 'Full name is required.');
      return;
    }
    if (!_isEmailValid(email)) {
      setState(() => _relationshipError = 'Please enter a valid official email.');
      return;
    }
    if (university.isEmpty) {
      setState(() => _relationshipError = 'University is required.');
      return;
    }

    final phone = _phone.text.trim();
    if (phone.isNotEmpty && !RegExp(r'^[+\d][\d\s\-()]{4,}$').hasMatch(phone)) {
      setState(() => _relationshipError = 'Please enter a valid phone number.');
      return;
    }

    final updated = widget.reference.copyWith(
      fullName: fullName,
      designation: _designation.text.trim(),
      department: _department.text.trim(),
      university: university,
      email: email,
      phone: phone,
      relationship: _relationship,
      customRelationship: _customRelationship.text.trim().isEmpty
          ? null
          : _customRelationship.text.trim(),
    );
    Navigator.pop(context, updated);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetColor = isDark ? scheme.surface : ScholarBirdColors.surface;
    final subtleTextColor =
        isDark ? scheme.onSurfaceVariant : ScholarBirdColors.body;

    return Container(
      decoration: BoxDecoration(
        color: sheetColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: ScholarBirdColors.muted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              widget.title ?? 'Edit Reference',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: ScholarBirdColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Provide the contact details of an academic referee who can '
              'speak to your studies or research.',
              style: TextStyle(fontSize: 12, color: subtleTextColor),
            ),
            const SizedBox(height: 16),
            _Field(label: 'Full Name', controller: _fullName, icon: Icons.person_outline),
            const SizedBox(height: 12),
            _Field(label: 'Designation', controller: _designation, icon: Icons.badge_outlined),
            const SizedBox(height: 12),
            _Field(label: 'Department', controller: _department, icon: Icons.school_outlined),
            const SizedBox(height: 12),
            _Field(label: 'University', controller: _university, icon: Icons.account_balance_outlined),
            const SizedBox(height: 12),
            _Field(
              label: 'Official Email',
              controller: _email,
              icon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            _Field(
              label: 'Phone Number',
              controller: _phone,
              icon: Icons.call_outlined,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _RelationshipDropdown(
              value: _relationship,
              onChanged: (value) => setState(() => _relationship = value),
            ),
            const SizedBox(height: 12),
            _Field(
              label: 'Custom Relationship (Optional)',
              controller: _customRelationship,
              icon: Icons.notes_outlined,
            ),
            if (_relationshipError != null) ...[
              const SizedBox(height: 8),
              Text(
                _relationshipError!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFDC2626),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.icon,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: ScholarBirdColors.primary),
      ),
    );
  }
}

class _RelationshipDropdown extends StatelessWidget {
  const _RelationshipDropdown({required this.value, required this.onChanged});

  final RelationshipType? value;
  final ValueChanged<RelationshipType?> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = <RelationshipType?>[
      null,
      ...RelationshipType.values,
    ];
    return DropdownButtonFormField<RelationshipType?>(
      initialValue: items.contains(value) ? value : null,
      decoration: const InputDecoration(
        labelText: 'Relationship',
        prefixIcon: Icon(Icons.people_outline, color: ScholarBirdColors.primary),
      ),
      isExpanded: true,
      icon: const Icon(Icons.expand_more, color: ScholarBirdColors.primary),
      dropdownColor: ScholarBirdColors.surface,
      items: items
          .map(
            (item) => DropdownMenuItem<RelationshipType?>(
              value: item,
              child: Text(
                item?.label ?? 'Select relationship',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: item == null ? ScholarBirdColors.muted : ScholarBirdColors.ink,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}
