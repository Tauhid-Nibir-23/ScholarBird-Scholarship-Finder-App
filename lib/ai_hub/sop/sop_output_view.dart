import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/scholarbird_theme.dart';
import 'sop_draft.dart';

/// Displays a generated [SopDraft] with Preview / Copy / Regenerate / PDF
/// actions.
///
/// Stateful so that Copy can show a transient snackbar confirmation.
class SopOutputView extends StatefulWidget {
  const SopOutputView({
    super.key,
    required this.draft,
    required this.onRegenerate,
    required this.onDownloadPdf,
    required this.onSaveAsDocument,
    this.isRegenerating = false,
  });

  final SopDraft draft;
  final Future<void> Function() onRegenerate;
  final Future<void> Function() onDownloadPdf;
  final Future<void> Function()? onSaveAsDocument;
  final bool isRegenerating;

  @override
  State<SopOutputView> createState() => _SopOutputViewState();
}

class _SopOutputViewState extends State<SopOutputView> {
  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.draft.body));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('SOP copied to clipboard.')),
    );
  }

  Future<void> _withMessage(Future<void> Function() action, String loading) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not $loading: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final paragraphs = draft.body
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(draft: draft),
        const SizedBox(height: ScholarBirdSpacing.small),
        if (draft.missingFields.isNotEmpty)
          _MissingFieldsHint(fields: draft.missingFields),
        const SizedBox(height: ScholarBirdSpacing.small),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final paragraph in paragraphs) ...[
                  Text(
                    paragraph,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.55,
                      color: ScholarBirdColors.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: widget.isRegenerating
                      ? null
                      : () => _withMessage(widget.onRegenerate, 'regenerate the SOP'),
                  icon: widget.isRegenerating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(
                    widget.isRegenerating ? 'Regenerating…' : 'Regenerate',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _withMessage(widget.onDownloadPdf, 'build the PDF'),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Download PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy'),
                ),
                if (widget.onSaveAsDocument != null)
                  OutlinedButton.icon(
                    onPressed: () => _withMessage(widget.onSaveAsDocument!, 'save the SOP as a document'),
                    icon: const Icon(Icons.folder_outlined),
                    label: const Text('Save as document'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.draft});

  final SopDraft draft;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ScholarBirdSpacing.medium,
        ScholarBirdSpacing.medium,
        ScholarBirdSpacing.medium,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            draft.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            draft.subtitle,
            style: const TextStyle(
              color: ScholarBirdColors.body,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _StatChip(
                icon: Icons.notes_outlined,
                label: '${draft.wordCount} words',
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.workspace_premium_outlined,
                label: draft.type.label,
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.history_outlined,
                label: draft.regenerations == 0
                    ? 'First draft'
                    : 'Regenerated ${draft.regenerations}×',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ScholarBirdColors.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: ScholarBirdColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: ScholarBirdColors.primaryDark,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingFieldsHint extends StatelessWidget {
  const _MissingFieldsHint({required this.fields});

  final List<String> fields;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ScholarBirdSpacing.medium,
      ),
      child: Container(
        padding: const EdgeInsets.all(ScholarBirdSpacing.small),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7E6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFCD9A6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline,
              size: 18,
              color: Color(0xFFB45309),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Gemini noted it didn\'t have enough on: ${fields.join(', ')}. '
                'The SOP mentions this gracefully — add a line or two on your '
                'profile to strengthen it.',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Color(0xFF92400E),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
