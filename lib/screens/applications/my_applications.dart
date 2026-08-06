import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../profile/profile_widgets.dart';
import 'application_details.dart';

class MyApplicationsScreen extends StatelessWidget {
  const MyApplicationsScreen({super.key, this.onMenuTap});
  final VoidCallback? onMenuTap;

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: sbBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 72,
        shape: const Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
        leading: IconButton(
          tooltip: 'Open navigation menu',
          onPressed: onMenuTap,
          icon: const Icon(Icons.menu_rounded),
        ),
        centerTitle: true,
        title: const Text(
          'My Applications',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: sbText,
          ),
        ),
      ),
      body: currentUser == null
          ? const Center(
              child: Text(
                'Please log in to view your applications.',
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
                  .collection('applications')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: sbPrimary),
                  );
                }

                if (snapshot.hasError) {
                  return const ProfileEmptyState(
                    title: 'Unable to load applications',
                    message: 'Please check your connection and try again.',
                    icon: Icons.error_outline,
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const ProfileEmptyState(
                    title: 'No applications yet',
                    message:
                        'Start applying to scholarships and track them here.',
                    icon: Icons.assignment_outlined,
                  );
                }

                return ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final scholarshipId =
                        (data['scholarshipId'] ?? docs[index].id).toString();
                    final title = (data['scholarshipTitle'] ??
                            data['title'] ??
                            'Scholarship')
                        .toString();
                    final country = (data['country'] ?? '').toString();
                    final degree = (data['degree'] ?? '').toString();
                    final rawStatus = (data['status'] ?? 'Pending').toString();
                    final status = rawStatus.toLowerCase() == 'applied' &&
                            data['adminAppliedAt'] != null
                        ? 'In Process'
                        : rawStatus.toLowerCase() == 'applied'
                            ? 'Pending'
                            : rawStatus;
                    final appliedDate =
                        _formatDate(data['submittedAt'] ?? data['appliedAt']);
                    final imageUrl = (data['image'] ?? '').toString();

                    return _buildApplicationCard(
                      scholarshipId: scholarshipId,
                      title: title,
                      country: country,
                      degree: degree,
                      imageUrl: imageUrl,
                      status: status,
                      appliedDate: appliedDate,
                      onViewDetails: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ApplicationDetailsScreen(application: data),
                            ));
                      },
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildApplicationCard({
    required String scholarshipId,
    required String title,
    required String country,
    required String degree,
    required String imageUrl,
    required String status,
    required String appliedDate,
    required VoidCallback onViewDetails,
  }) {
    final badgeColor = _statusColor(status);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sbBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
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
              child: _buildImage(imageUrl, scholarshipId),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 12, top: 12, bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: sbText,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.public,
                          size: 14, color: sbSecondaryText),
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
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.event_outlined,
                        size: 14,
                        color: sbSecondaryText,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        appliedDate.isEmpty
                            ? 'Applied date not available'
                            : appliedDate,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: sbSecondaryText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onViewDetails,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        backgroundColor: sbPrimary.withValues(alpha: 0.08),
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
  }

  Widget _buildImage(String imageUrl, String scholarshipId) {
    const size = 56.0;
    if (imageUrl.isNotEmpty) {
      return Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildImagePlaceholder(size),
      );
    }

    if (scholarshipId.isEmpty) {
      return _buildImagePlaceholder(size);
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('scholarships')
          .doc(scholarshipId)
          .get(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final fetchedUrl = (data?['image'] ?? '').toString();
        if (fetchedUrl.isNotEmpty) {
          return Image.network(
            fetchedUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildImagePlaceholder(size),
          );
        }
        return _buildImagePlaceholder(size);
      },
    );
  }

  Widget _buildImagePlaceholder(double size) => Container(
        width: size,
        height: size,
        color: sbPrimary.withValues(alpha: 0.1),
        child: const Icon(Icons.school_outlined, color: sbPrimary, size: 30),
      );

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'accepted':
        return sbPrimaryDark;
      case 'rejected':
        return Colors.red.shade600;
      case 'under review':
      case 'in process':
        return Colors.orange.shade700;
      case 'pending':
        return sbPrimary;
      default:
        return sbMutedText;
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
