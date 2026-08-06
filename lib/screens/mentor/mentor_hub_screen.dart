/// Mentor Hub — searchable faculty directory reachable from the navigation
/// drawer. The screen deliberately depends on the [Mentor] model only, so the
/// underlying data source can move from the bundled `sampleMentors` list to a
/// Firestore collection without UI changes.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/sample_mentors.dart';
import '../../models/mentor.dart';
import '../../theme/scholarbird_theme.dart';
import '../../widgets/mentor_card.dart';

class MentorHubScreen extends StatefulWidget {
  const MentorHubScreen({super.key});

  @override
  State<MentorHubScreen> createState() => _MentorHubScreenState();
}

class _MentorHubScreenState extends State<MentorHubScreen> {
  final TextEditingController _searchController = TextEditingController();

  String _query = '';
  MentorDepartment _filter = MentorDepartment.all;

  /// Firestore mentors merged with the bundled [sampleMentors]. When the
  /// admin panel has created any mentor in Firestore it shadows the sample
  /// entry with the same `id`; everything else remains for offline / first-
  /// launch fallback.
  Stream<List<Mentor>> _streamMergedMentors() {
    return FirebaseFirestore.instance
        .collection('mentors')
        .snapshots()
        .map((snapshot) {
      final byId = <String, Mentor>{
        for (final doc in snapshot.docs)
          // Always inject the doc id so the model has a stable identifier.
          doc.id: Mentor.fromMap({'id': doc.id, ...doc.data()}),
      };
      // Sample data is the offline fallback: any Firestore mentor with the
      // same id wins.
      final merged = <Mentor>[
        for (final m in sampleMentors)
          if (!byId.containsKey(m.id)) m,
        ...byId.values,
      ];
      // Sort by name so the list order is stable across data sources.
      merged.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return merged;
    });
  }

  List<Mentor> _applyFilters(List<Mentor> mentors) => mentors
      .where((m) => m.matchesFilter(_filter))
      .where((m) => m.matchesQuery(_query))
      .toList(growable: false);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? scheme.surface : ScholarBirdColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? scheme.surface : Colors.white,
        foregroundColor: ScholarBirdColors.ink,
        title: const Text(
          'Mentor Hub',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: OrientationBuilder(
          builder: (context, orientation) {
            return Column(
              children: [
                _SearchAndFilters(
                  controller: _searchController,
                  activeFilter: _filter,
                  onQueryChanged: (value) => setState(() => _query = value),
                  onFilterChanged: (filter) =>
                      setState(() => _filter = filter),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isTablet = constraints.maxWidth >= 720;
                      final isLandscape = orientation == Orientation.landscape;
                      final columns = isTablet
                          ? (isLandscape ? 3 : 2)
                          : 1;

                      return StreamBuilder<List<Mentor>>(
                        stream: _streamMergedMentors(),
                        builder: (context, snapshot) {
                          // While loading or on error, keep showing the
                          // bundled sample list so the screen never goes
                          // blank.
                          final all = snapshot.hasData
                              ? snapshot.data!
                              : sampleMentors;
                          final mentors = _applyFilters(all);
                          if (mentors.isEmpty) {
                            return const _EmptyState();
                          }
                          return SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(
                              ScholarBirdSpacing.medium,
                              0,
                              ScholarBirdSpacing.medium,
                              ScholarBirdSpacing.large,
                            ),
                            child: _ResponsiveGrid(
                              columnCount: columns,
                              gap: ScholarBirdSpacing.medium,
                              children: mentors
                                  .map((m) => MentorCard(mentor: m))
                                  .toList(growable: false),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Search + filter row ───────────────────────────────────────────────────

class _SearchAndFilters extends StatelessWidget {
  const _SearchAndFilters({
    required this.controller,
    required this.activeFilter,
    required this.onQueryChanged,
    required this.onFilterChanged,
  });

  final TextEditingController controller;
  final MentorDepartment activeFilter;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<MentorDepartment> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        ScholarBirdSpacing.medium,
        ScholarBirdSpacing.small,
        ScholarBirdSpacing.medium,
        ScholarBirdSpacing.small,
      ),
      decoration: BoxDecoration(
        color: isDark ? scheme.surface : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? scheme.outlineVariant.withValues(alpha: .4)
                : ScholarBirdColors.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            onChanged: onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search by name, department, or research area',
              hintStyle: const TextStyle(color: ScholarBirdColors.muted),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: ScholarBirdColors.body,
              ),
              filled: true,
              fillColor: isDark
                  ? scheme.surfaceContainerHighest
                  : ScholarBirdColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: ScholarBirdColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: ScholarBirdColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: ScholarBirdColors.primary,
                  width: 1.4,
                ),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: ScholarBirdSpacing.small),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: MentorDepartment.values.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: ScholarBirdSpacing.xSmall),
              itemBuilder: (context, index) {
                final dept = MentorDepartment.values[index];
                return ChoiceChip(
                  label: Text(dept.label),
                  selected: dept == activeFilter,
                  onSelected: (_) => onFilterChanged(dept),
                  backgroundColor: isDark
                      ? scheme.surfaceContainerHighest
                      : ScholarBirdColors.background,
                  selectedColor: ScholarBirdColors.primary,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: dept == activeFilter
                        ? Colors.white
                        : (isDark
                            ? scheme.onSurface
                            : ScholarBirdColors.ink),
                  ),
                  side: BorderSide(
                    color: dept == activeFilter
                        ? ScholarBirdColors.primary
                        : ScholarBirdColors.border,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Responsive grid wrapper ───────────────────────────────────────────────

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({
    required this.columnCount,
    required this.gap,
    required this.children,
  });

  final int columnCount;
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (columnCount == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _withVerticalGaps(children, gap),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _chunked(columns: columnCount).expand((row) {
        return [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _withHorizontalGaps(row, gap),
          ),
          SizedBox(height: gap),
        ];
      }).toList(),
    );
  }

  Iterable<List<Widget>> _chunked({required int columns}) sync* {
    for (var i = 0; i < children.length; i += columns) {
      yield children.sublist(
        i,
        i + columns > children.length ? children.length : i + columns,
      );
    }
  }

  List<Widget> _withVerticalGaps(List<Widget> items, double gap) {
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) out.add(SizedBox(height: gap));
      out.add(items[i]);
    }
    return out;
  }

  List<Widget> _withHorizontalGaps(List<Widget> items, double gap) {
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) out.add(SizedBox(width: gap));
      out.add(Expanded(child: items[i]));
    }
    return out;
  }
}

// ─── Empty state ───────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtle = isDark
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : ScholarBirdColors.body;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ScholarBirdSpacing.large),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: ScholarBirdColors.primary.withValues(alpha: .08),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.person_search_rounded,
                size: 38,
                color: ScholarBirdColors.primary,
              ),
            ),
            const SizedBox(height: ScholarBirdSpacing.medium),
            const Text(
              'No mentors found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: ScholarBirdColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try a different search term or filter.',
              style: TextStyle(fontSize: 13, color: subtle),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
