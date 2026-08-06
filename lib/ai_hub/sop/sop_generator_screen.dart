/// Orchestrates the SOP Generator flow: collect profile context →
/// render the input form → request a draft from Gemini → preview / persist
/// / regenerate / download / save-as-document.
///
/// Splits the screen into two stages:
///   1. _Stage.input   → SopInputForm
///   2. _Stage.output  → SopOutputView (preview + actions)
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
import 'ai_history_service.dart';
import 'sop_draft.dart';
import 'sop_generator_service.dart';
import 'sop_input_form.dart';
import 'sop_output_view.dart';
import 'sop_pdf_builder.dart';
import 'sop_prompt_params.dart';

/// Top-level entry point for the SOP Generator experience.
class SopGeneratorScreen extends StatefulWidget {
  const SopGeneratorScreen({
    super.key,
    SopGeneratorService? generator,
    AiHistoryService? history,
  })  : _generator = generator,
        _history = history;

  final SopGeneratorService? _generator;
  final AiHistoryService? _history;

  @override
  State<SopGeneratorScreen> createState() => _SopGeneratorScreenState();
}

class _SopGeneratorScreenState extends State<SopGeneratorScreen> {
  /// Tracks whether the user is looking at the input form or the draft
  /// preview. When null we are still loading profile context.
  _Stage? _stage;

  late final SopGeneratorService _generator =
      widget._generator ?? SopGeneratorService();
  late final AiHistoryService _history =
      widget._history ?? AiHistoryService();
  final SopPdfBuilder _pdfBuilder = const SopPdfBuilder();

  UserProfile? _profile;
  SopDraft? _currentDraft;
  SopFormSubmission? _lastSubmission;
  bool _isGenerating = false;
  bool _isPersisting = false;
  bool _savingAsDocument = false;
  Object? _loadError;

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

  // ---------------------------------------------------------------------------
  // Bootstrap
  // ---------------------------------------------------------------------------

  Future<void> _bootstrap() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loadError = StateError('You need to sign in first.'));
      return;
    }

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
      });
      _referencesSub =
          ReferencesService.instance.streamReferences().listen((items) {
        if (!mounted) return;
        setState(() => _references = items);
      });

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _stage = _Stage.input;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    }
  }

  // ---------------------------------------------------------------------------
  // Generation
  // ---------------------------------------------------------------------------

  Future<void> _handleRegenerate() async {
    final last = _lastSubmission;
    if (last == null) return;
    await _handleSubmit(last);
  }

  Future<void> _handleSubmit(SopFormSubmission submission) async {
    final user = FirebaseAuth.instance.currentUser;
    final profile = _profile;
    if (user == null || profile == null) {
      _showSnack('Profile not ready — please retry in a moment.');
      return;
    }
    _lastSubmission = submission;
    final params = SopPromptParams(
      user: profile,
      type: submission.type,
      targetProgramme: submission.targetProgramme,
      targetUniversity: submission.targetUniversity,
      targetField: submission.targetField,
      scholarshipName: submission.scholarshipName,
      wordCountTarget: submission.wordCountTarget,
      additionalNotes: submission.additionalNotes,
      documents: _documents,
      sopDocuments:
          _documents.where((d) => d.type == DocumentType.sop).toList(),
      references: _references,
    );

    final isRegeneration = _currentDraft != null;
    final draftId = _currentDraft?.id ?? _newDraftId();
    final now = DateTime.now();

    setState(() {
      _isGenerating = true;
    });

    try {
      final draft = await _generator.generate(
        userId: user.uid,
        params: params,
        draftId: draftId,
        now: now,
        existingTitle: _currentDraft?.title ?? '',
      );
      if (!mounted) return;
      setState(() {
        _currentDraft = draft;
        _stage = _Stage.output;
        _isGenerating = false;
      });
      // Persist asynchronously — UI does not need to wait.
      unawaited(_persistDraft(draft));
      if (isRegeneration) {
        unawaited(_history.bumpRegenerations(
          userId: user.uid,
          draftId: draft.id,
        ));
      }
    } on GeminiConfigurationException catch (e) {
      _onGenerationError(
        'Add a Gemini API key in your .env file before generating.',
        e,
      );
    } on GeminiRequestException catch (e) {
      _onGenerationError(
        'Gemini could not complete the request. Check your connection and retry.',
        e,
      );
    } catch (e) {
      _onGenerationError('Something went wrong while generating.', e);
    }
  }

  void _onGenerationError(String userMessage, Object error) {
    if (!mounted) return;
    setState(() => _isGenerating = false);
    debugPrint('[SOP] generation failed: $error');
    _showSnack(userMessage);
  }

  Future<void> _persistDraft(SopDraft draft) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isPersisting = true);
    try {
      await _history.saveSopDraft(userId: user.uid, draft: draft);
    } catch (e) {
      debugPrint('[SOP] persist failed: $e');
      _showSnack('Could not save this draft to your history.');
    } finally {
      if (mounted) setState(() => _isPersisting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _handleDownloadPdf() async {
    final draft = _currentDraft;
    if (draft == null) return;
    try {
      await _pdfBuilder.downloadSop(draft);
      _showSnack('PDF ready — share or save it from your device.');
    } catch (e) {
      debugPrint('[SOP] pdf download failed: $e');
      _showSnack('Could not build the PDF — please retry.');
    }
  }

  Future<void> _handleSaveAsDocument() async {
    final user = FirebaseAuth.instance.currentUser;
    final draft = _currentDraft;
    if (user == null || draft == null) return;
    setState(() => _savingAsDocument = true);
    try {
      final document = DocumentModel(
        type: DocumentType.sop,
        fileName: '${draft.suggestedFilename()}.txt',
        uploadedAt: DateTime.now(),
        fileSize: draft.body.length,
      );
      await DocumentsService.instance.saveDocument(document);
      _showSnack('Saved to your Documents as "${document.fileName}".');
    } catch (e) {
      debugPrint('[SOP] save-as-document failed: $e');
      _showSnack('Could not save to Documents — please retry.');
    } finally {
      if (mounted) setState(() => _savingAsDocument = false);
    }
  }

  void _handleBackToForm() {
    setState(() => _stage = _Stage.input);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _newDraftId() => 'sop-${DateTime.now().millisecondsSinceEpoch}';

  void _showSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ScholarBirdColors.background,
      appBar: AppBar(
        backgroundColor: ScholarBirdColors.surface,
        foregroundColor: ScholarBirdColors.ink,
        elevation: 0,
        title: const Text('Statement of Purpose'),
        actions: [
          if (_stage == _Stage.output && _currentDraft != null)
            IconButton(
              tooltip: 'Back to form',
              onPressed: _isGenerating ? null : _handleBackToForm,
              icon: const Icon(Icons.edit_note_outlined),
            ),
        ],
      ),
      body: PremiumGuard(
        feature: PremiumFeature.sopGenerator,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadError != null) {
      return _ErrorPanel(
        message: 'Could not load your profile.',
        detail: '$_loadError',
        onRetry: _bootstrap,
      );
    }
    if (_stage == null || _profile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    switch (_stage!) {
      case _Stage.input:
        return SopInputForm(
          userDocuments: _documents.where((d) => d.isUploaded).length,
          userReferences: _references.length,
          isGenerating: _isGenerating,
          onSubmit: _handleSubmit,
        );
      case _Stage.output:
        final draft = _currentDraft;
        if (draft == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return Stack(
          children: [
            SopOutputView(
              draft: draft,
              isRegenerating: _isGenerating,
              onRegenerate: _handleRegenerate,
              onDownloadPdf: _handleDownloadPdf,
              onSaveAsDocument: _handleSaveAsDocument,
            ),
            if (_isPersisting || _savingAsDocument)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        );
    }
  }
}

enum _Stage { input, output }

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
            const Icon(Icons.cloud_off_outlined,
                size: 48, color: ScholarBirdColors.body),
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
