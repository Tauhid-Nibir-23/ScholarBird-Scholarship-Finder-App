import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'add_scholarship_page.dart';
import 'admin_ui.dart';

class ScholarshipPage extends StatefulWidget {
  const ScholarshipPage({super.key});

  @override
  State<ScholarshipPage> createState() => _ScholarshipPageState();
}

class _ScholarshipPageState extends State<ScholarshipPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openForm([DocumentSnapshot<Map<String, dynamic>>? document]) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AddScholarshipPage(scholarship: document),
        ),
      );

  Future<void> _toggleValue(
    DocumentSnapshot<Map<String, dynamic>> document,
    String field,
  ) async {
    final currentValue = document.data()?[field] == true;
    try {
      await document.reference.update({field: !currentValue});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update scholarship.')),
        );
      }
    }
  }

  Future<void> _deleteScholarship(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete scholarship?'),
        content: Text(
          '“${document.data()?['title'] ?? 'This scholarship'}” will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await document.reference.delete();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not delete scholarship.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance.collection('scholarships').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load scholarships.'));
          }

          final scholarships = snapshot.data?.docs.where((document) {
                final data = document.data();
                final query = _searchQuery.toLowerCase();
                return data['title'].toString().toLowerCase().contains(query) ||
                    data['country'].toString().toLowerCase().contains(query) ||
                    data['field'].toString().toLowerCase().contains(query);
              }).toList() ??
              [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Scholarships',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                                'Create and manage scholarship opportunities.'),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _openForm,
                        icon: const Icon(Icons.add),
                        label: const Text('Add scholarship'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  AdminSurface(
                    padding: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          TextField(
                            controller: _searchController,
                            onChanged: (value) =>
                                setState(() => _searchQuery = value.trim()),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Search by title, country, or field',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (snapshot.connectionState ==
                              ConnectionState.waiting)
                            const Padding(
                              padding: EdgeInsets.all(32),
                              child: CircularProgressIndicator(),
                            )
                          else if (scholarships.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(32),
                              child: Text('No scholarships found.'),
                            )
                          else
                            LayoutBuilder(
                              builder: (context, constraints) => constraints
                                          .maxWidth <
                                      760
                                  ? Column(
                                      children: scholarships
                                          .map((document) => _ScholarshipCard(
                                                document: document,
                                                onEdit: () =>
                                                    _openForm(document),
                                                onFeature: () => _toggleValue(
                                                    document, 'isFeatured'),
                                                onHide: () => _toggleValue(
                                                    document, 'isHidden'),
                                                onDelete: () =>
                                                    _deleteScholarship(
                                                        document),
                                              ))
                                          .toList(),
                                    )
                                  : SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: DataTable(
                                        columns: const [
                                          DataColumn(
                                              label: Text('Scholarship')),
                                          DataColumn(label: Text('Country')),
                                          DataColumn(label: Text('Deadline')),
                                          DataColumn(label: Text('Visibility')),
                                          DataColumn(label: Text('Actions')),
                                        ],
                                        rows: scholarships.map((document) {
                                          final data = document.data();
                                          final hidden =
                                              data['isHidden'] == true;
                                          final featured =
                                              data['isFeatured'] == true;
                                          return DataRow(cells: [
                                            DataCell(Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(data['title']
                                                          ?.toString() ??
                                                      'Untitled'),
                                                  if (featured)
                                                    const Text('Featured',
                                                        style: TextStyle(
                                                            fontSize: 12))
                                                ])),
                                            DataCell(Text(
                                                data['country']?.toString() ??
                                                    '—')),
                                            DataCell(Text(
                                                data['deadline']?.toString() ??
                                                    '—')),
                                            DataCell(Chip(
                                                label: Text(hidden
                                                    ? 'Hidden'
                                                    : 'Visible'))),
                                            DataCell(Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                      onPressed: () =>
                                                          _openForm(document),
                                                      icon: const Icon(
                                                          Icons.edit_outlined),
                                                      tooltip: 'Edit'),
                                                  IconButton(
                                                      onPressed: () =>
                                                          _toggleValue(document,
                                                              'isFeatured'),
                                                      icon: Icon(featured
                                                          ? Icons.star
                                                          : Icons.star_outline),
                                                      tooltip: featured
                                                          ? 'Remove feature'
                                                          : 'Feature'),
                                                  IconButton(
                                                      onPressed: () =>
                                                          _toggleValue(document,
                                                              'isHidden'),
                                                      icon: Icon(hidden
                                                          ? Icons.visibility
                                                          : Icons
                                                              .visibility_off),
                                                      tooltip: hidden
                                                          ? 'Show scholarship'
                                                          : 'Hide scholarship'),
                                                  IconButton(
                                                      onPressed: () =>
                                                          _deleteScholarship(
                                                              document),
                                                      icon: const Icon(
                                                          Icons.delete_outline),
                                                      tooltip: 'Delete'),
                                                ])),
                                          ]);
                                        }).toList(),
                                      ),
                                    ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

class _ScholarshipCard extends StatelessWidget {
  const _ScholarshipCard(
      {required this.document,
      required this.onEdit,
      required this.onFeature,
      required this.onHide,
      required this.onDelete});

  final DocumentSnapshot<Map<String, dynamic>> document;
  final VoidCallback onEdit;
  final VoidCallback onFeature;
  final VoidCallback onHide;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final data = document.data()!;
    final featured = data['isFeatured'] == true;
    final hidden = data['isHidden'] == true;
    return AdminSurface(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.only(bottom: 14),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: AdminPalette.primary.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(14)),
            child:
                const Icon(Icons.school_outlined, color: AdminPalette.primary)),
        title: Text(data['title']?.toString() ?? 'Untitled'),
        subtitle: Text(
            '${data['country'] ?? '—'} • ${data['deadline'] ?? 'No deadline'}',
            style: const TextStyle(color: AdminPalette.body)),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') onEdit();
            if (value == 'feature') onFeature();
            if (value == 'hide') onHide();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
                value: 'feature',
                child:
                    Text(featured ? 'Remove feature' : 'Feature scholarship')),
            PopupMenuItem(
                value: 'hide',
                child: Text(hidden ? 'Show scholarship' : 'Hide scholarship')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}
