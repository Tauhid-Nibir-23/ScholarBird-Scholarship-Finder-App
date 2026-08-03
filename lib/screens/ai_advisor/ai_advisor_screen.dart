import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/scholarship.dart';
import '../../models/scholarship_recommendation.dart';
import '../../models/user_profile.dart';
import '../../services/gemini_service.dart';
import '../scholarship/scholarship_details.dart';
import '../../widgets/saved_scholarship_controls.dart';

class AIAdvisorScreen extends StatefulWidget {
  const AIAdvisorScreen({super.key, this.onMenuTap});
  final VoidCallback? onMenuTap;

  @override
  State<AIAdvisorScreen> createState() => _AIAdvisorScreenState();
}

class _AIAdvisorScreenState extends State<AIAdvisorScreen> {
  final GeminiService _geminiService = GeminiService();
  List<ScholarshipRecommendation> _recommendations =
      <ScholarshipRecommendation>[];
  bool _isLoading = false;
  String? _error;

  Future<void> _getRecommendations(UserProfile profile) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final scholarshipSnapshot =
          await FirebaseFirestore.instance.collection('scholarships').get();
      final scholarships =
          scholarshipSnapshot.docs.map(Scholarship.fromFirestore).toList();
      final results = await _geminiService.getScholarshipRecommendations(
          profile, scholarships);
      final detailsByName = {
        for (final document in scholarshipSnapshot.docs)
          (document.data()['title'] ?? '').toString().trim().toLowerCase():
              <String, dynamic>{...document.data(), 'id': document.id},
      };
      if (mounted) {
        setState(() => _recommendations = results.map((item) {
              final scholarship =
                  detailsByName[item.scholarshipName.toLowerCase()];
              return item.withScholarship(
                country: (scholarship?['country'] ?? '').toString(),
                scholarshipId: (scholarship?['id'] ?? '').toString(),
                scholarshipData: scholarship,
              );
            }).toList());
      }
    } on FirebaseException {
      if (mounted) {
        setState(
            () => _error = 'Unable to fetch scholarships. Please try again.');
      }
    } on GeminiConfigurationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on GeminiRequestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Unable to generate recommendations. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const _AdvisorMessage(
          message: 'Please log in to use ScholarBird AI.');
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF5B7AE8)));
        }
        if (snapshot.hasError) {
          return const _AdvisorMessage(
              message: 'Unable to load your profile. Please try again.');
        }

        final profile = UserProfile.fromFirestore(snapshot.data!);
        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FB),
          appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              toolbarHeight: 72,
              shape: const Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
              leading: IconButton(
                  tooltip: 'Open navigation menu',
                  onPressed: widget.onMenuTap,
                  icon: const Icon(Icons.menu_rounded)),
              centerTitle: true,
              title: const Text('ScholarBird AI',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)))),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _ProfileMatchCard(profile: profile),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: _isLoading || !profile.hasEnoughInformation
                      ? null
                      : () => _getRecommendations(profile),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome, color: Colors.white),
                  label: Text(_isLoading
                      ? 'Finding matches...'
                      : 'Find my top matches'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5B7AE8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                ),
                if (!profile.hasEnoughInformation)
                  const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                          'Complete your academic profile and preferences to get recommendations.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Color(0xFF6B7A95), fontSize: 13))),
                if (_error != null) _ErrorState(message: _error!),
                if (!_isLoading && _error == null && _recommendations.isEmpty)
                  const _AdvisorEmptyState(),
                ..._recommendations.map((recommendation) =>
                    _RecommendationCard(recommendation: recommendation)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProfileMatchCard extends StatelessWidget {
  const _ProfileMatchCard({required this.profile});
  final UserProfile profile;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Your Profile Match',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E))),
          const SizedBox(height: 12),
          _profileLine(Icons.school_outlined,
              profile.degree.isEmpty ? 'Degree not added' : profile.degree),
          _profileLine(Icons.grade_outlined,
              profile.cgpa == null ? 'CGPA not added' : 'CGPA ${profile.cgpa}'),
          _profileLine(
              Icons.public_outlined,
              profile.preferredStudyCountries.isEmpty
                  ? 'Preferred country not added'
                  : profile.preferredStudyCountries.join(', ')),
          _profileLine(
              Icons.psychology_outlined,
              profile.skills.isEmpty
                  ? 'Skills not added'
                  : profile.skills.join(', ')),
          _profileLine(
              Icons.menu_book_outlined,
              profile.academicBackground.isEmpty
                  ? 'Academic background not added'
                  : profile.academicBackground),
        ]),
      );
  Widget _profileLine(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 18, color: const Color(0xFF5B7AE8)),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13, color: Color(0xFF2F2F3A))))
      ]));
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.recommendation});
  final ScholarshipRecommendation recommendation;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .04), blurRadius: 12)
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(recommendation.scholarshipName,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E)))),
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: const Color(0xFFE8EDFF),
                    borderRadius: BorderRadius.circular(14)),
                child: Text(recommendation.matchProbability,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: Color(0xFF5B7AE8))))
          ]),
          const SizedBox(height: 10),
          Text(recommendation.reason,
              style: const TextStyle(
                  fontSize: 13, height: 1.45, color: Color(0xFF4B5563))),
          if (recommendation.country.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.public, size: 15, color: Color(0xFF6B7A95)),
              const SizedBox(width: 6),
              Text(recommendation.country,
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF6B7A95)))
            ])
          ],
          if (recommendation.scholarshipId.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ScholarshipDetailsScreen(
                          data: recommendation.scholarshipData!,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('View Scholarship'),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FB),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SavedScholarshipIconButton(
                    scholarship: recommendation.scholarshipData!,
                    iconSize: 22,
                  ),
                ),
              ],
            ),
          ],
        ]),
      );
}

class _AdvisorEmptyState extends StatelessWidget {
  const _AdvisorEmptyState();
  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.only(top: 38),
      child: Column(children: [
        Icon(Icons.auto_awesome_outlined, size: 48, color: Color(0xFF9CA3AF)),
        SizedBox(height: 10),
        Text('Your recommendations will appear here.',
            style: TextStyle(color: Color(0xFF6B7A95)))
      ]));
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.redAccent)));
}

class _AdvisorMessage extends StatelessWidget {
  const _AdvisorMessage({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Center(
          child:
              Text(message, style: const TextStyle(color: Color(0xFF6B7A95)))));
}
