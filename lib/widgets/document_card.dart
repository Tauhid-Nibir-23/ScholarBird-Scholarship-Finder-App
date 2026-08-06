/// Reusable card that renders a single uploadable document slot.
///
/// Visual language matches the rest of the profile screens: white surface,
/// 12px radius, thin `#E5E7EB` border, ScholarBird primary accent, dark-
/// mode aware.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/document_model.dart';
import '../theme/scholarbird_theme.dart';

/// Renders a single [DocumentModel] with the appropriate action buttons.
///
/// When [document.isUploaded] is true the card shows View / Replace / Delete.
/// Otherwise it shows a single Upload button. All callbacks are forwarded
/// to the parent so this widget stays purely presentational.
class DocumentCard extends StatelessWidget {
  const DocumentCard({
    super.key,
    required this.document,
    required this.onUpload,
    required this.onView,
    required this.onReplace,
    required this.onDelete,
    this.isBusy = false,
  });

  final DocumentModel document;
  final VoidCallback onUpload;
  final VoidCallback onView;
  final VoidCallback onReplace;
  final VoidCallback onDelete;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? scheme.surface : ScholarBirdColors.surface;
    final borderColor = isDark
        ? scheme.outlineVariant.withValues(alpha: .6)
        : ScholarBirdColors.border;
    final subtleTextColor =
        isDark ? scheme.onSurfaceVariant : ScholarBirdColors.body;

    final uploaded = document.isUploaded;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: ScholarBirdColors.primary.withValues(alpha: isDark ? .08 : .04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(document: document, subtleTextColor: subtleTextColor),
          const SizedBox(height: ScholarBirdSpacing.small),
          _MetadataRow(
            document: document,
            subtleTextColor: subtleTextColor,
          ),
          const SizedBox(height: ScholarBirdSpacing.medium),
          _ActionsRow(
            document: document,
            isBusy: isBusy,
            onUpload: onUpload,
            onView: onView,
            onReplace: onReplace,
            onDelete: onDelete,
          ),
        ],
      ),
    );
  }
}

// ─── Header (icon + title + status badge) ──────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.document, required this.subtleTextColor});

  final DocumentModel document;
  final Color subtleTextColor;

  @override
  Widget build(BuildContext context) {
    final uploaded = document.isUploaded;
    final accent = uploaded
        ? ScholarBirdColors.primary
        : ScholarBirdColors.muted;
    final statusBg = uploaded
        ? ScholarBirdColors.primary.withValues(alpha: .1)
        : ScholarBirdColors.background;
    final statusFg = uploaded
        ? ScholarBirdColors.primaryDark
        : ScholarBirdColors.body;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: ScholarBirdColors.primary.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(
            document.type.icon,
            color: ScholarBirdColors.primary,
            size: 22,
          ),
        ),
        const SizedBox(width: ScholarBirdSpacing.small),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                document.type.label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: ScholarBirdColors.ink,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                document.fileName?.trim().isNotEmpty == true
                    ? document.fileName!
                    : 'No file uploaded yet',
                style: TextStyle(fontSize: 12, color: subtleTextColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: ScholarBirdSpacing.small),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusBg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent.withValues(alpha: .25)),
          ),
          child: Text(
            uploaded ? 'Uploaded' : 'Not uploaded',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: statusFg,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Metadata row (date + size) ────────────────────────────────────────────

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.document, required this.subtleTextColor});

  final DocumentModel document;
  final Color subtleTextColor;

  @override
  Widget build(BuildContext context) {
    final uploaded = document.isUploaded;
    if (!uploaded) {
      return Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: subtleTextColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Upload this document to keep your profile complete.',
              style: TextStyle(fontSize: 12, color: subtleTextColor),
            ),
          ),
        ],
      );
    }
    final dateLabel = document.uploadedAt == null
        ? '—'
        : _formatDate(document.uploadedAt!);
    return Row(
      children: [
        Icon(Icons.calendar_today_outlined, size: 14, color: subtleTextColor),
        const SizedBox(width: 6),
        Text(
          dateLabel,
          style: TextStyle(fontSize: 12, color: subtleTextColor),
        ),
        const SizedBox(width: ScholarBirdSpacing.small),
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: subtleTextColor.withValues(alpha: .6),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: ScholarBirdSpacing.small),
        Icon(Icons.straighten_outlined, size: 14, color: subtleTextColor),
        const SizedBox(width: 6),
        Text(
          document.displaySize,
          style: TextStyle(fontSize: 12, color: subtleTextColor),
        ),
      ],
    );
  }

  static String _formatDate(DateTime value) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }
}

// ─── Action buttons ────────────────────────────────────────────────────────

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({
    required this.document,
    required this.isBusy,
    required this.onUpload,
    required this.onView,
    required this.onReplace,
    required this.onDelete,
  });

  final DocumentModel document;
  final bool isBusy;
  final VoidCallback onUpload;
  final VoidCallback onView;
  final VoidCallback onReplace;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final uploaded = document.isUploaded;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxWidth < 360;
        if (!uploaded) {
          return SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: isBusy ? null : onUpload,
              icon: isBusy
                  ? const _TinySpinner()
                  : const Icon(Icons.cloud_upload_outlined, size: 18),
              label: const Text('Upload'),
            ),
          );
        }
        final view = _OutlinedAction(
          icon: Icons.visibility_outlined,
          label: 'View',
          onTap: isBusy ? null : onView,
        );
        final replace = _OutlinedAction(
          icon: Icons.swap_horiz_rounded,
          label: 'Replace',
          onTap: isBusy ? null : onReplace,
        );
        final delete = _DangerAction(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          onTap: isBusy ? null : onDelete,
        );
        if (tight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: view),
                  const SizedBox(width: 8),
                  Expanded(child: replace),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(height: 40, child: delete),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: view),
            const SizedBox(width: 8),
            Expanded(child: replace),
            const SizedBox(width: 8),
            Expanded(child: delete),
          ],
        );
      },
    );
  }
}

class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 16),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      );
}

class _DangerAction extends StatelessWidget {
  const _DangerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 16),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFDC2626),
            side: const BorderSide(color: Color(0xFFDC2626), width: 1.2),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      );
}

class _TinySpinner extends StatelessWidget {
  const _TinySpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
}

/// Helper for callers — opens the supplied download URL with the system
/// browser via [url_launcher]. Returns false when the URL is empty.
Future<bool> openDocumentDownloadUrl(String? url) async {
  final raw = url?.trim() ?? '';
  if (raw.isEmpty) return false;
  final uri = Uri.tryParse(raw);
  if (uri == null) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
