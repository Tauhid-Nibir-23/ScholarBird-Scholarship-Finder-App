/// Mentor Free Call — request a 5-min intro call.
///
/// Free calls live in the same `mentor_bookings` collection with
/// `type: 'free_call'` and a status from `MentorFreeCallStatus`. After
/// submission, the screen listens to that document and surfaces the
/// current status (Requested → Accepted → Scheduled → Completed, etc.).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/mentor_booking.dart';
import '../../models/mentor_profile.dart';
import '../../theme/scholarbird_theme.dart';

class MentorFreeCallScreen extends StatefulWidget {
  const MentorFreeCallScreen({required this.mentor, super.key});

  final MentorProfile mentor;

  @override
  State<MentorFreeCallScreen> createState() => _MentorFreeCallScreenState();
}

class _MentorFreeCallScreenState extends State<MentorFreeCallScreen> {
  final _formKey = GlobalKey<FormState>();
  final _topicController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime? _preferredTime;
  bool _submitting = false;
  String? _activeDocId;

  static const String _collectionName = 'mentor_bookings';

  @override
  void dispose() {
    _topicController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: ScholarBirdColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: ScholarBirdColors.ink,
            ),
          ),
          child: child!,
        );
      },
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
    );
    if (time == null) return;
    setState(() {
      _preferredTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to request a free call.')),
      );
      return;
    }
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final freeCall = MentorFreeCall(
        id: '',
        mentorId: widget.mentor.id,
        mentorName: widget.mentor.name,
        userId: user.uid,
        userName: user.displayName ?? user.email ?? 'Student',
        topic:
            '${_topicController.text.trim()} | ${_notesController.text.trim()}',
        scheduledFor: _preferredTime,
        status: MentorFreeCallStatus.requested,
        createdAt: DateTime.now(),
      );
      final doc = await FirebaseFirestore.instance
          .collection(_collectionName)
          .add(freeCall.toMap());
      if (mounted) {
        setState(() {
          _submitting = false;
          _activeDocId = doc.id;
        });
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Free call request sent.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not send request: $e')),
      );
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_activeDocId != null) {
      return Scaffold(
        backgroundColor: ScholarBirdColors.background,
        appBar: AppBar(
          backgroundColor: ScholarBirdColors.primary,
          foregroundColor: Colors.white,
          title: const Text(
            'Free Call',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: _StatusTracker(docId: _activeDocId!),
      );
    }

    final formatter = DateFormat('EEE, MMM d · h:mm a');

    return Scaffold(
      backgroundColor: ScholarBirdColors.background,
      appBar: AppBar(
        backgroundColor: ScholarBirdColors.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'Request 5-min Call',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
          children: [
            Container(
              padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
              decoration: BoxDecoration(
                color: ScholarBirdColors.primary.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.support_agent_rounded,
                    color: ScholarBirdColors.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Talk to ${widget.mentor.name}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: ScholarBirdColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Free 5-minute intro call to see if the mentor '
                          'is the right fit.',
                          style: TextStyle(
                            color: ScholarBirdColors.body,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: ScholarBirdSpacing.medium),
            TextFormField(
              controller: _topicController,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'What do you want to discuss?',
                hintText: 'e.g. Scholarship shortlisting for UK',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please describe the topic.';
                }
                if (value.trim().length < 4) {
                  return 'Add a few more words so the mentor can prepare.';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'Anything the mentor should know in advance.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickDateTime,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: ScholarBirdColors.border),
                  borderRadius: BorderRadius.circular(12),
                  color: ScholarBirdColors.surface,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.event_available_rounded,
                      color: ScholarBirdColors.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Preferred time',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: ScholarBirdColors.ink,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _preferredTime == null
                                ? 'Pick a date and time'
                                : formatter.format(_preferredTime!),
                            style: const TextStyle(
                              color: ScholarBirdColors.body,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: ScholarBirdColors.body,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: ScholarBirdColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(
                _submitting ? 'Sending...' : 'Request free call',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusTracker extends StatelessWidget {
  const _StatusTracker({required this.docId});

  final String docId;

  String _label(StatusValues v) {
    switch (v) {
      case StatusValues.requested:
        return 'Requested';
      case StatusValues.accepted:
        return 'Accepted';
      case StatusValues.scheduled:
        return 'Scheduled';
      case StatusValues.completed:
        return 'Completed';
      case StatusValues.declined:
        return 'Declined';
      case StatusValues.expired:
        return 'Expired';
    }
  }

  IconData _icon(StatusValues v) {
    switch (v) {
      case StatusValues.requested:
        return Icons.schedule_rounded;
      case StatusValues.accepted:
        return Icons.thumb_up_alt_outlined;
      case StatusValues.scheduled:
        return Icons.event_available_rounded;
      case StatusValues.completed:
        return Icons.check_circle_outline_rounded;
      case StatusValues.declined:
        return Icons.cancel_outlined;
      case StatusValues.expired:
        return Icons.history_toggle_off_rounded;
    }
  }

  Color _color(StatusValues v) {
    switch (v) {
      case StatusValues.declined:
      case StatusValues.expired:
        return Colors.redAccent;
      case StatusValues.completed:
        return Colors.green;
      case StatusValues.scheduled:
      case StatusValues.accepted:
        return ScholarBirdColors.primary;
      case StatusValues.requested:
        return ScholarBirdColors.body;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('mentor_bookings')
          .doc(docId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: ScholarBirdColors.primary),
          );
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Request not found.'),
          );
        }
        final data = snapshot.data!.data() as Map<String, dynamic>;
        final status = _parseStatus(data['freeCallStatus'] as String? ?? 'requested');
        return ListView(
          padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
          children: [
            Container(
              padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
              decoration: BoxDecoration(
                color: ScholarBirdColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ScholarBirdColors.border),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: _color(status).withValues(alpha: .15),
                    child: Icon(_icon(status), color: _color(status)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _label(status),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: ScholarBirdColors.ink,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _description(status),
                          style: const TextStyle(
                            color: ScholarBirdColors.body,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (data['topic'] != null)
              _DetailRow(label: 'Topic', value: data['topic'].toString()),
            if (data['preferredTime'] != null)
              _DetailRow(
                label: 'Preferred time',
                value: DateFormat('EEE, MMM d · h:mm a').format(
                  (data['preferredTime'] as Timestamp).toDate(),
                ),
              ),
            if (data['notes'] != null &&
                (data['notes'] as String).trim().isNotEmpty)
              _DetailRow(label: 'Notes', value: data['notes'].toString()),
          ],
        );
      },
    );
  }

  String _description(StatusValues status) {
    switch (status) {
      case StatusValues.requested:
        return 'Your request has been sent. The mentor will respond '
            'within their stated response time.';
      case StatusValues.accepted:
        return 'The mentor has accepted. A scheduled time will be '
            'confirmed shortly.';
      case StatusValues.scheduled:
        return 'Your call is scheduled. You will get a reminder before '
            'the call.';
      case StatusValues.completed:
        return 'Call completed. You can leave a review from the mentor\'s '
            'profile.';
      case StatusValues.declined:
        return 'The mentor declined this request. You can request another '
            'mentor.';
      case StatusValues.expired:
        return 'This request has expired. Please send a new request.';
    }
  }
}

enum StatusValues {
  requested,
  accepted,
  scheduled,
  completed,
  declined,
  expired,
}

StatusValues _parseStatus(String raw) {
  switch (raw) {
    case 'accepted':
      return StatusValues.accepted;
    case 'scheduled':
      return StatusValues.scheduled;
    case 'completed':
      return StatusValues.completed;
    case 'declined':
      return StatusValues.declined;
    case 'expired':
      return StatusValues.expired;
    default:
      return StatusValues.requested;
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
        decoration: BoxDecoration(
          color: ScholarBirdColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ScholarBirdColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: ScholarBirdColors.body,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: ScholarBirdColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
