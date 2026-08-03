import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'edit_profile.dart';
import 'academic_profile_screen.dart';
import 'scholarship_preferences_screen.dart';
import 'saved_scholarships_screen.dart';
import 'notifications_screen.dart';
import 'profile_widgets.dart';
import '../premium/manage_subscription_screen.dart';
import '../premium/premium_upgrade_screen.dart';
import '../../models/subscription_model.dart';
import '../../services/pdf_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.onMenuTap});
  final VoidCallback? onMenuTap;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final user = FirebaseAuth.instance.currentUser;

  Future<void> _logout() async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: sbBackground,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          toolbarHeight: 72,
          shape: const Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
          leading: IconButton(
            tooltip: 'Open navigation menu',
            onPressed: widget.onMenuTap,
            icon: const Icon(Icons.menu_rounded),
          ),
          centerTitle: true,
          title: const Text(
            'Profile',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: sbText,
            ),
          ),
        ),
        body: user == null
            ? const Center(
                child: Text(
                  'Please log in to view your profile.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: sbSecondaryText,
                  ),
                ),
              )
            : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user!.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: sbPrimary),
                    );
                  }

                  if (snapshot.hasError) {
                    return const ProfileEmptyState(
                      title: 'Unable to load profile',
                      message: 'Please check your connection and try again.',
                      icon: Icons.error_outline,
                    );
                  }

                  final data = snapshot.data?.data() ?? {};
                  final name =
                      (data['name'] as String?)?.trim().isNotEmpty == true
                          ? data['name'] as String
                          : user?.displayName ?? 'User';
                  final email = user?.email ?? 'email@example.com';
                  final department =
                      (data['department'] as String?)?.trim() ?? '';
                  final degree = (data['degree'] as String?)?.trim() ?? '';
                  final completion = _calculateCompletion(data);

                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 24,
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 96,
                                height: 96,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [sbPrimary, sbPrimaryDark],
                                  ),
                                ),
                                child: user?.photoURL == null
                                    ? const Icon(
                                        Icons.person,
                                        color: Colors.white,
                                        size: 46,
                                      )
                                    : ClipOval(
                                        child: Image.network(
                                          user!.photoURL!,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: sbText,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                email,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: sbSecondaryText,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (department.isNotEmpty)
                                    _buildTag(
                                      department,
                                      sbPrimary.withValues(alpha: 0.1),
                                      sbPrimary,
                                      sbPrimary,
                                    ),
                                  if (degree.isNotEmpty)
                                    _buildTag(
                                      degree,
                                      Colors.white,
                                      sbText,
                                      sbBorder,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Profile completion',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: sbText,
                                    ),
                                  ),
                                  Text(
                                    '${completion.toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: sbPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: completion / 100,
                                  minHeight: 8,
                                  backgroundColor:
                                      sbPrimary.withValues(alpha: 0.1),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          sbPrimary),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _membershipCard(data),
                        ),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const ProfileSectionLabel('GENERAL SETTINGS'),
                              const SizedBox(height: 12),
                              ProfileMenuTile(
                                icon: Icons.person_outline,
                                title: 'Edit Profile',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const EditProfileScreen(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              ProfileMenuTile(
                                icon: Icons.school_outlined,
                                title: 'Academic Profile',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const AcademicProfileScreen(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              ProfileMenuTile(
                                icon: Icons.tune_outlined,
                                title: 'Scholarship Preferences',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const ScholarshipPreferencesScreen(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              ProfileMenuTile(
                                icon: Icons.bookmark_outline,
                                title: 'Saved Scholarships',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const SavedScholarshipsScreen(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              ProfileMenuTile(
                                icon: Icons.notifications_outlined,
                                title: 'Notifications',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const NotificationsScreen(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              ProfileMenuTile(
                                icon: Icons.picture_as_pdf_outlined,
                                title: 'Download User Guide',
                                subtitle: 'Learn how to use ScholarBird',
                                onTap: () async {
                                  try {
                                    await PdfService.downloadUserGuide();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  'ScholarBird User Guide downloaded successfully.')));
                                    }
                                  } catch (_) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  'Unable to generate the User Guide. Please try again.')));
                                    }
                                  }
                                },
                              ),
                              const SizedBox(height: 12),
                              ProfileMenuTile(
                                icon: Icons.logout,
                                title: 'Logout',
                                isDestructive: true,
                                onTap: _logout,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  );
                },
              ),
      );

  double _calculateCompletion(Map<String, dynamic> data) {
    const fields = [
      'name',
      'phone',
      'nationality',
      'country',
      'university',
      'department',
      'degree',
    ];

    var completed = 0;
    for (final field in fields) {
      final value = data[field];
      if (value != null && value.toString().trim().isNotEmpty) {
        completed += 1;
      }
    }

    return (completed / fields.length) * 100;
  }

  Widget _membershipCard(Map<String, dynamic> data) {
    final membership = SubscriptionModel.fromMap(data);
    final premium = membership.isPremium;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF101A38), Color(0xFF24439A)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: sbPrimary.withValues(alpha: .18),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
            width: 46,
            height: 46,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(14)),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset('assets/images/Logo_ScholarBird.png',
                    fit: BoxFit.cover))),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(premium ? 'ScholarBird PRO' : 'ScholarBird Free',
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          const SizedBox(height: 4),
          Text(
              premium
                  ? 'Premium active - ${membership.daysRemaining} days remaining'
                  : 'Free plan - browse and save scholarships.',
              style: const TextStyle(fontSize: 12, color: Color(0xFFE2E8F0))),
        ])),
        const SizedBox(width: 12),
        InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => premium
                    ? const ManageSubscriptionScreen()
                    : const PremiumUpgradeScreen())),
            child: Text(premium ? 'View Details' : 'Upgrade Now',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline))),
      ]),
    );
  }

  Widget _buildTag(
    String text,
    Color backgroundColor,
    Color textColor,
    Color borderColor,
  ) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
      );
}
