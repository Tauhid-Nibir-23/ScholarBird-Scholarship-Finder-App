/// Responsive data-table wrapper used by every admin list page.
///
/// On wide layouts (>= [breakpoint]) the [columns] are rendered as a
/// horizontal `DataTable`; on narrow layouts the [rowBuilder]
/// produces a stacked card list using [cardBuilder].
library;

import 'package:flutter/material.dart';

import '../admin_ui.dart';

/// Column descriptor used by the desktop `DataTable` layout.
class AdminTableColumn {
  const AdminTableColumn({
    required this.label,
    this.width,
    this.numeric = false,
  });

  final String label;
  final double? width;
  final bool numeric;
}

/// Responsive table shell.
class AdminDataTable<T> extends StatelessWidget {
  const AdminDataTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.cardBuilder,
    required this.rowBuilder,
    this.breakpoint = 880,
    this.emptyMessage = 'No items found.',
  });

  final List<AdminTableColumn> columns;

  /// Source data for the table. May be empty.
  final List<T> rows;

  /// Renders one row's cells for the desktop `DataTable`.
  final List<DataCell> Function(T item) rowBuilder;

  /// Renders the full mobile card.
  final Widget Function(T item) cardBuilder;

  final double breakpoint;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
        child: Center(
          child: Text(
            emptyMessage,
            style: const TextStyle(color: AdminPalette.body),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                cardBuilder(rows[i]),
              ],
            ],
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
            ),
            child: DataTable(
              headingTextStyle: const TextStyle(
                color: AdminPalette.body,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
              dataRowMinHeight: 56,
              dataRowMaxHeight: 72,
              columnSpacing: 24,
              columns: [
                for (final c in columns)
                  DataColumn(
                    label: Text(c.label.toUpperCase()),
                    numeric: c.numeric,
                  ),
              ],
              rows: [
                for (final item in rows)
                  DataRow(
                    cells: rowBuilder(item),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Helper: date formatter used in every admin list page. Accepts a
/// Firestore `Timestamp`, a `DateTime`, or any object with a sensible
/// `toString()` representation.
String adminFormatDate(dynamic value) {
  if (value is DateTime) {
    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/'
        '${value.year}';
  }
  return value?.toString() ?? '—';
}