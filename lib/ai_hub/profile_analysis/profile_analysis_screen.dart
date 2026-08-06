/// Screen that drives the profile analysis experience.
///
/// Mirrors the SOP generator flow: it loads the user's profile, documents,
/// and references through the shared `ChatContext` bundle, hands them to
/// Gemini via `ProfileAnalysisService`, validates the strict JSON response,
/// then renders the qualitative report. Past reports are streamed from the
/// AI history service so the user can revisit earlier analyses without
/// re-prompting Gemini.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/document_model.dart';
import '../../models/reference_model.dart';
import '../../models/user_profile.dart';
import '../../services/documents_service.dart';
import '../../services/gemini_service.dart' show GeminiConfigurationException,
      GeminiRequestException;
import '../../services/references_service.dart';
import '../../theme/scholarbird_theme.dart';
import '../../widgets/premium_feature.dart';
import '../../widgets/premium_guard.dart';
import '../chat/chat_context.dart';
import '../sop/ai_history_service.dart';
import 'profile_analysis_report.dart';
import 'profile_analysis_service.dart';

/// Top-level entry point for the profile analysis feature.
class ProfileAnalysisScreen extends StatefulWidget {
  const ProfileAnalysisScreen({
    super.key,
    ProfileAnalysisService? analysisService,
    AiHistoryService? history,
  })  : _analysisService = analysisService,
        _history = history;

  final ProfileAnalysisService? _analysisService;
  final AiHistoryService? _history;

  @override
  State<ProfileAnalysisScreen> createState() => _ProfileAnalysisScreenState();
}

class _ProfileAnalysisScreenState extends State<ProfileAnalysisScreen> {
  late final ProfileAnalysisService _service =
      widget._analysisService ?? ProfileAnalysisService();
  late final AiHistoryService _history =
      widget._history ?? AiHistoryService();

  Object? _loadError;
  bool _isLoadingContext = true;
  bool _isGenerating = false;

  ChatContext? _context;
  ProfileAnalysisReport? _currentReport;
  ProfileAnalysisRecord? _currentRecord;
  String _currentUserId = '';

  StreamSubscription<List<DocumentModel>>? _documentsSub;
  StreamSubscription<List<ReferenceModel>>? _referencesSub;
  List<DocumentModel> _documents = const <DocumentModel>[];
  List<ReferenceModel> _references = const <ReferenceModel>[];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _documentsSub?.cancel();
    _referencesSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _loadError = StateError('You need to sign in first.');
        _isLoadingContext = false;
      });
      return;
    }
    _currentUserId = user.uid;

    try {
      final profileSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final profile = profileSnap.exists
          ? UserProfile.fromFirestore(profileSnap)
          : const UserProfile(
              degree: '',
              cgpa: null,
              country: '',
              skills: <String>[],
              preferredStudyCountries: <String>[],
              academicBackground: '',
            );

      _documentsSub =
          DocumentsService.instance.streamDocuments().listen((items) {
        if (!mounted) return;
        setState(() => _documents = items);
        _refreshContext(profile);
      });
      _referencesSub =
          ReferencesService.instance.streamReferences().listen((items) {
        if (!mounted) return;
        setState(() => _references = items);
        _refreshContext(profile);
      });

      if (!mounted) return;
      setState(() {
        _context = ChatContext.from(
          profile: profile,
          documents: _documents,
          references: _references,
        );
        _isLoadingContext = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _isLoadingContext = false;
      });
    }
  }

  void _refreshContext(UserProfile profile) {
    if (!mounted) return;
    setState(() {
      _context = ChatContext.from(
        profile: profile,
        documents: _documents,
        references: _references,
      );
    });
  }

  Future<void> _handleGenerate() async {
    final ctx = _context;
    final userId = _currentUserId;
    if (ctx == null || userId.isEmpty) {
      _showSnack('Profile context is still loading. Please wait a moment.');
      return;
    }
    setState(() => _isGenerating = true);
    final now = DateTime.now();
    try {
      final report = await _service.analyze(context: ctx, now: now);
      if (!mounted) return;
      setState(() {
        _currentReport = report;
        _currentRecord = null;
        _isGenerating = false;
      });
      unawaited(_persistReport(report));
    } on GeminiConfigurationException catch (e) {
      _onGenerationError(
        'Add a Gemini API key in your .env file before running an analysis.',
        e,
      );
    } on GeminiRequestException catch (e) {
      _onGenerationError(
        'Gemini could not complete the analysis. Check your connection and retry.',
        e,
      );
    } catch (e) {
      _onGenerationError(
        'Something went wrong while analysing the profile.',
        e,
      );
    }
  }

  void _onGenerationError(String userMessage, Object error) {
    if (!mounted) return;
    setState(() => _isGenerating = false);
    debugPrint('[ProfileAnalysis] generation failed: $error');
    _showSnack(userMessage);
  }

  Future<void> _persistReport(ProfileAnalysisReport report) async {
    final userId = _currentUserId;
    if (userId.isEmpty) return;
    try {
      await _history.saveProfileAnalysis(userId: userId, report: report);
    } catch (e) {
      debugPrint('[ProfileAnalysis] persist failed: $e');
      _showSnack('Report ready but could not be saved to your history.');
    }
  }

  Future<void> _handleOpenHistory(ProfileAnalysisRecord record) async {
    if (!mounted) return;
    setState(() {
      _currentRecord = record;
      _currentReport = record.toReport();
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PremiumGuard(
      feature: PremiumFeature.aiRecommendations,
      child: Scaffold(
        backgroundColor: ScholarBirdColors.background,
        appBar: AppBar(
          backgroundColor: ScholarBirdColors.surface,
          foregroundColor: ScholarBirdColors.ink,
          elevation: 0,
          title: const Text('Profile Analysis'),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadError != null) {
      return _ErrorPanel(
        message: 'Could not load your profile.',
        detail: '$_loadError',
        onRetry: () {
          setState(() {
            _loadError = null;
            _isLoadingContext = true;
          });
          _bootstrap();
        },
      );
    }
    if (_isLoadingContext || _context == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final report = _currentReport;
    return ListView(
      padding: const EdgeInsets.all(ScholarBirdSpacing.large),
      children: [
        _ContextSummaryCard(
          context: _context!,
          isGenerating: _isGenerating,
          onGenerate: _isGenerating ? null : _handleGenerate,
        ),
        const SizedBox(height: ScholarBirdSpacing.large),
        if (report == null)
          const _IntroPrompt()
        else ...[
          _RatingHeader(report: report),
          const SizedBox(height: ScholarBirdSpacing.large),
          _SummaryCard(summary: report.summary),
          const SizedBox(height: ScholarBirdSpacing.large),
          _ReadinessCard(text: report.scholarshipReadiness),
          const SizedBox(height: ScholarBirdSpacing.large),
          _InsightSection(
            title: 'Strengths',
            icon: Icons.bolt_outlined,
            items: report.strengths,
            emptyHint: 'No strengths identified yet — keep refining your profile.',
          ),
          const SizedBox(height: ScholarBirdSpacing.medium),
          _InsightSection(
            title: 'Weaknesses',
            icon: Icons.warning_amber_outlined,
            items: report.weaknesses,
            emptyHint: 'No major weaknesses flagged — you are in good shape.',
          ),
          const SizedBox(height: ScholarBirdSpacing.medium),
          _InsightSection(
            title: 'Missing Documents',
            icon: Icons.folder_open_outlined,
            items: report.missingDocuments,
            emptyHint: 'Your document set looks complete for the next round.',
          ),
          const SizedBox(height: ScholarBirdSpacing.medium),
          _InsightSection(
            title: 'Suggested Improvements',
            icon: Icons.checklist_outlined,
            items: report.suggestedImprovements,
            emptyHint: 'No immediate improvements suggested.',
          ),
          const SizedBox(height: ScholarBirdSpacing.medium),
          _InsightSection(
            title: 'Best Scholarship Types',
            icon: Icons.school_outlined,
            items: report.bestScholarshipTypes,
            emptyHint: 'Scholarship-type recommendations will appear here.',
          ),
          const SizedBox(height: ScholarBirdSpacing.medium),
          _InsightSection(
            title: 'Countries Recommendation',
            icon: Icons.public_outlined,
            items: report.countriesRecommendation,
            emptyHint: 'Country recommendations will appear here.',
          ),
          const SizedBox(height: ScholarBirdSpacing.large),
          _RatingRationaleCard(rationale: report.ratingRationale),
        ],
        const SizedBox(height: ScholarBirdSpacing.large),
        _HistorySection(
          history: _history,
          userId: _currentUserId,
          activeRecordId: _currentRecord?.id,
          onOpen: _handleOpenHistory,
        ),
      ],
    );
  }
}

class _ContextSummaryCard extends StatelessWidget {
  const _ContextSummaryCard({
    required this.context,
    required this.isGenerating,
    required this.onGenerate,
  });

  final ChatContext context;
  final bool isGenerating;
  final VoidCallback? onGenerate;

  @override
  Widget build(BuildContext buildContext) {
    // Alias the field to a local with a distinct name so the incoming
    // `buildContext` parameter does not shadow the ChatContext instance.
    final chatContext = context;
    return Container(
      padding: const EdgeInsets.all(ScholarBirdSpacing.large),
      decoration: BoxDecoration(
        color: ScholarBirdColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ScholarBirdColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8EDFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.insights_outlined,
                  color: ScholarBirdColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: ScholarBirdSpacing.medium),
              const Expanded(
                child: Text(
                  'Readiness report',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ScholarBirdColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ScholarBirdSpacing.small),
          Text(
            chatContext.summary(),
            style: const TextStyle(
              fontSize: 13,
              color: ScholarBirdColors.body,
              height: 1.4,
            ),
          ),
          const SizedBox(height: ScholarBirdSpacing.medium),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onGenerate,
              icon: isGenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome, color: Colors.white),
              label: Text(
                isGenerating
                    ? 'Analysing your profile...'
                    : 'Generate analysis',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroPrompt extends StatelessWidget {
  const _IntroPrompt();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ScholarBirdSpacing.large),
      decoration: BoxDecoration(
        color: ScholarBirdColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ScholarBirdColors.border),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            color: ScholarBirdColors.primary,
            size: 24,
          ),
          SizedBox(width: ScholarBirdSpacing.medium),
          Expanded(
            child: Text(
              'Tap "Generate analysis" to get a qualitative readiness report '
              'based on your profile, documents, and references.',
              style: TextStyle(
                fontSize: 13,
                color: ScholarBirdColors.body,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingHeader extends StatelessWidget {
  const _RatingHeader({required this.report});

  final ProfileAnalysisReport report;

  @override
  Widget build(BuildContext context) {
    final rating = report.overallRating;
    return Container(
      padding: const EdgeInsets.all(ScholarBirdSpacing.large),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            ScholarBirdColors.primary,
            Color(0xFF7C9BFF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.workspace_premium_outlined,
            color: Colors.white,
            size: 32,
          ),
          const SizedBox(width: ScholarBirdSpacing.medium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Overall readiness',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  rating.label,
                  style: const TextStyle(
                    fontSize: 24,
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final String summary;

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      title: 'Summary',
      icon: Icons.summarize_outlined,
      child: Text(
        summary,
        style: const TextStyle(
          fontSize: 14,
          color: ScholarBirdColors.ink,
          height: 1.5,
        ),
      ),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      title: 'Scholarship Readiness',
      icon: Icons.timeline,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          color: ScholarBirdColors.ink,
          height: 1.5,
        ),
      ),
    );
  }
}

class _RatingRationaleCard extends StatelessWidget {
  const _RatingRationaleCard({required this.rationale});

  final String rationale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EDFF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 18,
            color: ScholarBirdColors.primary,
          ),
          const SizedBox(width: ScholarBirdSpacing.small),
          Expanded(
            child: Text(
              rationale,
              style: const TextStyle(
                fontSize: 13,
                color: ScholarBirdColors.ink,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightSection extends StatelessWidget {
  const _InsightSection({
    required this.title,
    required this.icon,
    required this.items,
    required this.emptyHint,
  });

  final String title;
  final IconData icon;
  final List<ProfileAnalysisInsight> items;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      title: title,
      icon: icon,
      child: items.isEmpty
          ? Text(
              emptyHint,
              style: const TextStyle(
                fontSize: 13,
                color: ScholarBirdColors.body,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final insight in items)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: ScholarBirdSpacing.small,
                    ),
                    child: _InsightCard(insight: insight),
                  ),
              ],
            ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});

  final ProfileAnalysisInsight insight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
      decoration: BoxDecoration(
        color: ScholarBirdColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ScholarBirdColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            insight.title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: ScholarBirdColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            insight.rationale,
            style: const TextStyle(
              fontSize: 13,
              color: ScholarBirdColors.body,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionShell extends StatelessWidget {
  const _SectionShell({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ScholarBirdSpacing.large),
      decoration: BoxDecoration(
        color: ScholarBirdColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ScholarBirdColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: ScholarBirdColors.primary),
              const SizedBox(width: ScholarBirdSpacing.small),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: ScholarBirdColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: ScholarBirdSpacing.small),
          child,
        ],
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({
    required this.history,
    required this.userId,
    required this.activeRecordId,
    required this.onOpen,
  });

  final AiHistoryService history;
  final String userId;
  final String? activeRecordId;
  final ValueChanged<ProfileAnalysisRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) return const SizedBox.shrink();
    return _SectionShell(
      title: 'Past analyses',
      icon: Icons.history,
      child: StreamBuilder<List<ProfileAnalysisRecord>>(
        stream: history.streamProfileAnalyses(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(minHeight: 2),
            );
          }
          final items = snapshot.data ?? const <ProfileAnalysisRecord>[];
          if (items.isEmpty) {
            return const Text(
              'No saved analyses yet. Your first report will be saved here.',
              style: TextStyle(
                fontSize: 13,
                color: ScholarBirdColors.body,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final record in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _HistoryTile(
                    record: record,
                    isActive: record.id == activeRecordId,
                    onTap: () => onOpen(record),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.record,
    required this.isActive,
    required this.onTap,
  });

  final ProfileAnalysisRecord record;
  final bool isActive;
  final VoidCallback onTap;

  static final DateFormat _formatter = DateFormat('MMM d, yyyy • h:mm a');

  @override
  Widget build(BuildContext context) {
    final report = record.toReport();
    final generated = _formatter.format(record.createdAt.toLocal());
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(ScholarBirdSpacing.medium),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFE8EDFF) : ScholarBirdColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? ScholarBirdColors.primary
                : ScholarBirdColors.border,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.bolt_outlined,
              size: 18,
              color: ScholarBirdColors.primary,
            ),
            const SizedBox(width: ScholarBirdSpacing.small),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${report.overallRating.label} • $generated',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ScholarBirdColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    report.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: ScholarBirdColors.body,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: ScholarBirdColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.detail,
    required this.onRetry,
  });

  final String message;
  final String detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(ScholarBirdSpacing.large),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: ScholarBirdColors.body,
            ),
            const SizedBox(height: ScholarBirdSpacing.medium),
            Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ScholarBirdColors.ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: ScholarBirdSpacing.small),
            Text(
              detail,
              style: const TextStyle(
                fontSize: 12,
                color: ScholarBirdColors.body,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: ScholarBirdSpacing.large),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
