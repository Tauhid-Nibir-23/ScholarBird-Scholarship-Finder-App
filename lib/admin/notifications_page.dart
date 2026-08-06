/// Admin notification composer + history.
///
/// Lets an admin author a push or in-app notification, choose an
/// audience (all, premium, country, or test user), toggle between
/// "send immediately" or "schedule", preview the rendered notification,
/// and review the last 50 broadcasts from Firestore.
///
/// State:
///   - `notifications` collection: { title, body, audience, scheduledFor,
///     sentAt, status, type }
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/scholarbird_theme.dart';
import '../services/notification_image_service.dart';
import 'admin_ui.dart';
import 'widgets/admin_badge.dart';
import 'widgets/admin_dialogs.dart';
import 'widgets/admin_empty_state.dart';
import 'widgets/admin_image_picker.dart';
import 'widgets/admin_section.dart';
import 'widgets/admin_search_bar.dart';

/// Pretty-prints a DateTime for the notification composer / history.
String adminFormatDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final mi = d.minute.toString().padLeft(2, '0');
  return '${dd}/${mm}/${d.year} $hh:$mi';
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

enum _Audience { everyone, premium, free, country, testUser }

enum _DeliveryMode { immediate, scheduled }

class _NotificationsPageState extends State<NotificationsPage> {
  final _firestore = FirebaseFirestore.instance;

  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _imageUrlCtrl = TextEditingController();
  final _linkUrlCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _testEmailCtrl = TextEditingController();
  DateTime? _scheduledFor;

  _Audience _audience = _Audience.everyone;
  _DeliveryMode _mode = _DeliveryMode.immediate;
  bool _busy = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _imageUrlCtrl.dispose();
    _linkUrlCtrl.dispose();
    _countryCtrl.dispose();
    _testEmailCtrl.dispose();
    super.dispose();
  }

  Future<String?> _uploadNotificationImage(ImageSource source) async {
    try {
      final url = source == ImageSource.gallery
          ? await NotificationImageService.instance.pickAndUploadFromGallery()
          : await NotificationImageService.instance.pickAndUploadFromCamera();
      if (url != null && mounted) {
        setState(() => _imageUrlCtrl.text = url);
      }
      return url;
    } catch (error) {
      if (mounted) AdminDialogs.error(context, error.toString());
      return null;
    }
  }

  Future<void> _pickSchedule() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      // ignore: use_build_context_synchronously
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null || !mounted) return;
    setState(() {
      _scheduledFor = DateTime(
        picked.year,
        picked.month,
        picked.day,
        time.hour,
        time.minute,
      );
    });
  }

  Map<String, dynamic>? _audiencePayload() {
    switch (_audience) {
      case _Audience.everyone:
        return {
          'type': 'all',
          'label': 'All users',
          'query': <String, Object?>{},
        };
      case _Audience.premium:
        return {
          'type': 'premium',
          'label': 'Premium users',
          'query': <String, Object?>{'premium': true},
        };
      case _Audience.free:
        return {
          'type': 'free',
          'label': 'Free users',
          'query': <String, Object?>{'premium': false},
        };
      case _Audience.country:
        if (_countryCtrl.text.trim().isEmpty) {
          AdminDialogs.error(context, 'Enter a country to target.');
          return null;
        }
        final c = _countryCtrl.text.trim();
        return {
          'type': 'country',
          'label': 'Country: $c',
          'query': <String, Object?>{'country': c},
        };
      case _Audience.testUser:
        if (_testEmailCtrl.text.trim().isEmpty) {
          AdminDialogs.error(context, 'Enter a test user email or uid.');
          return null;
        }
        return {
          'type': 'user',
          'label': 'User: ${_testEmailCtrl.text.trim()}',
          'query': <String, Object?>{'userId': _testEmailCtrl.text.trim()},
        };
    }
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      AdminDialogs.error(context, 'Title and body are required.');
      return;
    }
    final audience = _audiencePayload();
    if (audience == null) return;
    if (_mode == _DeliveryMode.scheduled && _scheduledFor == null) {
      AdminDialogs.error(
        context,
        'Pick a send date before scheduling.',
      );
      return;
    }

    final confirmed = await AdminDialogs.confirm(
      context: context,
      title: _mode == _DeliveryMode.immediate ? 'Send now?' : 'Schedule?',
      message:
          'Audience: ${audience['label']}\nType: ${_mode == _DeliveryMode.immediate ? 'Immediate' : 'Scheduled'}',
      confirmLabel: _mode == _DeliveryMode.immediate ? 'Send' : 'Schedule',
      cancelLabel: 'Cancel',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await _firestore.collection('notifications').add({
        'title': title,
        'body': body,
        'imageUrl': _imageUrlCtrl.text.trim(),
        'linkUrl': _linkUrlCtrl.text.trim(),
        'audience': audience,
        'mode': _mode.name,
        'scheduledFor': _mode == _DeliveryMode.scheduled
            ? Timestamp.fromDate(_scheduledFor!)
            : null,
        'status': _mode == _DeliveryMode.immediate ? 'sent' : 'scheduled',
        'sentAt': _mode == _DeliveryMode.immediate
            ? FieldValue.serverTimestamp()
            : null,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': 'admin',
      });
      if (!mounted) return;
      _titleCtrl.clear();
      _bodyCtrl.clear();
      _imageUrlCtrl.clear();
      _linkUrlCtrl.clear();
      _scheduledFor = null;
      AdminDialogs.success(
        context,
        _mode == _DeliveryMode.immediate
            ? 'Notification sent.'
            : 'Notification scheduled.',
      );
    } catch (e) {
      if (!mounted) return;
      AdminDialogs.error(context, 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _viewNotification(Map<String, dynamic> data) {
    final title = data['title']?.toString() ?? 'Notification';
    final body = data['body']?.toString() ?? '';
    final imageUrl = data['imageUrl']?.toString().trim() ?? '';
    final linkUrl = data['linkUrl']?.toString().trim() ?? '';
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (body.isNotEmpty) Text(body),
              if (imageUrl.isNotEmpty) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(imageUrl, fit: BoxFit.cover),
                ),
              ],
              if (linkUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectableText(linkUrl,
                    style: const TextStyle(color: AdminPalette.primary)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _editNotification(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final data = document.data() ?? const <String, dynamic>{};
    final titleCtrl = TextEditingController(text: data['title']?.toString());
    final bodyCtrl = TextEditingController(text: data['body']?.toString());
    final imageCtrl = TextEditingController(text: data['imageUrl']?.toString());
    final linkCtrl = TextEditingController(text: data['linkUrl']?.toString());
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit notification'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Title')),
                TextField(
                    controller: bodyCtrl,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: 'Body')),
                TextField(
                    controller: imageCtrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                        labelText: 'Image URL (optional)')),
                TextField(
                    controller: linkCtrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                        labelText: 'Open link (optional)')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Save changes')),
        ],
      ),
    );
    if (saved != true) return;
    final title = titleCtrl.text.trim();
    final body = bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      if (mounted) AdminDialogs.error(context, 'Title and body are required.');
      return;
    }
    try {
      await document.reference.update({
        'title': title,
        'body': body,
        'imageUrl': imageCtrl.text.trim(),
        'linkUrl': linkCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) AdminDialogs.success(context, 'Notification updated.');
    } catch (error) {
      if (mounted) AdminDialogs.error(context, 'Update failed: $error');
    } finally {
      titleCtrl.dispose();
      bodyCtrl.dispose();
      imageCtrl.dispose();
      linkCtrl.dispose();
    }
  }

  Future<void> _deleteNotification(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final confirmed = await AdminDialogs.confirm(
      context: context,
      title: 'Delete notification?',
      message: 'This removes it from all recipients and cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    try {
      await document.reference.delete();
      if (mounted) AdminDialogs.success(context, 'Notification deleted.');
    } catch (error) {
      if (mounted) AdminDialogs.error(context, 'Delete failed: $error');
    }
  }

  Future<void> _cancelScheduled(
      DocumentSnapshot<Map<String, dynamic>> d) async {
    try {
      await d.reference.update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      AdminDialogs.success(context, 'Scheduled notification cancelled.');
    } catch (e) {
      if (!mounted) return;
      AdminDialogs.error(context, 'Cancel failed: $e');
    }
  }

  // --------------------------- Build -------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? Theme.of(context).colorScheme.surface : Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminPageHeader(
              title: 'Notifications',
              subtitle: 'Compose broadcasts and review recent sends.',
            ),
            const SizedBox(height: 20),
            AdminSection(
              title: 'Compose',
              subtitle:
                  'Send instantly or schedule for later. Required: title & body.',
              icon: Icons.notifications_active_outlined,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth > 880;
                  final composer = _Composer(
                    titleCtrl: _titleCtrl,
                    bodyCtrl: _bodyCtrl,
                    imageUrlCtrl: _imageUrlCtrl,
                    linkUrlCtrl: _linkUrlCtrl,
                    audience: _audience,
                    onAudience: (v) => setState(() => _audience = v),
                    countryCtrl: _countryCtrl,
                    testEmailCtrl: _testEmailCtrl,
                    mode: _mode,
                    onMode: (v) => setState(() => _mode = v),
                    scheduledFor: _scheduledFor,
                    onPickSchedule: _pickSchedule,
                    busy: _busy,
                    onSend: _send,
                    onUploadImage: _uploadNotificationImage,
                  );
                  final preview = _PreviewCard(
                    title: _titleCtrl.text,
                    body: _bodyCtrl.text,
                    audienceLabel: _previewAudienceLabel(),
                  );
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: composer),
                        const SizedBox(width: 16),
                        Expanded(child: preview),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      composer,
                      const SizedBox(height: 16),
                      preview,
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            AdminSection(
              title: 'Recent broadcasts',
              subtitle: 'Last 50 notifications from Firestore.',
              icon: Icons.history,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _firestore
                    .collection('notifications')
                    .orderBy('createdAt', descending: true)
                    .limit(50)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: AdminLoadingSkeleton(itemCount: 4, itemHeight: 64),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Could not load: ${snapshot.error}',
                        style: const TextStyle(color: AdminPalette.body),
                      ),
                    );
                  }
                  final docs = snapshot.data?.docs ?? const [];
                  if (docs.isEmpty) {
                    return const AdminEmptyState(
                      icon: Icons.notifications_off_outlined,
                      title: 'No broadcasts yet',
                      message: 'Compose one above to send or schedule.',
                    );
                  }
                  return Column(
                    children: [
                      for (final d in docs)
                        _NotificationRow(
                          data: d.data(),
                          onView: () => _viewNotification(d.data()),
                          onEdit: () => _editNotification(d),
                          onDelete: () => _deleteNotification(d),
                          onCancel: d.data()['status'] == 'scheduled'
                              ? () => _cancelScheduled(d)
                              : null,
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _previewAudienceLabel() {
    switch (_audience) {
      case _Audience.everyone:
        return 'All users';
      case _Audience.premium:
        return 'Premium users';
      case _Audience.free:
        return 'Free users';
      case _Audience.country:
        return _countryCtrl.text.trim().isEmpty
            ? 'Country: ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â'
            : 'Country: ${_countryCtrl.text.trim()}';
      case _Audience.testUser:
        return _testEmailCtrl.text.trim().isEmpty
            ? 'Test user'
            : 'User: ${_testEmailCtrl.text.trim()}';
    }
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.titleCtrl,
    required this.bodyCtrl,
    required this.imageUrlCtrl,
    required this.linkUrlCtrl,
    required this.audience,
    required this.onAudience,
    required this.countryCtrl,
    required this.testEmailCtrl,
    required this.mode,
    required this.onMode,
    required this.scheduledFor,
    required this.onPickSchedule,
    required this.busy,
    required this.onSend,
    required this.onUploadImage,
  });

  final TextEditingController titleCtrl;
  final TextEditingController bodyCtrl;
  final TextEditingController imageUrlCtrl;
  final TextEditingController linkUrlCtrl;
  final _Audience audience;
  final ValueChanged<_Audience> onAudience;
  final TextEditingController countryCtrl;
  final TextEditingController testEmailCtrl;
  final _DeliveryMode mode;
  final ValueChanged<_DeliveryMode> onMode;
  final DateTime? scheduledFor;
  final VoidCallback onPickSchedule;
  final bool busy;
  final VoidCallback onSend;
  final Future<String?> Function(ImageSource source) onUploadImage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'TITLE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AdminPalette.body,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AdminSearchBar(
                controller: titleCtrl,
                hintText: 'e.g. New scholarships available now',
                onChanged: (_) {},
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'BODY',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AdminPalette.body,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: bodyCtrl,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            hintText:
                'Write what recipients see in the app or push notification...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'NOTIFICATION IMAGE (OPTIONAL)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AdminPalette.body,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: AdminImagePicker(
            photoUrl: imageUrlCtrl.text.trim().isEmpty
                ? null
                : imageUrlCtrl.text.trim(),
            title: 'Notification image',
            subtitle: 'Upload from gallery or camera. Recommended: 1600x900.',
            fallbackLabel: 'Notification image',
            shape: AdminImagePickerShape.rounded,
            aspectRatio: 16 / 9,
            onUploadFromGallery: () => onUploadImage(ImageSource.gallery),
            onUploadFromCamera: () => onUploadImage(ImageSource.camera),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: imageUrlCtrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Image URL (optional)',
            hintText: 'https://example.com/announcement.jpg',
            prefixIcon: Icon(Icons.image_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: linkUrlCtrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Open link (optional)',
            hintText: 'https://example.com/details',
            prefixIcon: Icon(Icons.link_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'AUDIENCE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AdminPalette.body,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final a in _Audience.values)
              ChoiceChip(
                label: Text(_audienceLabel(a)),
                selected: audience == a,
                onSelected: (_) => onAudience(a),
                avatar: Icon(_audienceIcon(a), size: 14),
              ),
          ],
        ),
        if (audience == _Audience.country) ...[
          const SizedBox(height: 10),
          AdminSearchBar(
            controller: countryCtrl,
            hintText: 'Target country (e.g. Nigeria)',
            onChanged: (_) {},
          ),
        ],
        if (audience == _Audience.testUser) ...[
          const SizedBox(height: 10),
          AdminSearchBar(
            controller: testEmailCtrl,
            hintText: 'Test user email or uid',
            onChanged: (_) {},
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'DELIVERY',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AdminPalette.body,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        SegmentedButton<_DeliveryMode>(
          segments: const [
            ButtonSegment(
              value: _DeliveryMode.immediate,
              icon: Icon(Icons.bolt_outlined),
              label: Text('Immediate'),
            ),
            ButtonSegment(
              value: _DeliveryMode.scheduled,
              icon: Icon(Icons.schedule_outlined),
              label: Text('Scheduled'),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (v) => onMode(v.first),
        ),
        if (mode == _DeliveryMode.scheduled) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  scheduledFor == null
                      ? 'No date picked'
                      : adminFormatDate(scheduledFor!),
                  style: const TextStyle(
                    color: AdminPalette.heading,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onPickSchedule,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  scheduledFor == null ? 'Pick date' : 'Change',
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : onSend,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      mode == _DeliveryMode.immediate
                          ? Icons.send
                          : Icons.schedule_send,
                    ),
              label: Text(
                mode == _DeliveryMode.immediate
                    ? 'Send notification'
                    : 'Schedule notification',
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _audienceLabel(_Audience a) {
    switch (a) {
      case _Audience.everyone:
        return 'Everyone';
      case _Audience.premium:
        return 'Premium';
      case _Audience.free:
        return 'Free';
      case _Audience.country:
        return 'By country';
      case _Audience.testUser:
        return 'Test user';
    }
  }

  static IconData _audienceIcon(_Audience a) {
    switch (a) {
      case _Audience.everyone:
        return Icons.groups_outlined;
      case _Audience.premium:
        return Icons.workspace_premium_outlined;
      case _Audience.free:
        return Icons.person_outline;
      case _Audience.country:
        return Icons.public;
      case _Audience.testUser:
        return Icons.bug_report_outlined;
    }
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.title,
    required this.body,
    required this.audienceLabel,
  });

  final String title;
  final String body;
  final String audienceLabel;

  @override
  Widget build(BuildContext context) {
    final hasBody = title.isNotEmpty || body.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminPalette.body.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PREVIEW',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AdminPalette.body,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AdminPalette.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AdminPalette.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: AdminPalette.primary,
                  radius: 18,
                  child: const Icon(
                    Icons.notifications,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? 'Notification title' : title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: hasBody
                              ? AdminPalette.heading
                              : AdminPalette.body,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        body.isEmpty ? 'Notification body preview.' : body,
                        style: TextStyle(
                          color: hasBody
                              ? AdminPalette.body
                              : AdminPalette.body.withValues(alpha: 0.6),
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.public, size: 16, color: AdminPalette.body),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Audience: $audienceLabel',
                  style: const TextStyle(
                    color: AdminPalette.body,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow(
      {required this.data,
      required this.onCancel,
      required this.onView,
      required this.onEdit,
      required this.onDelete});

  final Map<String, dynamic> data;
  final VoidCallback? onCancel;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final title = data['title']?.toString() ?? 'Untitled';
    final body = data['body']?.toString() ?? '';
    final status = data['status']?.toString() ?? 'pending';
    final audience = data['audience'] is Map
        ? data['audience']['label']?.toString() ??
            'ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â'
        : 'ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â';
    final dynamic ts = data['createdAt'];
    DateTime? created;
    if (ts is Timestamp) created = ts.toDate();
    final dynamic sched = data['scheduledFor'];
    DateTime? scheduled;
    if (sched is Timestamp) scheduled = sched.toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AdminPalette.body.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(10),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AdminPalette.heading,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _statusBadge(status),
              if (onCancel != null)
                IconButton(
                  tooltip: 'Cancel scheduled send',
                  icon: const Icon(
                    Icons.cancel_outlined,
                    color: Color(0xFFDC2626),
                  ),
                  onPressed: onCancel,
                ),
            ],
          ),
          if (body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                body,
                style: const TextStyle(color: AdminPalette.body, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              AdminBadge(
                label: 'Audience: $audience',
                color: const Color(0xFF0F766E),
                icon: Icons.groups_outlined,
              ),
              if (created != null)
                AdminBadge(
                  label: 'Sent ${adminFormatDate(created)}',
                  color: const Color(0xFF2563EB),
                  icon: Icons.send_outlined,
                ),
              if (scheduled != null)
                AdminBadge(
                  label: 'For ${adminFormatDate(scheduled)}',
                  color: const Color(0xFFD97706),
                  icon: Icons.schedule_outlined,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 2,
            children: [
              TextButton.icon(
                onPressed: onView,
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('View'),
              ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline,
                    size: 16, color: Color(0xFFDC2626)),
                label: const Text('Delete',
                    style: TextStyle(color: Color(0xFFDC2626))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _statusBadge(String status) {
    switch (status) {
      case 'sent':
        return const AdminBadge(
          label: 'Sent',
          color: Color(0xFF16A34A),
          icon: Icons.check_circle_outline,
        );
      case 'scheduled':
        return const AdminBadge(
          label: 'Scheduled',
          color: Color(0xFFD97706),
          icon: Icons.schedule_outlined,
        );
      case 'cancelled':
        return const AdminBadge(
          label: 'Cancelled',
          color: Color(0xFF6B7A95),
          icon: Icons.cancel_outlined,
        );
      case 'failed':
        return const AdminBadge(
          label: 'Failed',
          color: Color(0xFFDC2626),
          icon: Icons.error_outline,
        );
      case 'pending':
      default:
        return const AdminBadge(
          label: 'Pending',
          color: Color(0xFF6B7A95),
          icon: Icons.schedule_outlined,
        );
    }
  }
}
