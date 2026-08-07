import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../scholarship/scholarship_list.dart';
import '../community/community_screen.dart';
import '../profile/profile_screen.dart';
import '../profile/notifications_screen.dart';
import '../profile/saved_scholarships_screen.dart';
import '../applications/my_applications.dart';
import '../ai_advisor/ai_advisor_screen.dart';
import '../premium/premium_upgrade_screen.dart';
import '../../widgets/scholarbird_navigation_drawer.dart';
import '../mentor/mentor_hub_screen.dart';
import '../../theme/app_theme.dart';
import 'home_content.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentIndex = 0;
  late PageController _pageController;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _screens = [
      HomeContent(
        onExploreTap: _openAiAdvisor,
        onSavedTap: _openSaved,
      ),
      ScholarshipsScreen(onMenuTap: _openDrawer),
      AIAdvisorScreen(onMenuTap: _openDrawer),
      CommunityScreen(onMenuTap: _openDrawer),
      ProfileScreen(onMenuTap: _openDrawer),
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppColors.background,
        extendBodyBehindAppBar: false,
        drawer: ScholarBirdNavigationDrawer(
          selectedIndex: _currentIndex,
          onTabSelected: _goToTab,
          onSaved: _openSaved,
          onMyApplications: () => _push(const MyApplicationsScreen()),
          onNotifications: () => _push(const NotificationsScreen()),
          onPremium: () => _push(const PremiumUpgradeScreen()),
          onMentorHub: () => _push(const MentorHubScreen()),
          onLogout: _logout,
        ),
        appBar: _buildAppBar(),
        body: PageView(
          controller: _pageController,
          onPageChanged: (index) {
            setState(() => _currentIndex = index);
          },
          physics: const NeverScrollableScrollPhysics(),
          children: _screens,
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: _goToTab,
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            selectedItemColor: AppColors.primary,
            unselectedItemColor: AppColors.textMuted,
            selectedLabelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.search_outlined),
                activeIcon: Icon(Icons.search_rounded),
                label: 'Explore',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.auto_awesome_outlined),
                activeIcon: Icon(Icons.auto_awesome),
                label: 'AI Advisor',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.groups_outlined),
                activeIcon: Icon(Icons.groups_rounded),
                label: 'Community',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person_rounded),
                label: 'Profile',
              ),
            ],
          ),
        ),
      );

  void _goToTab(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
    _pageController.animateToPage(index,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  /// Jumps straight to the AI Advisor tab (index 2) when the user taps the
  /// Review button on the home hero card.
  void _openAiAdvisor() => _goToTab(2);

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  void _openSaved() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xFFF5F7FB),
          body: SavedScholarshipsScreen(
            onMenuTap: _openDrawer,
            onExplore: () {
              Navigator.of(context).pop();
              _goToTab(1);
            },
          ),
        ),
      ),
    );
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  PreferredSizeWidget? _buildAppBar() {
    if (_currentIndex == 0) {
      return PreferredSize(
        preferredSize: const Size.fromHeight(76),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 10),
              child: Row(
                children: [
                  Builder(
                    builder: (context) => _AppBarIconButton(
                      icon: Icons.menu_rounded,
                      tooltip: 'Open navigation menu',
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: AppShadows.innerSoft,
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/Logo_ScholarBird.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'ScholarBird',
                          style: AppText.title.copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Find scholarships that fit you',
                          style: AppText.caption.copyWith(
                            fontSize: 11.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _AskAiButton(
                    onTap: _openAiAdvisor,
                  ),
                  const SizedBox(width: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: AppShadows.innerSoft,
                    ),
                    child: UnreadNotificationBell(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const NotificationsScreen()),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    // Each secondary tab owns its own app bar. Returning null removes the
    // otherwise empty bar and keeps its heading aligned with the top.
    return null;
  }
}

/// Small circular icon button used in the restyled home app bar.
class _AppBarIconButton extends StatelessWidget {
  const _AppBarIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: AppColors.textPrimary, size: 24),
      onPressed: onPressed,
      splashRadius: 22,
    );
  }
}

/// Pill-shaped "Ask AI" entry point placed in the home app bar.
class _AskAiButton extends StatelessWidget {
  const _AskAiButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: AppGradients.primary,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: AppShadows.primaryGlow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              'Ask AI',
              style: AppText.button.copyWith(fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
