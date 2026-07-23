import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profile_widgets.dart';
import '../scholarship/scholarship_details.dart';

class SavedScholarshipsScreen extends StatelessWidget {
  const SavedScholarshipsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: sbBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Saved Scholarships',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: sbText,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: sbText),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: currentUser == null
          ? const Center(
              child: Text(
                'Please log in to view saved scholarships.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: sbSecondaryText,
                ),
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUser.uid)
                  .collection('savedScholarships')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: sbPrimary),
                  );
                }

                if (snapshot.hasError) {
                  return const ProfileEmptyState(
                    title: 'Unable to load saved scholarships',
                    message: 'Please check your connection and try again.',
                    icon: Icons.error_outline,
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const ProfileEmptyState(
                    title: 'No saved scholarships yet',
                    message: 'No saved scholarships yet',
                    icon: Icons.bookmark_border,
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final title = (data['title'] ?? 'Scholarship').toString();
                    final country = (data['country'] ?? '').toString();
                    final degree = (data['degree'] ?? '').toString();
                    final savedDate = _formatDate(data['savedAt']);
                    final imageUrl = (data['imageUrl'] ?? data['image'] ?? '').toString();

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: sbBorder),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _buildImage(imageUrl),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12, top: 12, bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: sbText,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.public, size: 14, color: sbSecondaryText),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          country.isEmpty ? 'Global' : country,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w400,
                                            color: sbSecondaryText,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.school_outlined,
                                        size: 14,
                                        color: sbSecondaryText,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          degree.isEmpty ? 'Degree not available' : degree,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w400,
                                            color: sbSecondaryText,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (savedDate.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.bookmark_added_outlined,
                                          size: 14,
                                          color: sbSecondaryText,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          savedDate,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w400,
                                            color: sbSecondaryText,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: () {
                                          _openScholarshipDetails(
                                            context,
                                            docs[index].id,
                                            data,
                                          );
                                        },
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          backgroundColor: sbPrimary.withOpacity(0.08),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        child: const Text(
                                          'View Details',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: sbPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildImage(String imageUrl) {
    const size = 56.0;
    if (imageUrl.isEmpty) {
      return Container(
        width: size,
        height: size,
        color: sbPrimary.withOpacity(0.1),
        child: const Icon(Icons.school_outlined, color: sbPrimary, size: 30),
      );
    }

    return Image.network(
      imageUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: size,
        height: size,
        color: sbPrimary.withOpacity(0.1),
        child: const Icon(Icons.school_outlined, color: sbPrimary, size: 30),
      ),
    );
  }

  Future<void> _openScholarshipDetails(
    BuildContext context,
    String scholarshipId,
    Map<String, dynamic> fallbackData,
  ) async {
    if (scholarshipId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing scholarship id')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: sbPrimary),
      ),
    );

    try {
      final doc = await FirebaseFirestore.instance
          .collection('scholarships')
          .doc(scholarshipId)
          .get();

      if (!context.mounted) return;
      Navigator.of(context).pop();

      if (!doc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scholarship not found')),
        );
        return;
      }

      final data = doc.data() ?? {};
      data['id'] = scholarshipId;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScholarshipDetailsScreen(
            data: {
              ...fallbackData,
              ...data,
            },
            readOnly: true,
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load scholarship')),
      );
    }
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    DateTime? date;
    if (raw is Timestamp) {
      date = raw.toDate();
    } else if (raw is DateTime) {
      date = raw;
    } else if (raw is String) {
      date = DateTime.tryParse(raw);
    }

    if (date == null) return raw.toString();

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
