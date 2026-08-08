/// Admin screen for managing the **Reference Point** directory
/// (professors, researchers, labs, universities).
///
/// Streams records from the Firestore `reference_points` collection.
/// Previously this lived in the `mentors` collection; the rename was
/// performed to keep the Reference Point (free directory) and the
/// Mentor Hub (paid marketplace) fully independent.
///
/// Supports free-text search across name / designation / university /
/// research interests, department filtering, sort by name / department /
/// availability, and full CRUD through [MentorFormScreen].
///
/// Tapping a record opens the form for edit/delete; the floating
/// action button opens it for create.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/mentor.dart';
import '../data/sample_mentors.dart';
import '../services/firestore_collections.dart';
import '../theme/scholarbird_theme.dart';
import 'admin_ui.dart';
import 'mentor_admin_form.dart';
import 'widgets/admin_data_table.dart';
import 'widgets/admin_dialogs.dart';
import 'widgets/admin_empty_state.dart';
import 'widgets/admin_filter_bar.dart';
import 'widgets/admin_search_bar.dart';
import 'widgets/admin_section.dart';

class MentorAdminScreen extends StatefulWidget {
  const MentorAdminScreen({super.key});

  @override
  State<MentorAdminScreen> createState() => _MentorAdminScreenState();
}

enum _MentorSort { name, department, availability }

class _MentorAdminScreenState extends State<MentorAdminScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _searchCtrl = TextEditingController();
  String _query = '';
  MentorDepartment _department = MentorDepartment.all;
  _MentorSort _sort = _MentorSort.name;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters => _department != MentorDepartment.all;

  void _clearFilters() => setState(() => _department = MentorDepartment.all);

  Future<void> _showFilters() => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFFD7DDEA), borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 18),
              Row(children: [
                const Icon(Icons.tune_rounded, color: AdminPalette.primary),
                const SizedBox(width: 10),
                const Expanded(child: Text('Filter mentors', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                TextButton(onPressed: _clearFilters, child: const Text('Reset')),
              ]),
              const SizedBox(height: 12),
              AdminFilterBar<MentorDepartment>(
                options: [for (final d in MentorDepartment.values) if (d != MentorDepartment.all) AdminFilterOption(d, d.label, icon: Icons.label_outline)],
                selected: _department == MentorDepartment.all ? <MentorDepartment>{} : {_department},
                singleSelect: true,
                onChanged: (value) => setState(() => _department = value.isEmpty ? MentorDepartment.all : value.first),
              ),
              const SizedBox(height: 18),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.of(sheetContext).pop(), child: const Text('Show results'))),
            ]),
          ),
        ),
      );

  Future<void> _openForm(BuildContext context, {Mentor? mentor}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MentorFormScreen(mentor: mentor),
      ),
    );
  }

  Future<void> _deleteMentor(BuildContext context, Mentor mentor) async {
    final confirmed = await AdminDialogs.confirm(
      context: context,
      title: 'Delete reference entry?',
      message:
          'This removes ${mentor.name.isEmpty ? "this entry" : mentor.name} from the Reference Point directory. The portrait in Supabase Storage will also be deleted.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    try {
      await _firestore
          .collection(kCollectionReferencePoints)
          .doc(mentor.id)
          .delete();
      if (mounted) {
        AdminDialogs.success(context, 'Reference entry deleted');
      }
    } catch (e) {
      if (mounted) {
        AdminDialogs.error(context, 'Could not delete entry: $e');
      }
    }
  }

  /// One-time migration for the reference fixtures that originally shipped
  /// only as local Mentor Hub (Reference Point) data. Existing Firestore
  /// documents are never overwritten. Writes go to the new
  /// `reference_points` collection.
  Future<void> _importBuiltInMentors(BuildContext context) async {
    try {
      final batch = _firestore.batch();
      for (final mentor in sampleMentors) {
        final ref = _firestore
            .collection(kCollectionReferencePoints)
            .doc(mentor.id);
        final existing = await ref.get();
        if (existing.exists) continue;
        batch.set(ref, {
          'id': mentor.id,
          'name': mentor.name,
          'designation': mentor.designation,
          'department': mentor.department.label,
          'university': mentor.university,
          'researchInterests': mentor.researchInterests,
          'bio': mentor.bio,
          'email': mentor.email,
          'photoUrl': mentor.photoUrl,
          'phone': mentor.phone,
          'officeRoom': mentor.officeRoom,
          'availableDays': mentor.availableDays,
          'availableTime': mentor.availableTime,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      if (mounted) {
        AdminDialogs.success(context,
            '${sampleMentors.length} reference entries imported');
      }
    } catch (e) {
      if (mounted) {
        AdminDialogs.error(context, 'Could not import reference entries: $e');
      }
    }
  }

  List<Mentor> _applyClientSideFilters(List<Mentor> input) {
    final filtered = input
        .where((mentor) => mentor.matchesFilter(_department))
        .where((mentor) => mentor.matchesQuery(_query))
        .toList();
    switch (_sort) {
      case _MentorSort.department:
        filtered.sort((a, b) {
          final byDept = a.department.label
              .toLowerCase()
              .compareTo(b.department.label.toLowerCase());
          if (byDept != 0) return byDept;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        break;
      case _MentorSort.availability:
        filtered.sort((a, b) =>
            b.availableDays.length.compareTo(a.availableDays.length));
        break;
      case _MentorSort.name:
        filtered.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? Theme.of(context).colorScheme.surface
          : Colors.white,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Add reference'),
        backgroundColor: AdminPalette.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestore
            .collection(kCollectionReferencePoints)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(ScholarBirdSpacing.large),
                child: Text('Could not load reference points: ${snapshot.error}'),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: AdminLoadingSkeleton(itemCount: 6, itemHeight: 72),
            );
          }

          final mentors = (snapshot.data?.docs ?? const [])
              .map((doc) => Mentor.fromMap({'id': doc.id, ...doc.data()}))
              .toList(growable: false);

          final filtered = _applyClientSideFilters(mentors);

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
                  title: 'Reference Points',
                  subtitle:
                      'Manage the professor and research directory surfaced in the Reference Point feature. Paid mentors live in Mentor Marketplace.',
                  actions: [
                    FilledButton.icon(
                      onPressed: () => _openForm(context),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('New reference'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AdminPalette.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                AdminSection(
                  title: 'Reference Point directory',
                  subtitle:
                      '${filtered.length} of ${mentors.length} entries shown',
                  icon: Icons.school_outlined,
                  action: PopupMenuButton<_MentorSort>(
                    tooltip: 'Sort',
                    icon: const Icon(Icons.sort, color: AdminPalette.heading),
                    onSelected: (value) =>
                        setState(() => _sort = value),
                    itemBuilder: (_) => [
                      for (final s in _MentorSort.values)
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
                        hintText: 'Search by name, university, or interest…',
                        onChanged: (value) => setState(() => _query = value),
                      ),
                      const SizedBox(height: 12),
                      AdminFilterBar<MentorDepartment>(
                        options: [
                          for (final d in MentorDepartment.values)
                            if (d != MentorDepartment.all)
                              AdminFilterOption<MentorDepartment>(
                                d,
                                d.label,
                                icon: Icons.label_outline,
                              ),
                        ],
                        selected: _department == MentorDepartment.all
                            ? <MentorDepartment>{}
                            : {_department},
                        singleSelect: true,
                        onChanged: (value) => setState(() {
                          _department = value.isEmpty
                              ? MentorDepartment.all
                              : value.first;
                        }),
                        onClear: () => setState(
                            () => _department = MentorDepartment.all),
                      ),
                      const SizedBox(height: 12),
                      if (filtered.isEmpty)
                        AdminEmptyState(
                          icon: Icons.person_search_outlined,
                          title: mentors.isEmpty
                              ? 'No reference points in Firestore yet'
                              : 'No reference points match the filters',
                          message: mentors.isEmpty
                              ? 'Tap "New reference" to create the first one.'
                              : 'Try clearing the search or department filter.',
                          action: mentors.isEmpty
                              ? FilledButton.icon(
                                  onPressed: () => _importBuiltInMentors(context),
                                  icon: const Icon(Icons.cloud_upload_outlined),
                                  label: const Text('Import built-in references'),
                                )
                              : null,
                        )
                      else
                        AdminDataTable<Mentor>(
                          columns: const [
                            AdminTableColumn(label: 'Mentor'),
                            AdminTableColumn(label: 'Department'),
                            AdminTableColumn(label: 'University'),
                            AdminTableColumn(label: 'Contact'),
                            AdminTableColumn(label: 'Availability'),
                            AdminTableColumn(label: 'Actions'),
                          ],
                          rows: filtered,
                          cardBuilder: (mentor) => _MentorCard(
                            mentor: mentor,
                            onEdit: () => _openForm(context, mentor: mentor),
                            onDelete: () => _deleteMentor(context, mentor),
                          ),
                          rowBuilder: (mentor) => [
                            DataCell(_MentorCell(mentor: mentor)),
                            DataCell(Text(mentor.department.label)),
                            DataCell(Text(
                              mentor.university.isEmpty
                                  ? '—'
                                  : mentor.university,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            )),
                            DataCell(Text(
                              mentor.email.isEmpty ? '—' : mentor.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )),
                            DataCell(Text(
                              mentor.availableDays.isEmpty
                                  ? '—'
                                  : '${mentor.availableDays.join(', ')}'
                                      '${(mentor.availableTime?.isNotEmpty ?? false) ? ' • ${mentor.availableTime}' : ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            )),
                            DataCell(Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Edit',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () =>
                                      _openForm(context, mentor: mentor),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Color(0xFFDC2626),
                                  ),
                                  onPressed: () =>
                                      _deleteMentor(context, mentor),
                                ),
                              ],
                            )),
                          ],
                        ),
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

  static String _sortLabel(_MentorSort sort) {
    switch (sort) {
      case _MentorSort.name:
        return 'Sort by name';
      case _MentorSort.department:
        return 'Sort by department';
      case _MentorSort.availability:
        return 'Sort by availability';
    }
  }
}

class _MentorCell extends StatelessWidget {
  const _MentorCell({required this.mentor});

  final Mentor mentor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AdminPalette.primary.withValues(alpha: 0.12),
          backgroundImage:
              (mentor.photoUrl != null && mentor.photoUrl!.isNotEmpty)
                  ? NetworkImage(mentor.photoUrl!)
                  : null,
          child: (mentor.photoUrl == null || mentor.photoUrl!.isEmpty)
              ? Text(
                  mentor.name.isEmpty
                      ? '?'
                      : mentor.name.characters.first.toUpperCase(),
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
                mentor.name.isEmpty ? 'Unnamed mentor' : mentor.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AdminPalette.heading,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (mentor.designation.isNotEmpty)
                Text(
                  mentor.designation,
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

class _MentorCard extends StatelessWidget {
  const _MentorCard({
    required this.mentor,
    required this.onEdit,
    required this.onDelete,
  });

  final Mentor mentor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AdminSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AdminPalette.primary.withValues(alpha: 0.12),
                backgroundImage:
                    (mentor.photoUrl != null && mentor.photoUrl!.isNotEmpty)
                        ? NetworkImage(mentor.photoUrl!)
                        : null,
                child: (mentor.photoUrl == null || mentor.photoUrl!.isEmpty)
                    ? Text(
                        mentor.name.isEmpty
                            ? '?'
                            : mentor.name.characters.first.toUpperCase(),
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
                      mentor.name.isEmpty ? 'Unnamed mentor' : mentor.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AdminPalette.heading,
                      ),
                    ),
                    Text(
                      mentor.designation.isEmpty
                          ? mentor.department.label
                          : '${mentor.designation} • ${mentor.department.label}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminPalette.body,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (mentor.university.isNotEmpty)
            _row(Icons.account_balance, mentor.university),
          if (mentor.email.isNotEmpty) _row(Icons.mail_outline, mentor.email),
          if (mentor.availableDays.isNotEmpty)
            _row(
              Icons.event_available,
              '${mentor.availableDays.join(', ')}'
              '${(mentor.availableTime?.isNotEmpty ?? false) ? ' • ${mentor.availableTime}' : ''}',
            ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: AdminPalette.body),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  color: AdminPalette.body,
                ),
              ),
            ),
          ],
        ),
      );
}
