import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ScholarshipDetailsScreen extends StatelessWidget {

  const ScholarshipDetailsScreen({
    super.key,
    required this.data,
    this.readOnly = false,
  });
  final Map<String, dynamic> data;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? '').toString();
    final imageUrl = (data['image'] ?? '').toString();
    final link = (data['link'] ?? '').toString();
    final country = (data['country'] ?? '').toString();
    final degree = (data['degree'] ?? '').toString();
    final field = (data['field'] ?? '').toString();
    final deadline = (data['deadline'] ?? '').toString();
    final description = (data['description'] ?? '').toString();
    final minCgpa = (data['minCgpa'] ?? '').toString();
    final cgpaScale = (data['cgpaScale'] ?? '').toString();
    final ieltsRequired = (data['ieltsRequired'] ?? '').toString();
    final maxBacklogs = (data['maxBacklogs'] ?? '').toString();
    final fullyFunded = _asBool(data['fullyFunded']);
    final englishMediumAccepted = _asBool(data['englishMediumAccepted']);
    final researchRequired = _asBool(data['researchRequired']);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Scholarship Details'),
        actions: readOnly
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.bookmark_border),
                  onPressed: () {
                    _saveScholarship(context);
                  },
                ),
              ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _imagePlaceholder(),
                    )
                  : _imagePlaceholder(),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (fullyFunded)
                  _buildBadge(
                    'FULLY FUNDED',
                    const Color(0xFFE8F5E9),
                    const Color(0xFF2E7D32),
                  ),
                if (country.isNotEmpty)
                  _buildBadge(
                    country,
                    const Color(0xFFE3F2FD),
                    const Color(0xFF1565C0),
                  ),
                if (degree.isNotEmpty)
                  _buildBadge(
                    degree,
                    const Color(0xFFF3E5F5),
                    const Color(0xFF6A1B9A),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              title.isEmpty ? 'Untitled scholarship' : title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildInfoCard('Degree', degree.isEmpty ? 'N/A' : degree),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoCard('Field', field.isEmpty ? 'N/A' : field),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoCard(
                    'Deadline',
                    deadline.isEmpty ? 'N/A' : deadline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Eligibility Criteria'),
            const SizedBox(height: 12),
            _buildEligibilityItem(
              'Minimum CGPA: ${_formatCgpa(minCgpa, cgpaScale)}',
            ),
            _buildEligibilityItem('IELTS Required: ${_displayValue(ieltsRequired)}'),
            _buildEligibilityItem('Maximum Backlogs: ${_displayValue(maxBacklogs)}'),
            _buildEligibilityItem(
              englishMediumAccepted
                  ? 'English Medium Accepted'
                  : 'English Medium Not Accepted',
            ),
            _buildEligibilityItem(
              researchRequired ? 'Research Required' : 'Research Not Required',
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('About the Scholarship'),
            const SizedBox(height: 8),
            Text(
              description.isEmpty
                  ? 'No description available.'
                  : _cleanDescription(description),
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: Color(0xFF2F2F3A),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!readOnly)
                FutureBuilder<bool>(
                  future: _hasApplied(),
                  builder: (context, snapshot) {
                    final isLoading =
                        snapshot.connectionState == ConnectionState.waiting;
                    final alreadyApplied = snapshot.data == true;

                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (alreadyApplied || isLoading)
                            ? null
                            : () {
                                _applyScholarship(context);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5B7AE8),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          alreadyApplied ? 'Applied' : 'Apply Now',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              if (!readOnly) const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    if (link.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No link available')),
                      );
                      return;
                    }

                    final url = Uri.parse(link);
                    final launched = await launchUrl(url);
                    if (!launched && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not open link')),
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFF5B7AE8)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Official Website',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5B7AE8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagePlaceholder() => Container(
        height: 220,
        width: double.infinity,
        alignment: Alignment.center,
        color: const Color(0xFFE5E7EB),
        child: const Text('No image available'),
      );

  Widget _buildBadge(String text, Color background, Color foreground) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
        ),
      );

  Widget _buildInfoCard(String label, String value) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8A94A6),
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A2E),
              ),
            ),
          ],
        ),
      );

  Widget _buildSectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A2E),
        ),
      );

  Widget _buildEligibilityItem(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.check_circle,
              size: 18,
              color: Color(0xFF5B7AE8),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Color(0xFF2F2F3A),
                ),
              ),
            ),
          ],
        ),
      );

  String _formatCgpa(String value, String scale) {
    final cleanedValue = value.trim();
    final cleanedScale = scale.trim();
    if (cleanedValue.isEmpty && cleanedScale.isEmpty) {
      return 'N/A';
    }
    if (cleanedScale.isEmpty) return cleanedValue;
    if (cleanedValue.isEmpty) return 'N/A/$cleanedScale';
    return '$cleanedValue/$cleanedScale';
  }

  String _displayValue(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'N/A' : trimmed;
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final cleaned = value.trim().toLowerCase();
      return cleaned == 'true' || cleaned == 'yes' || cleaned == '1';
    }
    return false;
  }

  Future<bool> _hasApplied() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('applications')
        .doc(data['id'])
        .get();

    return doc.exists;
  }

  Future<void> _applyScholarship(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login first')),
      );
      return;
    }

    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('applications')
          .doc(data['id']);

      final existing = await docRef.get();

      if (existing.exists) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Already applied to this scholarship'),
            ),
          );
        }
        return;
      }

      await docRef.set({
        'scholarshipId': data['id'],
        'title': data['title'],
        'country': data['country'],
        'degree': data['degree'],
        'status': 'Applied',
        'appliedAt': Timestamp.now(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Applied Successfully')),
        );
      }
    } catch (e) {
      print('Firestore Error: $e');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Application failed')),
        );
      }
    }
  }

  Future<void> _saveScholarship(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login first')),
      );
      return;
    }

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('savedScholarships')
        .doc(data['id']);

    final existing = await docRef.get();

    if (existing.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already Saved')),
      );
      return;
    }

    await docRef.set({
      'title': data['title'],
      'country': data['country'],
      'degree': data['degree'],
      'image': data['image'],
      'savedAt': Timestamp.now(),
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scholarship Saved')),
    );
  }

  String _cleanDescription(String text) {
    // Remove URLs and HTML tags from description
    return text
        .replaceAll(RegExp(r'https?:\/\/\S+'), '')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\n\n+'), '\n')
        .trim();
  }
}