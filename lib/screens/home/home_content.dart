/// Home dashboard content showing promos, counts, and quick actions.
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../applications/my_applications.dart';
import '../profile/saved_scholarships_screen.dart';
import '../scholarship/scholarship_details.dart';
import '../premium/manage_subscription_screen.dart';
import '../premium/premium_upgrade_screen.dart';
import '../mentor/mentor_hub_screen.dart';
import '../../widgets/premium_banner.dart';
import '../../widgets/premium_guard.dart';
import '../../services/pdf_service.dart';
import '../../widgets/saved_scholarship_controls.dart';
import '../../theme/app_theme.dart';
import 'home_community_feed.dart';

/// Renders the scrollable dashboard cards for the home screen.
class HomeContent extends StatefulWidget {
  const HomeContent({
    required this.onExploreTap,
    this.onSavedTap,
    super.key,
  });

  final VoidCallback onExploreTap;
  final VoidCallback? onSavedTap;

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  late final PageController _bannerController;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _bannerController = PageController(viewportFraction: 0.92);
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _bannerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Greeting hero card
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: _GreetingCard(name: _getUserName()),
            ),

            const SizedBox(height: 18),

            // Promo Banners
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                height: 168,
                child: Listener(
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) {
                      final current = _scrollController.position.pixels;
                      final target = current + event.scrollDelta.dy;
                      final min = _scrollController.position.minScrollExtent;
                      final max = _scrollController.position.maxScrollExtent;
                      _scrollController.jumpTo(target.clamp(min, max));
                    }
                  },
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: const {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                      },
                    ),
                    child: PageView(
                      controller: _bannerController,
                      physics: const BouncingScrollPhysics(),
                      children: [
                        ListenableBuilder(
                          listenable: SubscriptionProviderScope.of(context),
                          builder: (context, _) {
                            final subscription =
                                SubscriptionProviderScope.of(context)
                                    .subscription;
                            return _PremiumBannerShell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => subscription.isPremium
                                      ? const ManageSubscriptionScreen()
                                      : const PremiumUpgradeScreen(),
                                ),
                              ),
                              child: PremiumBanner(
                                subscription: subscription,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => subscription.isPremium
                                        ? const ManageSubscriptionScreen()
                                        : const PremiumUpgradeScreen(),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        _PremiumBannerShell(
                          onTap: () async {
                            try {
                              await PdfService.downloadUserGuide();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'ScholarBird User Guide downloaded successfully.')));
                              }
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Unable to generate the User Guide. Please try again.')));
                              }
                            }
                          },
                          child: _buildPromoBanner(
                            context,
                            title: 'Free Scholarship Guide!',
                            subtitle:
                                'Download our ultimate guide to win Erasmus Mundus in 2026. Step-by-step strategy for success.',
                            buttonText: 'Download Guide',
                            gradient: AppGradients.sunrise,
                            icon: Icons.menu_book_rounded,
                            isDarkText: true,
                            onTap: () async {
                              try {
                                await PdfService.downloadUserGuide();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'ScholarBird User Guide downloaded successfully.')));
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Unable to generate the User Guide. Please try again.')));
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 22),

            // Find New Opportunities Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _AiOpportunitiesHero(
                onExploreTap: widget.onExploreTap,
                scholarshipStream: FirebaseFirestore.instance
                    .collection('scholarships')
                    .snapshots(),
              ),
            ),

            const SizedBox(height: 22),

            // Quick Stats
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _buildQuickStatCard(
                      label: 'Applied',
                      stream: _userCollectionStream('applications'),
                      accent: AppColors.primary,
                      icon: Icons.assignment_turned_in_rounded,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MyApplicationsScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildQuickStatCard(
                      label: 'Saved',
                      stream: _userCollectionStream('savedScholarships'),
                      accent: AppColors.accentViolet,
                      icon: Icons.bookmark_rounded,
                      onTap: () {
                        // Prefer the host tab switch so the bottom nav and
                        // drawer remain visible. Fall back to a push only if
                        // the host did not provide the callback.
                        if (widget.onSavedTap != null) {
                          widget.onSavedTap!();
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => Scaffold(
                              backgroundColor: AppColors.background,
                              body: const SavedScholarshipsScreen(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // Quick Services grid (visual addition that mirrors the reference
            // layout without changing any navigation/route — every tap calls
            // an existing host callback or shows a soft toast).
            const _QuickServicesGrid(),

            // Trending Scholarships Section
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: SectionHeader(
                title: 'Trending Scholarships',
                subtitle: 'Hand-picked opportunities closing soon',
                trailing: TextButton(
                  onPressed: widget.onExploreTap,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text('See all',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      SizedBox(width: 2),
                      Icon(Icons.arrow_forward_rounded, size: 16),
                    ],
                  ),
                ),
              ),
            ),

            // Scholarships Carousel
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                // Each card includes a badge, image, save control, and deadline.
                // The height must accommodate two-line titles on compact screens.
                height: 256,
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('scholarships')
                      .snapshots(),
                  builder: (context, snapshot) {
                    final allData = (snapshot.data?.docs ?? [])
                        .where((doc) =>
                            (doc.data() as Map<String, dynamic>)['isHidden'] !=
                            true)
                        .toList();
                    if (snapshot.hasError) {
                      return const Center(
                          child: Text('Unable to load scholarships'));
                    }
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        allData.isEmpty) {
                      return const Center(
                        child:
                            CircularProgressIndicator(color: AppColors.primary),
                      );
                    }
                    if (allData.isEmpty) {
                      return const Center(child: Text('No scholarships found'));
                    }

                    final items = allData
                        .map((doc) => <String, dynamic>{
                              ...doc.data()! as Map<String, dynamic>,
                              'id': doc.id,
                            })
                        .where((s) => s.isNotEmpty)
                        .toList();

                    items.sort((a, b) {
                      final aDate = _parseDeadline(a['deadline']);
                      final bDate = _parseDeadline(b['deadline']);
                      if (aDate == null && bDate == null) return 0;
                      if (aDate == null) return 1;
                      if (bDate == null) return -1;
                      return aDate.compareTo(bDate);
                    });

                    final topThree = items.take(3).toList();
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemBuilder: (context, index) => _buildScholarshipCard(
                        context,
                        topThree[index],
                      ),
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemCount: topThree.length,
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 28),
            const HomeCommunityFeed(),

            const SizedBox(height: 24),
          ],
        ),
      );

  Widget _buildScholarshipCard(BuildContext context, Map<String, dynamic> s) {
    final title = (s['title'] ?? '').toString();
    final location = (s['country'] ?? '').toString();
    final deadline = (s['deadline'] ?? '').toString();
    final badgeValue =
        (s['fundingType'] ?? s['amount'] ?? '').toString().trim();
    final imageUrl = (s['image'] ?? '').toString();

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ScholarshipDetailsScreen(data: s),
          ),
        );
      },
      child: Container(
        width: 176,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadows.soft,
          border: Border.all(color: AppColors.divider),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (badgeValue.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  gradient: AppGradients.primary,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: AppShadows.innerSoft,
                ),
                child: Text(
                  badgeValue,
                  style: const TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Row keeps the scholarship image and the bookmark control on one line.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.18),
                        AppColors.primary.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: imageUrl.isEmpty
                        ? const Icon(
                            Icons.school_rounded,
                            color: AppColors.primary,
                            size: 22,
                          )
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                              Icons.school_rounded,
                              color: AppColors.primary,
                              size: 22,
                            ),
                          ),
                  ),
                ),
                const Spacer(),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: SavedScholarshipIconButton(
                    scholarship: s,
                    iconSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title.isEmpty ? 'Untitled scholarship' : title,
              style: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                height: 1.3,
                letterSpacing: -0.1,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.place_outlined,
                    size: 13, color: AppColors.textMuted),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    location.isEmpty ? 'N/A' : location,
                    style: AppText.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.event_outlined,
                    size: 13, color: AppColors.textMuted),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    deadline.isEmpty ? 'Deadline: N/A' : 'Deadline: $deadline',
                    style: AppText.caption.copyWith(
                      color: AppColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _userCollectionStream(
      String collection) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Stream.empty();
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection(collection)
        .snapshots();
  }

  Widget _buildQuickStatCard({
    required String label,
    required Stream<QuerySnapshot<Map<String, dynamic>>> stream,
    required VoidCallback onTap,
    required Color accent,
    required IconData icon,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: AppShadows.soft,
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.18),
                      accent.withValues(alpha: 0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: stream,
                  builder: (context, snapshot) {
                    final count = snapshot.data?.docs.length ?? 0;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          count.toString(),
                          style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Icon(Icons.arrow_forward_rounded,
                  color: AppColors.textMuted, size: 18),
            ],
          ),
        ),
      );
  Widget _buildPromoBanner(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String buttonText,
    required LinearGradient gradient,
    required IconData icon,
    bool isDarkText = false,
    VoidCallback? onTap,
  }) {
    final titleColor = isDarkText ? const Color(0xFF0F172A) : Colors.white;
    final subtitleColor =
        isDarkText ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final buttonColor = isDarkText ? const Color(0xFF1E40AF) : Colors.white;
    final buttonTextColor = isDarkText ? Colors.white : const Color(0xFF1E3A8A);

    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: isDarkText ? 0.7 : 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: isDarkText ? const Color(0xFF1E3A8A) : Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: subtitleColor,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: buttonColor,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      onTap: onTap ??
                          () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Coming Soon...')),
                            );
                          },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          buttonText,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: buttonTextColor,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _parseDeadline(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();

    final trimmed = raw.toString().trim();
    if (trimmed.isEmpty) return null;

    final direct = DateTime.tryParse(trimmed);
    if (direct != null) return direct;

    final monthMap = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };

    final monthFirst = RegExp(
        r'^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2}),?\s*(\d{4})$');
    final dayFirst = RegExp(
        r'^(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s*(\d{4})$');

    final monthMatch = monthFirst.firstMatch(trimmed);
    if (monthMatch != null) {
      final month = monthMap[monthMatch.group(1)!.toLowerCase()];
      final day = int.tryParse(monthMatch.group(2) ?? '');
      final year = int.tryParse(monthMatch.group(3) ?? '');
      if (month != null && day != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    final dayMatch = dayFirst.firstMatch(trimmed);
    if (dayMatch != null) {
      final day = int.tryParse(dayMatch.group(1) ?? '');
      final month = monthMap[dayMatch.group(2)!.toLowerCase()];
      final year = int.tryParse(dayMatch.group(3) ?? '');
      if (month != null && day != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    return null;
  }

  String _getUserName() {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return 'Scholar';
  }
}

/// Greeting hero at the top of the home dashboard.
class _GreetingCard extends StatelessWidget {
  const _GreetingCard({required this.name});

  final String name;

  String get _timeBasedGreeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E54FF), Color(0xFF4F7BFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: AppShadows.primaryGlow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$_timeBasedGreeting, $name',
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('👋',
                        style: TextStyle(fontSize: 20)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Find scholarships that fit you.',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: const Icon(Icons.flight_takeoff_rounded,
                color: Colors.white, size: 26),
          ),
        ],
      ),
    );
  }
}

/// Premium call-to-action hero with embedded scholarship match counter.
class _AiOpportunitiesHero extends StatelessWidget {
  const _AiOpportunitiesHero({
    required this.onExploreTap,
    required this.scholarshipStream,
  });

  final VoidCallback onExploreTap;
  final Stream<QuerySnapshot> scholarshipStream;
  // Note: `onExploreTap` is wired directly to the Review button so tapping it
  // opens the AI Advisor screen without any intermediate "next" affordance.

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B1B3D), Color(0xFF1E3A8A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepNavy.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative ambient circles for premium depth.
          Positioned(
            top: -28,
            right: -24,
            child: _GlowCircle(
              size: 120,
              color: AppColors.primary.withValues(alpha: 0.35),
            ),
          ),
          Positioned(
            bottom: -40,
            left: -32,
            child: _GlowCircle(
              size: 140,
              color: AppColors.accentViolet.withValues(alpha: 0.22),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.auto_awesome,
                            size: 13, color: Colors.white),
                        SizedBox(width: 5),
                        Text(
                          'AI UPDATE',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                '5 new matches',
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.15,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              StreamBuilder<QuerySnapshot>(
                stream: scholarshipStream,
                builder: (context, snapshot) {
                  final count = (snapshot.data?.docs ?? const [])
                      .where((doc) =>
                          (doc.data()
                              as Map<String, dynamic>)['isHidden'] !=
                          true)
                      .length;
                  final label = count == 1
                      ? '1 fully funded match in your shortlist.'
                      : '$count fully funded matches in your shortlist.';
                  return Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.78),
                      height: 1.4,
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: onExploreTap,
                    icon: const Icon(Icons.bolt_rounded, size: 18),
                    label: const Text('Review'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      textStyle: const TextStyle(
                        fontFamily: 'Roboto',
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        letterSpacing: 0.2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.pill),
                      ),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Decorative blurred circle used by the hero card.
class _GlowCircle extends StatelessWidget {
  const _GlowCircle({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 40, spreadRadius: 4),
          ],
        ),
      ),
    );
  }
}

/// Wraps a banner child with a soft tap ripple that forwards to the same
/// handler that the banner itself uses.
class _PremiumBannerShell extends StatelessWidget {
  const _PremiumBannerShell({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}

/// Decorative quick services grid that mirrors the reference layout. Each
/// tile is interactive: it shows a hover/press feedback (the card fills with
/// the brand blue) and pops a tooltip-style overlay above the tile with a
/// short description. Tapping a tile routes the user to the matching flow.
class _QuickServicesGrid extends StatelessWidget {
  const _QuickServicesGrid();

  @override
  Widget build(BuildContext context) {
    final services = <_ServiceTileData>[
      _ServiceTileData(
        title: 'Mentoring',
        subtitle: '1:1 with scholars',
        description: 'Book a 1-on-1 session with a real scholar mentor.',
        icon: Icons.school_rounded,
        accent: AppColors.primary,
      ),
      _ServiceTileData(
        title: 'SOP',
        subtitle: 'Essay writer',
        description: 'Draft your Statement of Purpose with AI guidance.',
        icon: Icons.edit_note_rounded,
        accent: AppColors.accentMint,
      ),
      _ServiceTileData(
        title: 'Consultation',
        subtitle: 'Expert advisors',
        description: 'Chat with our advisors on WhatsApp for quick help.',
        icon: Icons.support_agent_rounded,
        accent: AppColors.accentSky,
      ),
      _ServiceTileData(
        title: 'Pro',
        subtitle: 'Premium services',
        description: 'Premium add-ons and concierge support.',
        icon: Icons.workspace_premium_rounded,
        accent: AppColors.accentAmber,
      ),
      _ServiceTileData(
        title: 'Subscription',
        subtitle: 'Unlimited access',
        description: 'Manage your ScholarBird Premium subscription.',
        icon: Icons.card_membership_rounded,
        accent: AppColors.accentViolet,
      ),
      _ServiceTileData(
        title: 'Course',
        subtitle: 'Guided Learning',
        description: 'Open the user guide or download the PDF manual.',
        icon: Icons.menu_book_rounded,
        accent: AppColors.accentRose,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Our Services',
            subtitle: 'Everything to win your scholarship',
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.95,
            children: [
              for (final service in services)
                _ServiceTile(
                  data: service,
                  onTap: () => _handleServiceTap(context, service),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Routes each service tile to its target. The tooltip overlay is purely
  /// descriptive and is shown by the tile itself; this method only fires the
  /// real action when the user actually taps the tile.
  void _handleServiceTap(BuildContext context, _ServiceTileData service) {
    switch (service.title) {
      case 'Mentoring':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MentorHubScreen()),
        );
        break;
      case 'SOP':
        Navigator.of(context).pushNamed('/ai-hub/sop');
        break;
      case 'Consultation':
        _openWhatsApp(context);
        break;
      case 'Pro':
        // Reserved: no-op for now.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pro services coming soon.'),
            duration: Duration(milliseconds: 1400),
          ),
        );
        break;
      case 'Subscription':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ManageSubscriptionScreen(),
          ),
        );
        break;
      case 'Course':
        _openCourse(context);
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${service.title} is coming soon.')),
        );
    }
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    // The phone number is provided as a plain local-format string; we
    // normalise it to the international E.164 form expected by wa.me.
    const rawNumber = '01893399532';
    final phone = '+880${rawNumber.substring(1)}';
    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent('Hi ScholarBird, I would like a consultation.')}',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open WhatsApp. Please try again later.'),
        ),
      );
    }
  }

  Future<void> _openCourse(BuildContext context) async {
    // Show a short helper dialog first so the user knows what to expect,
    // then trigger the same PDF download used elsewhere in the app.
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('ScholarBird User Guide'),
        content: const Text(
          'A short walkthrough of how to use the app. Tap Download to save the PDF manual to your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                await PdfService.downloadUserGuide();
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not download the user guide.'),
                    ),
                  );
                }
              }
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }
}

class _ServiceTileData {
  const _ServiceTileData({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color accent;
}

/// Interactive service tile with hover/press feedback.
///
/// On hover (web/desktop) or while pressed, the card flips to the brand blue
/// and a small tooltip-style overlay is rendered above it with a short
/// description. The tooltip follows the user gesture: it appears on hover and
/// is kept visible while pressed so the user gets clear feedback before the
/// tap actually fires the route.
class _ServiceTile extends StatefulWidget {
  const _ServiceTile({required this.data, required this.onTap});

  final _ServiceTileData data;
  final VoidCallback onTap;

  @override
  State<_ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<_ServiceTile> {
  bool _hover = false;
  bool _pressed = false;

  bool get _highlighted => _hover || _pressed;

  @override
  Widget build(BuildContext context) {
    final highlighted = _highlighted;
    final tile = _buildTile(highlighted);
    // The tooltip overlay is stacked above the tile via an OverlayPortal so
    // it floats cleanly even when the grid scrolls.
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: OverlayPortal(
          controller: _overlayController,
          overlayChildBuilder: (context) => _ServiceTooltip(
            text: widget.data.description,
            anchor: _anchorKey,
          ),
          child: CompositedTransformTarget(
            link: _layerLink,
            child: KeyedSubtree(
              key: _anchorKey,
              child: tile,
            ),
          ),
        ),
      ),
    );
  }

  final LayerLink _layerLink = LayerLink();
  final GlobalKey _anchorKey = GlobalKey();
  final OverlayPortalController _overlayController = OverlayPortalController();

  Widget _buildTile(bool highlighted) {
    final accent = widget.data.accent;
    final bg = highlighted ? AppColors.primary : Colors.white;
    final fg = highlighted ? Colors.white : AppColors.textPrimary;
    final subFg =
        highlighted ? Colors.white.withValues(alpha: 0.85) : AppColors.textMuted;
    final iconBg = highlighted
        ? Colors.white.withValues(alpha: 0.18)
        : accent.withValues(alpha: 0.16);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () {
          _hideTooltip();
          widget.onTap();
        },
        onHover: (hover) {
          setState(() => _hover = hover);
          if (hover) {
            _showTooltip();
          } else {
            _hideTooltip();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: highlighted ? AppColors.primary : AppColors.divider,
            ),
            boxShadow: highlighted ? AppShadows.primaryGlow : AppShadows.soft,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.data.icon,
                  color: highlighted ? Colors.white : accent,
                  size: 22,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.data.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: fg,
                  letterSpacing: -0.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                widget.data.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: subFg,
                  height: 1.25,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTooltip() {
    if (_overlayController.isShowing) return;
    _overlayController.show();
  }

  void _hideTooltip() {
    if (!_overlayController.isShowing) return;
    _overlayController.hide();
  }

  @override
  void dispose() {
    _overlayController.hide();
    super.dispose();
  }
}

/// Floating tooltip anchored above the originating service tile.
class _ServiceTooltip extends StatelessWidget {
  const _ServiceTooltip({required this.text, required this.anchor});

  final String text;
  final GlobalKey anchor;

  @override
  Widget build(BuildContext context) {
    final renderBox =
        anchor.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return const SizedBox.shrink();
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final left = offset.dx + size.width / 2 - 90;
    final top = offset.dy - 44;
    return Positioned(
      left: left.clamp(8.0, MediaQuery.of(context).size.width - 188),
      top: top,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 180,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryDark,
              borderRadius: BorderRadius.circular(8),
              boxShadow: AppShadows.primaryGlow,
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
