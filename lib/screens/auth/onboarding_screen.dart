import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late PageController _pageController;
  int _currentPage = 0;

  final List<OnboardingPage> _pages = [
    OnboardingPage(
      title: 'Discover Scholarships',
      description:
          'Find the best scholarships tailored for your academic journey',
      illustration: _buildIllustration(0),
    ),
    OnboardingPage(
      title: 'Track Applications',
      description: 'Keep track of your application progress in one place',
      illustration: _buildIllustration(1),
    ),
    OnboardingPage(
      title: 'Smart Filtering',
      description:
          'Easily filter scholarships by field, country, and degree',
      illustration: _buildIllustration(2),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _skipToLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('firstTime', false);

    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  void _goToNextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _getStarted();
    }
  }

  Future<void> _getStarted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('firstTime', false);

    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  static Widget _buildIllustration(int pageIndex) {
    const colors = [
      Color(0xFF0052CC),
      Color(0xFF80B3FF),
      Color(0xFF4DABF7),
    ];

    const icons = [
      Icons.search,
      Icons.track_changes,
      Icons.filter_list,
    ];

    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors[pageIndex].withOpacity(0.1),
      ),
      child: Center(
        child: Icon(
          icons[pageIndex],
          size: 100,
          color: colors[pageIndex],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              // Skip button
              Positioned(
                top: 16,
                right: 16,
                child: TextButton(
                  onPressed: _skipToLogin,
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0052CC),
                    ),
                  ),
                ),
              ),
              // PageView
              PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                children: _pages
                    .map(
                      (page) => _buildPage(context, page),
                    )
                    .toList(),
              ),
              // Bottom navigation area
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 30,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        spreadRadius: 0,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Page indicator dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _pages.length,
                          (index) => Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _currentPage == index
                                  ? const Color(0xFF0052CC)
                                  : const Color(0xFF0052CC).withOpacity(0.3),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Next / Get Started button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _goToNextPage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0052CC),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            _currentPage == _pages.length - 1
                                ? 'Get Started'
                                : 'Next',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
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
        ),
      ),
    );

  Widget _buildPage(BuildContext context, OnboardingPage page) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Illustration
          page.illustration,
          const SizedBox(height: 48),
          // Title
          Text(
            page.title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // Description
          Text(
            page.description,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF666666),
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
}

class OnboardingPage {

  OnboardingPage({
    required this.title,
    required this.description,
    required this.illustration,
  });
  final String title;
  final String description;
  final Widget illustration;
}
