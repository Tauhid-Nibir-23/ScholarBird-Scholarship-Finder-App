/// Renders the "Documents" section on the profile screen.
///
/// Streams every supported [DocumentType] from the user's documents
/// subcollection and renders a [DocumentCard] for each. The whole section
/// is collapsible (ExpansionTile) so it does not dominate the profile view.
///
/// All upload / replace / delete actions are routed back to the parent
/// via callbacks so this widget stays decoupled from the actual file
/// picker. A lightweight in-app placeholder flow is provided so the
/// feature is usable end-to-end today.
library;

import 'package:flutter/material.dart';

import '../models/document_model.dart';
import '../services/documents_service.dart';
import '../theme/scholarbird_theme.dart';
import 'document_card.dart';

/// Section widget that renders all document slots for the current user.
class DocumentsSection extends StatefulWidget {
  const DocumentsSection({super.key});

  @override
  State<DocumentsSection> createState() => _DocumentsSectionState();
}

class _DocumentsSectionState extends State<DocumentsSection> {
  final _service = DocumentsService.instance;
  late final Stream<List<DocumentModel>> _stream;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _stream = _service.streamDocuments();
  }

  Future<void> _onUpload(DocumentModel document) async {
    await _persist(document, pickFile: true);
  }

  Future<void> _onReplace(DocumentModel document) async {
    await _persist(document, pickFile: true);
  }

  Future<void> _onView(DocumentModel document) async {
    final url = document.downloadUrl?.trim() ?? '';
    if (url.isEmpty) {
      _toast('No download URL is available for this document yet.');
      return;
    }
    final ok = await openDocumentDownloadUrl(url);
    if (!ok && mounted) {
      _toast('Unable to open the document link.');
    }
  }

  Future<void> _onDelete(DocumentModel document) async {
    final confirm = await _confirmDelete(document);
    if (confirm != true) return;
    setState(() => _busyId = document.type.firestoreId);
    try {
      await _service.deleteDocument(document.type);
    } catch (e) {
      if (mounted) _toast('Failed to delete document: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _persist(
    DocumentModel document, {
    bool pickFile = false,
  }) async {
    // ignore: avoid_print
    print('[DocUpload] _persist START type=${document.type.firestoreId} pickFile=$pickFile');
    setState(() => _busyId = document.type.firestoreId);
    try {
      await _service.saveDocument(document, pickFile: pickFile);
      // ignore: avoid_print
      print('[DocUpload] _persist SUCCESS type=${document.type.firestoreId}');
      if (mounted) {
        _toast(
          pickFile
              ? '${document.type.label} uploaded.'
              : '${document.type.label} saved.',
        );
      }
    } catch (e) {
      // ignore: avoid_print
      print('[DocUpload] _persist FAILED type=${document.type.firestoreId} err=$e');
      if (mounted) _toast('Failed to save document: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<bool?> _confirmDelete(DocumentModel document) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete document'),
        content: Text(
          'Remove the metadata for "${document.type.label}"? '
          'You can upload it again at any time.',
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

    return StreamBuilder<List<DocumentModel>>(
      stream: _stream,
      initialData: DocumentType.values
          .map((type) => DocumentModel(type: type))
          .toList(growable: false),
      builder: (context, snapshot) {
        final documents = snapshot.data ??
            DocumentType.values
                .map((type) => DocumentModel(type: type))
                .toList(growable: false);
        final uploadedCount = documents.where((d) => d.isUploaded).length;
        final total = documents.length;

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
            // Removes the default ExpansionTile divider lines.
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
                      Icons.folder_open_outlined,
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
                          'Documents',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: ScholarBirdColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$uploadedCount of $total uploaded',
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
              children: documents
                  .map(
                    (doc) => Padding(
                      padding: const EdgeInsets.only(
                        bottom: ScholarBirdSpacing.small,
                      ),
                      child: DocumentCard(
                        document: doc,
                        isBusy: _busyId == doc.type.firestoreId,
                        onUpload: () => _onUpload(doc),
                        onView: () => _onView(doc),
                        onReplace: () => _onReplace(doc),
                        onDelete: () => _onDelete(doc),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
  }
}

