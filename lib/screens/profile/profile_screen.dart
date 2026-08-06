/// Profile hub that surfaces account data, settings, and saved resources.
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
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
import '../../services/profile_image_service.dart';
import '../../widgets/academic_references_section.dart';
import '../../widgets/documents_section.dart';

/// Displays the signed-in user's profile and account management actions.
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
                              _ProfileAvatar(
                                user: user,
                                name: name,
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
                              const ProfileSectionLabel('PROFESSIONAL PROFILE'),
                              const SizedBox(height: 12),
                              const DocumentsSection(),
                              const SizedBox(height: 12),
                              const AcademicReferencesSection(),
                            ],
                          ),
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
                                    builder: (_) => Scaffold(
                                      backgroundColor:
                                          const Color(0xFFF5F7FB),
                                      body: SavedScholarshipsScreen(
                                        onExplore: () =>
                                            Navigator.of(context).pop(),
                                      ),
                                    ),
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
    // Profile completion is split across the three edit surfaces:
    //   - Personal info (Edit Profile)     -> 40%
    //   - Academic profile                 -> 40%
    //   - Scholarship preferences          -> 20%
    // The bar only reaches 100% when each section is fully filled.
    const personalFields = <String>[
      'name',
      'phone',
      'nationality',
      'country',
      'university',
      'department',
      'degree',
    ];
    const academicFields = <String>[
      'currentYear',
      'cgpa',
      'ielts',
      'toefl',
      'researchExperience',
      'publicationCount',
      'workExperienceYears',
      'graduationYear',
      'englishMedium',
      'targetDegree',
    ];
    const preferenceFields = <String>[
      'preferredCountries',
      'preferredDegree',
      'interestedFields',
      'fundingTypes',
      'intakes',
    ];

    bool isFilled(String field) {
      final value = data[field];
      if (value == null) return false;
      if (value is String) return value.trim().isNotEmpty;
      if (value is num) return true;
      if (value is bool) return true;
      if (value is List) return value.isNotEmpty;
      return false;
    }

    double sectionPercent(List<String> fields) {
      if (fields.isEmpty) return 0;
      final filled = fields.where(isFilled).length;
      return (filled / fields.length) * 100;
    }

    final personal = sectionPercent(personalFields);
    final academic = sectionPercent(academicFields);
    final preferences = sectionPercent(preferenceFields);

    return personal * 0.40 + academic * 0.40 + preferences * 0.20;
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
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => premium
                    ? const ManageSubscriptionScreen()
                    : const PremiumUpgradeScreen())),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(premium ? 'View Details' : 'Upgrade Now',
                  style: const TextStyle(
                      color: Color(0xFF1E3A8A),
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ),
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

/// Round avatar at the top of the profile hub.
///
/// Reads its photo from the Firestore `users/{uid}.profileImage` field so
/// every UI surface (drawer, profile, home greeting) updates instantly
/// when the photo changes. Tapping the avatar opens a bottom sheet with
/// the gallery / camera / remove actions; uploads go through
/// [ProfileImageService].
class _ProfileAvatar extends StatefulWidget {
  const _ProfileAvatar({required this.user, required this.name});

  /// Auth record used purely for initials / fallback.
  final User? user;

  /// Display name — drives the initials overlay.
  final String name;

  @override
  State<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<_ProfileAvatar> {
  bool _uploading = false;

  bool get _hasUser => widget.user != null;

  Future<void> _onTap() async {
    if (!_hasUser || _uploading) return;
    final action = await showModalBottomSheet<_AvatarAction>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(ctx).pop(_AvatarAction.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(ctx).pop(_AvatarAction.camera),
            ),
            if (_hasUser)
              StreamBuilder<String?>(
                stream: ProfileImageService.instance.streamProfileImage(),
                builder: (context, snapshot) {
                  final hasPhoto = (snapshot.data ?? '').isNotEmpty;
                  if (!hasPhoto) return const SizedBox.shrink();
                  return ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.red),
                    title: const Text(
                      'Remove photo',
                      style: TextStyle(color: Colors.red),
                    ),
                    onTap: () => Navigator.of(ctx).pop(_AvatarAction.remove),
                  );
                },
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    setState(() => _uploading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (action) {
        case _AvatarAction.gallery:
          await ProfileImageService.instance.pickAndUploadFromGallery();
          break;
        case _AvatarAction.camera:
          await ProfileImageService.instance.pickAndUploadFromCamera();
          break;
        case _AvatarAction.remove:
          await ProfileImageService.instance.removeProfileImage();
          break;
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String get _initials {
    final trimmed = widget.name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasUser) {
      return Container(
        width: 96,
        height: 96,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [sbPrimary, sbPrimaryDark]),
        ),
        child: const Icon(Icons.person, color: Colors.white, size: 46),
      );
    }
    return GestureDetector(
      onTap: _onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          StreamBuilder<String?>(
            stream: ProfileImageService.instance.streamProfileImage(),
            builder: (context, snapshot) {
              final firestoreUrl = snapshot.data ?? '';
              // Prefer Firestore `profileImage`; fall back to whatever the
              // legacy Firebase Auth photoURL holds so existing users
              // with a Google avatar still see it before uploading.
              final url = firestoreUrl.isNotEmpty
                  ? firestoreUrl
                  : (widget.user?.photoURL ?? '');
              final hasPhoto = url.isNotEmpty;
              return Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: hasPhoto
                      ? null
                      : const LinearGradient(
                          colors: [sbPrimary, sbPrimaryDark],
                        ),
                  color: hasPhoto ? Colors.white : null,
                  image: hasPhoto
                      ? DecorationImage(
                          image: NetworkImage(url),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: hasPhoto
                    ? null
                    : Text(
                        _initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              );
            },
          ),
          if (_uploading)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x88000000),
                ),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(
                color: sbPrimary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _AvatarAction { gallery, camera, remove }
