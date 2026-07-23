import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../applications/my_applications.dart';
import '../profile/saved_scholarships_screen.dart';
import '../scholarship/scholarship_details.dart';

class HomeContent extends StatefulWidget {
  const HomeContent({required this.onExploreTap, super.key});

  final VoidCallback onExploreTap;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, ${_getUserName()}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Ready to continue your journey?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF6B7A95),
                  ),
                ),
              ],
            ),
          ),

          // Promo Banners
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              height: 140,
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
                      _buildPromoBanner(
                        context,
                        title: 'Unlock ScholarBird Pro!',
                        subtitle:
                            'Get exclusive access to 500+ hidden scholarships and expert SOP/Resume reviews.',
                        buttonText: 'Upgrade Now',
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        icon: Icons.workspace_premium_outlined,
                      ),
                      _buildPromoBanner(
                        context,
                        title: 'Free Scholarship Guide!',
                        subtitle:
                            'Download our ultimate guide to win Erasmus Mundus in 2026. Step-by-step strategy for success.',
                        buttonText: 'Download Guide',
                        gradient: const LinearGradient(
                          colors: [Color(0xFF93C5FD), Color(0xFFFDE68A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        icon: Icons.menu_book_outlined,
                        isDarkText: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Find New Opportunities Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1A1A2E).withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Find new opportunities',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('scholarships')
                        .snapshots(),
                    builder: (context, snapshot) {
                      final count = snapshot.data?.docs.length ?? 0;
                      final label = count == 1
                          ? '1 scholarship matches your profile'
                          : '$count scholarships match your profile';
                      return Text(
                        label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFFB4B9C8),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: widget.onExploreTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5B7AE8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Browse All',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Quick Stats
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _buildQuickStatCard(
                    label: 'Applied',
                    stream: _userCollectionStream('applications'),
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
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SavedScholarshipsScreen(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Trending Scholarships Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Trending Scholarships',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                TextButton(
                  onPressed: widget.onExploreTap,
                  child: const Text(
                    'See all',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5B7AE8),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Scholarships Carousel
          SizedBox(
            height: 200,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('scholarships').snapshots(),
              builder: (context, snapshot) {
                final allData = snapshot.data?.docs ?? [];
                if (snapshot.hasError) {
                  return const Center(child: Text('Unable to load scholarships'));
                }
                if (snapshot.connectionState == ConnectionState.waiting && allData.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF5B7AE8)),
                  );
                }
                if (allData.isEmpty) {
                  return const Center(child: Text('No scholarships found'));
                }

                final items = allData
                    .map((doc) => doc.data() as Map<String, dynamic>)
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
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemCount: topThree.length,
                );
              },
            ),
          ),

          const SizedBox(height: 30),
        ],
      ),
    );

  Widget _buildScholarshipCard(BuildContext context, Map<String, dynamic> s) {
    final title = (s['title'] ?? '').toString();
    final location = (s['country'] ?? '').toString();
    final deadline = (s['deadline'] ?? '').toString();
    final badgeValue = (s['fundingType'] ?? s['amount'] ?? '').toString().trim();
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
          width: 160,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFE5E7EB),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (badgeValue.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B7AE8).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badgeValue,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5B7AE8),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF5B7AE8).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: imageUrl.isEmpty
                      ? const Icon(
                          Icons.school_outlined,
                          color: Color(0xFF5B7AE8),
                          size: 20,
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                            Icons.school_outlined,
                            color: Color(0xFF5B7AE8),
                            size: 20,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title.isEmpty ? 'Untitled scholarship' : title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                location.isEmpty ? 'N/A' : location,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF9CA3AF),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Deadline: ${deadline.isEmpty ? 'N/A' : deadline}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF9CA3AF),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
  }) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF5B7AE8).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.bookmark_border,
                color: Color(0xFF5B7AE8),
                size: 20,
              ),
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
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7A95),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        count.toString(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
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
  Widget _buildPromoBanner(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String buttonText,
    required LinearGradient gradient,
    required IconData icon,
    bool isDarkText = false,
  }) {
    final titleColor = isDarkText ? const Color(0xFF0F172A) : Colors.white;
    final subtitleColor =
        isDarkText ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final buttonColor = isDarkText ? const Color(0xFF1E40AF) : Colors.white;
    final buttonTextColor = isDarkText ? Colors.white : const Color(0xFF1E3A8A);

    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(isDarkText ? 0.7 : 0.15),
              borderRadius: BorderRadius.circular(14),
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
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: subtitleColor,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: buttonColor,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Coming Soon...')),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          buttonText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: buttonTextColor,
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
