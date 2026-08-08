/// Mentor Hub — the new paid-mentor marketplace.
///
/// This is a different concept from the legacy "Reference Point" faculty
/// directory. The screen lists verified paid mentors from the
/// `mentors_marketplace` Firestore collection (falling back to bundled
/// sample data when the collection is empty) and lets users search and
/// filter by expertise / country / language.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../data/sample_mentor_profiles.dart';
import '../../models/mentor_profile.dart';
import '../../models/subscription_model.dart';
import '../../services/subscription_service.dart';
import '../../theme/scholarbird_theme.dart';
import '../../widgets/mentor_profile_card.dart';
import 'mentor_detail_screen.dart';

/// Holds the user's pending filter selections inside the filter sheet.
class _FilterSelection {
  const _FilterSelection({
    this.country,
    this.expertise,
    this.language,
    this.budgetMin,
    this.budgetMax,
    this.budgetFloor = 0,
    this.budgetCeiling = 1000,
  });

  final String? country;
  final String? expertise;
  final String? language;
  final double? budgetMin;
  final double? budgetMax;

  /// Inclusive lower bound the slider should clamp to.
  final double budgetFloor;

  /// Inclusive upper bound the slider should clamp to.
  final double budgetCeiling;

  bool get isEmpty =>
      country == null &&
      expertise == null &&
      language == null &&
      budgetMin == null &&
      budgetMax == null;

  _FilterSelection copyWith({
    Object? country = _sentinel,
    Object? expertise = _sentinel,
    Object? language = _sentinel,
    Object? budgetMin = _sentinel,
    Object? budgetMax = _sentinel,
  }) {
    return _FilterSelection(
      country: identical(country, _sentinel) ? this.country : country as String?,
      expertise:
          identical(expertise, _sentinel) ? this.expertise : expertise as String?,
      language:
          identical(language, _sentinel) ? this.language : language as String?,
      budgetMin:
          identical(budgetMin, _sentinel) ? this.budgetMin : budgetMin as double?,
      budgetMax:
          identical(budgetMax, _sentinel) ? this.budgetMax : budgetMax as double?,
      budgetFloor: budgetFloor,
      budgetCeiling: budgetCeiling,
    );
  }
}

const Object _sentinel = Object();

/// Opens a Daraz-style multi-section filter sheet and returns the user's
/// selection (or null if they cancel).
Future<_FilterSelection?> showFilterSheet(
  BuildContext context, {
  required List<String> countries,
  required List<String> expertise,
  required List<String> languages,
  required _FilterSelection initial,
}) {
  return showModalBottomSheet<_FilterSelection>(
    context: context,
    backgroundColor: ScholarBirdColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return _FilterSheet(
        countries: countries,
        expertise: expertise,
        languages: languages,
        initial: initial,
      );
    },
  );
}

class MentorHubScreen extends StatefulWidget {
  const MentorHubScreen({super.key});

  static const String routeName = 'mentor_hub';

  @override
  State<MentorHubScreen> createState() => _MentorHubScreenState();
}

class _MentorHubScreenState extends State<MentorHubScreen> {
  final TextEditingController _searchController = TextEditingController();
  final SubscriptionService _subscriptionService = SubscriptionService();
  StreamSubscription<SubscriptionModel>? _subscriptionSub;
  String _query = '';
  String? _countryFilter;
  String? _expertiseFilter;
  String? _languageFilter;
  double? _budgetMin;
  double? _budgetMax;
  bool _isPremium = false;

  static const String _collectionName = 'mentors_marketplace';

  @override
  void initState() {
    super.initState();
    // Wire the existing subscription state into the premium gate. The stream
    // defaults to `status: 'free'` for signed-out users, so it is safe to
    // subscribe unconditionally.
    _subscriptionSub = _subscriptionService.watch().listen((sub) {
      if (!mounted) return;
      if (sub.isPremium != _isPremium) {
        setState(() => _isPremium = sub.isPremium);
      }
    }, onError: (_) {
      // Premium state is non-critical for browse — silently fall back to
      // the free tier instead of surfacing subscription errors here.
    });
  }

  @override
  void dispose() {
    _subscriptionSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<List<MentorProfile>> _fetchFromFirestore() async {
    final snapshot = await FirebaseFirestore.instance
        .collection(_collectionName)
        .where('disabled', isEqualTo: false)
        .get();
    return snapshot.docs
        .map((d) => MentorProfile.fromMap(
              {...d.data() as Map<String, dynamic>, 'id': d.id},
            ))
        .toList();
  }

  Future<List<MentorProfile>> _loadMentors() async {
    try {
      final remote = await _fetchFromFirestore();
      if (remote.isNotEmpty) return remote;
    } catch (e) {
      debugPrint('MentorHub: remote fetch failed, falling back to sample: $e');
    }
    return sampleMentorProfiles;
  }

  List<MentorProfile> _applyFilters(List<MentorProfile> source) {
    final lowered = _query.trim().toLowerCase();
    return source.where((mentor) {
      if (mentor.disabled) return false;
      if (mentor.premiumOnly && !_isPremium) {
        // We still surface them, but the card will display the badge.
      }
      if (_countryFilter != null && mentor.country != _countryFilter) {
        return false;
      }
      if (_expertiseFilter != null) {
        if (!mentor.expertise.contains(_expertiseFilter)) return false;
      }
      if (_languageFilter != null) {
        if (!mentor.languages.contains(_languageFilter)) return false;
      }
      if (_budgetMin != null && mentor.hourlyPrice < _budgetMin!) {
        return false;
      }
      if (_budgetMax != null && mentor.hourlyPrice > _budgetMax!) {
        return false;
      }
      if (lowered.isEmpty) return true;
      return mentor.matchesQuery(lowered);
    }).toList();
  }

  // Premium state is now driven by the existing SubscriptionService.watch()
  // stream wired in initState — see `_isPremium` field above.

  void _onViewDetails(MentorProfile mentor) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MentorDetailScreen(mentor: mentor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? Theme.of(context).colorScheme.surface
        : ScholarBirdColors.background;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? Theme.of(context).colorScheme.surface : Colors.white,
        foregroundColor: ScholarBirdColors.ink,
        title: const Text(
          'Mentor Hub',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: FutureBuilder<List<MentorProfile>>(
        future: _loadMentors(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: ScholarBirdColors.primary,
              ),
            );
          }
          if (snapshot.hasError) {
            return _ErrorState(
              error: snapshot.error.toString(),
              onRetry: () => setState(() {}),
            );
          }
          final mentors = snapshot.data ?? const <MentorProfile>[];
          return _Body(
            mentors: mentors,
            filtered: _applyFilters(mentors),
            searchController: _searchController,
            onSearchChanged: (value) => setState(() => _query = value),
            countryFilter: _countryFilter,
            expertiseFilter: _expertiseFilter,
            languageFilter: _languageFilter,
            budgetMin: _budgetMin,
            budgetMax: _budgetMax,
            onFilterApply: (selection) {
              setState(() {
                _countryFilter = selection.country;
                _expertiseFilter = selection.expertise;
                _languageFilter = selection.language;
                _budgetMin = selection.budgetMin;
                _budgetMax = selection.budgetMax;
              });
            },
            onViewDetails: _onViewDetails,
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.mentors,
    required this.filtered,
    required this.searchController,
    required this.onSearchChanged,
    required this.countryFilter,
    required this.expertiseFilter,
    required this.languageFilter,
    required this.budgetMin,
    required this.budgetMax,
    required this.onFilterApply,
    required this.onViewDetails,
  });

  final List<MentorProfile> mentors;
  final List<MentorProfile> filtered;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String? countryFilter;
  final String? expertiseFilter;
  final String? languageFilter;
  final double? budgetMin;
  final double? budgetMax;
  final void Function(_FilterSelection) onFilterApply;
  final void Function(MentorProfile) onViewDetails;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtleTextColor =
        isDark ? Theme.of(context).colorScheme.onSurfaceVariant : ScholarBirdColors.body;

    final countries = <String>{
      for (final m in mentors) if (m.country.isNotEmpty) m.country,
    }.toList()
      ..sort();

    final expertise = <String>{for (final m in mentors) ...m.expertise}.toList()
      ..sort();

    final languages = <String>{for (final m in mentors) ...m.languages}.toList()
      ..sort();

    double budgetFloor = 0;
    double budgetCeiling = 200;
    for (final m in mentors) {
      if (m.hourlyPrice < budgetFloor) budgetFloor = m.hourlyPrice;
      if (m.hourlyPrice > budgetCeiling) budgetCeiling = m.hourlyPrice;
    }
    budgetFloor = budgetFloor.floorToDouble();
    budgetCeiling = (budgetCeiling.ceilToDouble()).clamp(50, 1000);

    final hasActiveFilter = countryFilter != null ||
        expertiseFilter != null ||
        languageFilter != null ||
        budgetMin != null ||
        budgetMax != null;

    final activeCount = [
      countryFilter,
      expertiseFilter,
      languageFilter,
      budgetMin,
      budgetMax,
    ].where((v) => v != null).length;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _Header(subtleTextColor: subtleTextColor),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              ScholarBirdSpacing.medium,
              0,
              ScholarBirdSpacing.medium,
              ScholarBirdSpacing.small,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search by name, university…',
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: ScholarBirdColors.primary,
                      ),
                      suffixIcon: searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                searchController.clear();
                                onSearchChanged('');
                              },
                            ),
                      filled: true,
                      fillColor: isDark
                          ? Theme.of(context).colorScheme.surface
                          : ScholarBirdColors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            BorderSide(color: ScholarBirdColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            BorderSide(color: ScholarBirdColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: ScholarBirdColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _FilterButton(
                  active: hasActiveFilter,
                  activeCount: activeCount,
                  onTap: () async {
                    final selection = await showFilterSheet(
                      context,
                      countries: countries,
                      expertise: expertise,
                      languages: languages,
                      initial: _FilterSelection(
                        country: countryFilter,
                        expertise: expertiseFilter,
                        language: languageFilter,
                        budgetMin: budgetMin,
                        budgetMax: budgetMax,
                        budgetFloor: budgetFloor,
                        budgetCeiling: budgetCeiling,
                      ),
                    );
                    if (selection != null) {
                      onFilterApply(selection);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        if (filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              query: searchController.text,
              onResetFilters: () {
                onFilterApply(
                  _FilterSelection(
                    country: null,
                    expertise: null,
                    language: null,
                    budgetMin: null,
                    budgetMax: null,
                    budgetFloor: budgetFloor,
                    budgetCeiling: budgetCeiling,
                  ),
                );
              },
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              ScholarBirdSpacing.medium,
              0,
              ScholarBirdSpacing.medium,
              ScholarBirdSpacing.large,
            ),
            sliver: SliverList.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: ScholarBirdSpacing.medium),
              itemBuilder: (context, index) {
                final mentor = filtered[index];
                return MentorProfileCard(
                  mentor: mentor,
                  onViewDetails: () => onViewDetails(mentor),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.subtleTextColor});

  final Color subtleTextColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        ScholarBirdSpacing.medium,
        ScholarBirdSpacing.medium,
        ScholarBirdSpacing.medium,
        ScholarBirdSpacing.small,
      ),
      padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ScholarBirdColors.primary, ScholarBirdColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.school_rounded,
              color: ScholarBirdColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Find your mentor',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Verified scholarship mentors from top universities.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .92),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.active,
    required this.onTap,
    required this.activeCount,
  });

  final bool active;
  final int activeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark
        ? Theme.of(context).colorScheme.surface
        : ScholarBirdColors.surface;
    return Material(
      color: fillColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: active ? ScholarBirdColors.primary : ScholarBirdColors.border,
          width: active ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune_rounded,
                size: 18,
                color:
                    active ? ScholarBirdColors.primary : ScholarBirdColors.body,
              ),
              const SizedBox(width: 6),
              const Text(
                'Filter',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: ScholarBirdColors.ink,
                ),
              ),
              if (active) ...[
                const SizedBox(width: 6),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: ScholarBirdColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                if (activeCount > 1) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$activeCount',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: ScholarBirdColors.primary,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Daraz-style multi-section filter sheet shown as a modal bottom sheet.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.countries,
    required this.expertise,
    required this.languages,
    required this.initial,
  });

  final List<String> countries;
  final List<String> expertise;
  final List<String> languages;
  final _FilterSelection initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late _FilterSelection _draft = widget.initial;
  late RangeValues _range = RangeValues(
    _draft.budgetMin ?? widget.initial.budgetFloor,
    _draft.budgetMax ?? widget.initial.budgetCeiling,
  );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.85;
    final bottomInset = media.viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ScholarBirdColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _SheetHeader(
                onReset: () {
                  setState(() {
                    _draft = _FilterSelection(
                      budgetFloor: widget.initial.budgetFloor,
                      budgetCeiling: widget.initial.budgetCeiling,
                    );
                    _range = RangeValues(
                      widget.initial.budgetFloor,
                      widget.initial.budgetCeiling,
                    );
                  });
                },
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    ScholarBirdSpacing.medium,
                    0,
                    ScholarBirdSpacing.medium,
                    16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionTitle('Country'),
                      _ChipWrap(
                        options: widget.countries,
                        selected: _draft.country,
                        onSelected: (v) => setState(
                          () => _draft = _draft.copyWith(country: v),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _SectionTitle('Expertise'),
                      _ChipWrap(
                        options: widget.expertise,
                        selected: _draft.expertise,
                        onSelected: (v) => setState(
                          () => _draft = _draft.copyWith(expertise: v),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _SectionTitle('Budget range (per hour)'),
                      _BudgetRange(
                        range: _range,
                        min: widget.initial.budgetFloor,
                        max: widget.initial.budgetCeiling,
                        onChanged: (r) {
                          setState(() {
                            _range = r;
                            final atMin = (r.start - widget.initial.budgetFloor)
                                    .abs() <
                                0.5;
                            final atMax = (r.end - widget.initial.budgetCeiling)
                                    .abs() <
                                0.5;
                            _draft = _draft.copyWith(
                              budgetMin: atMin ? null : r.start,
                              budgetMax: atMax ? null : r.end,
                            );
                          });
                        },
                      ),
                      const SizedBox(height: 20),
                      _SectionTitle('Language'),
                      _ChipWrap(
                        options: widget.languages,
                        selected: _draft.language,
                        onSelected: (v) => setState(
                          () => _draft = _draft.copyWith(language: v),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: ScholarBirdColors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ScholarBirdSpacing.medium,
                  12,
                  ScholarBirdSpacing.medium,
                  12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: ScholarBirdColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: ScholarBirdColors.ink,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: ScholarBirdColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => Navigator.of(context).pop(_draft),
                        child: const Text(
                          'Apply',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.onReset});
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ScholarBirdSpacing.medium,
        12,
        ScholarBirdSpacing.medium,
        4,
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Filter',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: ScholarBirdColors.ink,
              ),
            ),
          ),
          TextButton(
            onPressed: onReset,
            child: const Text(
              'Reset',
              style: TextStyle(
                color: ScholarBirdColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: ScholarBirdColors.ink,
        ),
      ),
    );
  }
}

/// Single-select chip group for one filter dimension.
class _ChipWrap extends StatelessWidget {
  const _ChipWrap({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return Text(
        'No options available',
        style: TextStyle(
          fontSize: 12,
          color: ScholarBirdColors.body.withValues(alpha: 0.7),
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final opt in options)
          _ChoiceChip(
            label: opt,
            isSelected: opt == selected,
            onTap: () => onSelected(opt == selected ? null : opt),
          ),
      ],
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? ScholarBirdColors.primary : ScholarBirdColors.surface,
          border: Border.all(
            color: isSelected ? ScholarBirdColors.primary : ScholarBirdColors.border,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : ScholarBirdColors.ink,
          ),
        ),
      ),
    );
  }
}

class _BudgetRange extends StatelessWidget {
  const _BudgetRange({
    required this.range,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final RangeValues range;
  final double min;
  final double max;
  final ValueChanged<RangeValues> onChanged;

  String _fmt(double v) {
    if (v >= max) return '\$${max.toStringAsFixed(0)}+';
    return '\$${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _fmt(range.start),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: ScholarBirdColors.ink,
              ),
            ),
            Text(
              _fmt(range.end),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: ScholarBirdColors.ink,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: ScholarBirdColors.primary,
            inactiveTrackColor: ScholarBirdColors.border,
            thumbColor: ScholarBirdColors.primary,
            overlayColor: ScholarBirdColors.primary.withValues(alpha: 0.12),
            valueIndicatorColor: ScholarBirdColors.primary,
          ),
          child: RangeSlider(
            values: range,
            min: min,
            max: max,
            divisions: (max - min).round().clamp(2, 50),
            labels: RangeLabels(_fmt(range.start), _fmt(range.end)),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query, required this.onResetFilters});

  final String query;
  final VoidCallback onResetFilters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.search_off_rounded,
            size: 56,
            color: ScholarBirdColors.body,
          ),
          const SizedBox(height: 12),
          const Text(
            'No mentors match your filters',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: ScholarBirdColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            query.isEmpty
                ? 'Try a different country or area of expertise.'
                : 'No mentors match "$query".',
            textAlign: TextAlign.center,
            style: const TextStyle(color: ScholarBirdColors.body),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onResetFilters,
            child: const Text('Reset filters'),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.redAccent),
          const SizedBox(height: 12),
          const Text(
            'Could not load mentors',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(color: ScholarBirdColors.body),
          ),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
