/// Scholarship detail screen with actions, metadata, and related controls.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../premium/premium_upgrade_screen.dart';
import '../../widgets/scholarship_ui.dart';
import '../../widgets/saved_scholarship_controls.dart';
import '../../services/application_service.dart';

/// Shows the full scholarship record and links to external actions.
class ScholarshipDetailsScreen extends StatelessWidget {
  const ScholarshipDetailsScreen({
    required this.data,
    super.key,
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
    final university = (data['university'] ?? '').toString();
    final source = (data['source'] ?? '').toString();
    final degree = (data['degree'] ?? '').toString();
    final field = (data['field'] ?? '').toString();
    final deadline = (data['deadline'] ?? '').toString();
    final description = (data['description'] ?? '').toString();
    final minCgpa = (data['minCgpa'] ?? '').toString();
    final cgpaScale = (data['cgpaScale'] ?? '').toString();
    final ieltsRequired = (data['ieltsRequired'] ?? '').toString();
    final fullyFunded = _asBool(data['fullyFunded']);
    final researchRequired = _asBool(data['researchRequired']);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Scholarship Details'),
        actions: readOnly
            ? null
            : [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SavedScholarshipIconButton(scholarship: data),
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
                child: Stack(children: [
                  ScholarshipImage(
                      url: imageUrl,
                      height: 240,
                      heroTag: 'scholarship-image-${data['id'] ?? ''}'),
                  Positioned.fill(
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: .38)
                      ])))),
                  if (source.isNotEmpty)
                    Positioned(
                        left: 14,
                        bottom: 14,
                        child: _buildBadge(source.toUpperCase(),
                            Colors.white.withValues(alpha: .92), sbBlue)),
                ])),
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
            LayoutBuilder(
                builder: (context, constraints) =>
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      SizedBox(
                          width: constraints.maxWidth > 640
                              ? (constraints.maxWidth - 24) / 3
                              : (constraints.maxWidth - 12) / 2,
                          child: _buildInfoCard(
                              'Degree', degree.isEmpty ? 'N/A' : degree)),
                      SizedBox(
                          width: constraints.maxWidth > 640
                              ? (constraints.maxWidth - 24) / 3
                              : (constraints.maxWidth - 12) / 2,
                          child: _buildInfoCard(
                              'Field', field.isEmpty ? 'N/A' : field)),
                      SizedBox(
                          width: constraints.maxWidth > 640
                              ? (constraints.maxWidth - 24) / 3
                              : (constraints.maxWidth - 12) / 2,
                          child: _buildInfoCard(
                              'Deadline', deadline.isEmpty ? 'N/A' : deadline)),
                    ])),
            if (university.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildSectionTitle('University'),
              const SizedBox(height: 8),
              _buildInfoCard('Host institution', university)
            ],
            if (fullyFunded ||
                (data['amount'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildSectionTitle('Funding'),
              const SizedBox(height: 8),
              _buildInfoCard(
                  'Award value',
                  fullyFunded
                      ? 'Fully funded'
                      : (data['amount'] ?? '').toString())
            ],
            const SizedBox(height: 24),
            _buildSectionTitle('Eligibility Criteria'),
            const SizedBox(height: 12),
            _buildEligibilityItem(
              'Minimum CGPA: ${_formatCgpa(minCgpa, cgpaScale)}',
            ),
            _buildEligibilityItem(
                'IELTS Required: ${_displayValue(ieltsRequired)}'),
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
            if (field.isNotEmpty) ...[
              const SizedBox(height: 28),
              _buildSectionTitle('Related scholarships'),
              const SizedBox(height: 12),
              SizedBox(
                  height: 126,
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('scholarships')
                        .where('field', isEqualTo: field)
                        .limit(4)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const SizedBox.shrink();
                      final docs = snapshot.data!.docs
                          .where((doc) => doc.id != data['id'])
                          .toList();
                      if (docs.isEmpty) {
                        return const Text(
                            'More opportunities in this field will appear here.',
                            style: TextStyle(color: Color(0xFF667085)));
                      }
                      return ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, index) {
                          final item =
                              docs[index].data()! as Map<String, dynamic>;
                          return SizedBox(
                            width: 210,
                            child: Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            ScholarshipDetailsScreen(data: {
                                              ...item,
                                              'id': docs[index].id
                                            }))),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            (item['title'] ?? 'Scholarship')
                                                .toString(),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: sbInk)),
                                        const Spacer(),
                                        Text((item['country'] ?? '').toString(),
                                            style: const TextStyle(
                                                color: sbBlue,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700)),
                                      ]),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  )),
            ],
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
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!readOnly)
                FutureBuilder<ApplicationAccess>(
                  future: _applicationAccess(),
                  builder: (context, snapshot) {
                    final isLoading =
                        snapshot.connectionState == ConnectionState.waiting;
                    final access = snapshot.data ?? const ApplicationAccess();

                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (isLoading || access.alreadyApplied)
                            ? null
                            : () {
                                if (!access.isLoggedIn) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Please login first')),
                                  );
                                } else if (!access.isPremium) {
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) =>
                                        const PremiumUpgradeScreen(),
                                  ));
                                } else if (access.missing.isNotEmpty) {
                                  _showMissingRequirements(
                                      context, access.missing);
                                } else {
                                  _applyScholarship(context);
                                }
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
                          access.alreadyApplied
                              ? 'Applied'
                              : access.canApply
                                  ? 'Apply Now'
                                  : 'Unlock Scholarship Applications',
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

  Widget _buildBadge(String text, Color background, Color foreground) =>
      Container(
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
              color: Colors.black.withValues(alpha: 0.05),
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

  Future<ApplicationAccess> _applicationAccess() =>
      ApplicationService.instance.checkAccess(data['id']?.toString() ?? '');

  Future<void> _applyScholarship(BuildContext context) async {
    final continueToWebsite = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("You're leaving ScholarBird."),
        content: const Text(
            'You will be redirected to the official scholarship website.\n\nHave you started your application?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Yes, Continue')),
        ],
      ),
    );
    if (continueToWebsite != true || !context.mounted) return;
    try {
      final officialUrl = await ApplicationService.instance.submit(data);
      final url = Uri.tryParse(officialUrl);
      if (url == null ||
          officialUrl.isEmpty ||
          !await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open the official website.');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is StateError
              ? e.message.toString()
              : 'Application tracking could not be started.'),
        ));
      }
    }
  }

  void _showMissingRequirements(BuildContext context, List<String> missing) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete your profile'),
        content: Text('You still need: ${missing.join(', ')}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK'))
        ],
      ),
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
