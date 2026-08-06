/// Multi-select chip filter bar used by every admin list page.
///
/// Designed to replace ad-hoc `Wrap` + `FilterChip` blocks. Supports
/// a single-select groups (sort by) and multi-select groups (filter
/// by) coexisting in one row, with a clear-all action.
library;

import 'package:flutter/material.dart';

import '../admin_ui.dart';

/// One filter item shown in the bar.
class AdminFilterOption<T> {
  const AdminFilterOption(this.value, this.label, {this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// A horizontally scrolling row of chips. Pass [singleSelect] `true`
/// for a sort/group selector, `false` for the typical multi-select.
class AdminFilterBar<T> extends StatelessWidget {
  const AdminFilterBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.singleSelect = false,
    this.label,
    this.onClear,
  });

  final List<AdminFilterOption<T>> options;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;
  final bool singleSelect;
  final String? label;
  final VoidCallback? onClear;

  void _toggle(T value) {
    final next = Set<T>.from(selected);
    if (singleSelect) {
      if (next.contains(value)) {
        next.remove(value);
      } else {
        next
          ..clear()
          ..add(value);
      }
    } else {
      if (next.contains(value)) {
        next.remove(value);
      } else {
        next.add(value);
      }
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final canClear = selected.isNotEmpty && onClear != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final chips = <Widget>[];
        if (label != null) {
          chips.add(
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                label!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AdminPalette.body,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          );
        }
        for (final option in options) {
          final isSelected = selected.contains(option.value);
          chips.add(_ChoiceChip(
            label: option.label,
            icon: option.icon,
            selected: isSelected,
            onTap: () => _toggle(option.value),
          ));
        }
        if (canClear) {
          chips.add(
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('Clear'),
                style: TextButton.styleFrom(
                  foregroundColor: AdminPalette.body,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                chips[i],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: selected
          ? primary.withValues(alpha: 0.12)
          : Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? primary : const Color(0xFFE5E7EB),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: selected ? primary : AdminPalette.body,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? primary : AdminPalette.heading,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
