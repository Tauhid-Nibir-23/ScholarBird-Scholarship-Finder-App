import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/application_service.dart';
import 'package:flutter/material.dart';

import '../profile/profile_widgets.dart';

class ApplicationDetailsScreen extends StatefulWidget {
  const ApplicationDetailsScreen({required this.application, super.key});
  final Map<String, dynamic> application;
  @override
  State<ApplicationDetailsScreen> createState() =>
      _ApplicationDetailsScreenState();
}

class _ApplicationDetailsScreenState extends State<ApplicationDetailsScreen> {
  static const _labels = {
    'passport': 'Passport',
    'cv': 'CV',
    'sop': 'SOP',
    'recommendationLetter': 'Recommendation Letter',
    'transcript': 'Transcript',
    'ielts': 'IELTS',
    'researchProposal': 'Research Proposal'
  };
  late Map<String, dynamic> _data;
  @override
  void initState() {
    super.initState();
    _data = Map.of(widget.application);
  }

  Future<void> _update(String action, [Map<String, bool>? checklist]) async {
    try {
      await ApplicationService.instance.updateTracking(
        (_data['applicationId'] ?? '').toString(),
        submitted: action == 'submitted',
        checklist: checklist,
      );
      if (action == 'submitted') _data['status'] = 'SUBMITTED';
      if (checklist != null) _data['checklist'] = checklist;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update application.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final checklist = Map<String, bool>.from(_labels.map(
        (key, _) => MapEntry(key, (_data['checklist'] as Map?)?[key] == true)));
    final completed = checklist.values.where((value) => value).length;
    final status = (_data['status'] ?? 'IN_PROGRESS').toString();
    return Scaffold(
        backgroundColor: sbBackground,
        appBar: AppBar(
            backgroundColor: Colors.white,
            title: const Text('Application Details')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Text(
              (_data['scholarshipTitle'] ?? _data['title'] ?? 'Scholarship')
                  .toString(),
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: sbText)),
          const SizedBox(height: 16),
          _card('Status', status),
          _card(
              'Submitted',
              _formatDate(_data['submittedAt']).isEmpty
                  ? 'Not submitted yet'
                  : _formatDate(_data['submittedAt'])),
          const Text('Timeline',
              style: TextStyle(fontWeight: FontWeight.w700, color: sbText)),
          const SizedBox(height: 8),
          ...[
            'Started',
            'Documents Ready',
            'Application Submitted',
            'Under Review',
            'Interview',
            'Result Published',
            'Accepted / Rejected'
          ].asMap().entries.map((entry) => ListTile(
              leading: Icon(
                  entry.key <= (_data['currentStep'] ?? 0)
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: sbPrimary),
              title: Text(entry.value))),
          if (status == 'IN_PROGRESS')
            ElevatedButton(
                onPressed: () => _update('submitted'),
                child: const Text('Mark as Submitted')),
          const SizedBox(height: 20),
          Text('Checklist ? $completed / ${_labels.length} Completed',
              style:
                  const TextStyle(fontWeight: FontWeight.w700, color: sbText)),
          ..._labels.entries.map((entry) => CheckboxListTile(
              value: checklist[entry.key],
              title: Text(entry.value),
              onChanged: (value) {
                checklist[entry.key] = value ?? false;
                _update('checklist', checklist);
              })),
          _card(
              'Admin Notes',
              (_data['adminNotes'] ?? _data['notes'] ?? '').toString().isEmpty
                  ? 'No notes yet.'
                  : (_data['adminNotes'] ?? _data['notes']).toString()),
        ]));
  }

  Widget _card(String label, String value) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sbBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: sbSecondaryText)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: sbText))
      ]));
  String _formatDate(Object? value) {
    final date = value is Timestamp
        ? value.toDate()
        : value is DateTime
            ? value
            : DateTime.tryParse('${value ?? ''}');
    return date == null ? '' : '${date.day}/${date.month}/${date.year}';
  }
}
