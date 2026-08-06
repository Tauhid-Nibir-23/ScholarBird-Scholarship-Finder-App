/// Modern ScholarBird AI chat interface.
///
/// Reuses the shared [GeminiService] (via [ChatService]) for generation and
/// stores the conversation history in SharedPreferences so nothing leaks
/// into Firestore. The screen loads the user's profile / documents /
/// references once on entry and feeds them into the system prompt so the
/// chatbot stays personalised for the duration of the conversation.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../ai_hub/chat/chat_context.dart';
import '../../ai_hub/chat/chat_history_store.dart';
import '../../ai_hub/chat/chat_message.dart';
import '../../ai_hub/chat/chat_service.dart';
import '../../ai_hub/services/gemini_service.dart';
import '../../models/user_profile.dart';
import '../../services/documents_service.dart';
import '../../services/references_service.dart';
import '../../theme/scholarbird_theme.dart';
import '../../widgets/premium_feature.dart';
import '../../widgets/premium_guard.dart';

/// Entry point for the ScholarBird AI chat feature.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _composerFocus = FocusNode();

  late final ChatService _chatService;
  late final ChatHistoryStore _historyStore;

  StreamSubscription<String>? _activeStream;
  Timer? _scrollDebounce;

  List<ChatMessage> _messages = <ChatMessage>[];
  ChatContext? _context;
  bool _isStreaming = false;
  bool _isInitialising = true;
  String? _error;
  String _currentUserId = '';

  static const List<_Suggestion> _starterSuggestions = <_Suggestion>[
    _Suggestion(
      'Which scholarships should I target with my CGPA?',
      Icons.school_outlined,
    ),
    _Suggestion(
      'Help me draft an SOP opening paragraph.',
      Icons.edit_document,
    ),
    _Suggestion(
      'What documents do I need for a US student visa?',
      Icons.badge_outlined,
    ),
    _Suggestion(
      'How do I pick the right referees?',
      Icons.mail_outline_rounded,
    ),
    _Suggestion(
      'IELTS 6.5 vs 7.0 — which is enough for top universities?',
      Icons.translate_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _chatService = ChatService();
    _historyStore = ChatHistoryStore();
    _composer.addListener(_onComposerChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _activeStream?.cancel();
    _scrollDebounce?.cancel();
    _composer.removeListener(_onComposerChanged);
    _composer.dispose();
    _scrollController.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _onComposerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _bootstrap() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isInitialising = false;
        _error = 'Please log in to chat with ScholarBird AI.';
      });
      return;
    }
    _currentUserId = user.uid;
    try {
      final history = await _historyStore.load(user.uid);
      final context = await _loadContext(user.uid);
      if (!mounted) return;
      setState(() {
        _messages = history;
        _context = context;
        _isInitialising = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isInitialising = false;
        _error = 'Could not start the chat. Please try again.';
      });
    }
  }

  Future<ChatContext> _loadContext(String userId) async {
    final profileSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    final profile = profileSnapshot.exists
        ? UserProfile.fromFirestore(profileSnapshot)
        : UserProfile(
            degree: '',
            cgpa: null,
            country: '',
            skills: const <String>[],
            preferredStudyCountries: const <String>[],
            academicBackground: '',
          );

    final documents = await _firstNonEmpty(
      DocumentsService.instance.streamDocuments(),
    );
    final references = await _firstNonEmpty(
      ReferencesService.instance.streamReferences(),
    );

    return ChatContext.from(
      profile: profile,
      documents: documents,
      references: references,
    );
  }

  Future<List<T>> _firstNonEmpty<T>(Stream<List<T>> stream) async {
    final completer = Completer<List<T>>();
    StreamSubscription<List<T>>? subscription;
    Timer? timer;
    timer = Timer(const Duration(seconds: 2), () {
      if (!completer.isCompleted) {
        subscription?.cancel();
        completer.complete(<T>[]);
      }
    });
    subscription = stream.listen((value) {
      if (!completer.isCompleted) {
        timer?.cancel();
        completer.complete(value);
      }
    }, onError: (_) {
      if (!completer.isCompleted) {
        timer?.cancel();
        completer.complete(<T>[]);
      }
    });
    final result = await completer.future;
    await subscription.cancel();
    return result;
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent + 120,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _scheduleScroll() {
    _scrollDebounce?.cancel();
    _scrollDebounce = Timer(const Duration(milliseconds: 60), _scrollToBottom);
  }

  Future<void> _send(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || _isStreaming || _context == null) return;
    final context = _context!;
    final userMessage = ChatMessage(
      id: _newMessageId(),
      role: ChatRole.user,
      content: text,
      createdAt: DateTime.now(),
    );

    final pendingAssistant = ChatMessage(
      id: _newMessageId(),
      role: ChatRole.assistant,
      content: '',
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages = [..._messages, userMessage, pendingAssistant];
      _isStreaming = true;
      _error = null;
    });
    _composer.clear();
    _scheduleScroll();

    try {
      final historyForPrompt = _messages
          .where((msg) => msg.id != pendingAssistant.id)
          .toList(growable: false);

      final buffer = StringBuffer();
      final stream = _chatService.streamReply(
        context: context,
        history: historyForPrompt,
        userMessage: text,
      );

      _activeStream = stream.listen(
        (chunk) {
          buffer.write(chunk);
          _appendToAssistant(pendingAssistant.id, buffer.toString());
          _scheduleScroll();
        },
        onError: (error) {
          _finaliseAssistant(
            pendingAssistant.id,
            _errorMessage(error),
            persist: true,
          );
        },
        onDone: () {
          final finalText = buffer.toString().trim();
          if (finalText.isEmpty) {
            _finaliseAssistant(
              pendingAssistant.id,
              'ScholarBird AI returned an empty response. Please try again.',
              persist: true,
            );
          } else {
            _finaliseAssistant(pendingAssistant.id, finalText, persist: true);
          }
        },
        cancelOnError: true,
      );
    } catch (error) {
      _finaliseAssistant(
        pendingAssistant.id,
        _errorMessage(error),
        persist: true,
      );
    }
  }

  void _appendToAssistant(String id, String content) {
    if (!mounted) return;
    setState(() {
      _messages = _messages
          .map((msg) => msg.id == id ? msg.copyWith(content: content) : msg)
          .toList(growable: false);
    });
  }

  void _finaliseAssistant(String id, String content, {required bool persist}) {
    if (!mounted) return;
    final updated = _messages
        .map((msg) => msg.id == id ? msg.copyWith(content: content) : msg)
        .toList(growable: false);
    setState(() {
      _messages = updated;
      _isStreaming = false;
    });
    _activeStream = null;
    if (persist) {
      _persistHistory(updated);
    }
    _scheduleScroll();
  }

  Future<void> _persistHistory(List<ChatMessage> messages) async {
    if (_currentUserId.isEmpty) return;
    try {
      await _historyStore.save(_currentUserId, messages);
    } catch (_) {
      // Persistence is best-effort — a failed write should not interrupt the
      // user's chat. We surface a one-shot error string in the UI so the user
      // knows their history might not survive a relaunch.
      if (!mounted) return;
      setState(() => _error = 'Could not save the latest message locally.');
    }
  }

  String _errorMessage(Object error) {
    if (error is GeminiConfigurationException) return error.message;
    if (error is GeminiRequestException) return error.message;
    return 'ScholarBird AI is unavailable. Please try again shortly.';
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear chat history?'),
        content: const Text(
          'This will delete every message in this conversation from this device. '
          'It cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    unawaited(_activeStream?.cancel());
    _activeStream = null;
    if (_currentUserId.isNotEmpty) {
      await _historyStore.clear(_currentUserId);
    }
    if (!mounted) return;
    setState(() {
      _messages = <ChatMessage>[];
      _isStreaming = false;
      _error = null;
    });
  }

  String _newMessageId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_messages.length}';

  @override
  Widget build(BuildContext context) {
    if (_isInitialising) {
      return const _ChatLoadingScaffold();
    }
    if (_context == null) {
      return _ChatMessageScaffold(
        title: 'ScholarBird AI',
        message: _error ?? 'Please log in to chat with ScholarBird AI.',
      );
    }

    return PremiumGuard(
      feature: PremiumFeature.aiChatAssistant,
      child: Scaffold(
      backgroundColor: ScholarBirdColors.background,
      appBar: AppBar(
        backgroundColor: ScholarBirdColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const Border(
          bottom: BorderSide(color: ScholarBirdColors.border),
        ),
        titleSpacing: 0,
        title: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: ScholarBirdColors.primary.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 18,
                color: ScholarBirdColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'ScholarBird AI',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: ScholarBirdColors.ink,
                    ),
                  ),
                  Text(
                    _context!.summary(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: ScholarBirdColors.body,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Clear chat',
            onPressed: _messages.isEmpty ? null : _confirmClearHistory,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: _MessageList(
                controller: _scrollController,
                messages: _messages,
                isStreaming: _isStreaming,
                onSuggestionTap: (text) {
                  _composer.text = text;
                  _composer.selection = TextSelection.fromPosition(
                    TextPosition(offset: text.length),
                  );
                  _composerFocus.requestFocus();
                },
                starterSuggestions: _starterSuggestions,
              ),
            ),
            if (_error != null) _ErrorBanner(message: _error!),
            _Composer(
              controller: _composer,
              focusNode: _composerFocus,
              isStreaming: _isStreaming,
              onSend: _send,
              onStop: _stopStreaming,
            ),
          ],
        ),
      ),
      ),
    );
  }

  void _stopStreaming() {
    _activeStream?.cancel();
    _activeStream = null;
    final pending = _messages.lastOrNull;
    if (pending != null && pending.role == ChatRole.assistant) {
      final text = pending.content.trim().isEmpty
          ? 'Response stopped.'
          : '${pending.content.trim()}\n\n_Response stopped._';
      _finaliseAssistant(pending.id, text, persist: true);
    } else {
      setState(() => _isStreaming = false);
    }
  }
}

/// Renders the message list, an empty-state with starter suggestions, and
/// the auto-scroll behaviour.
class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.controller,
    required this.messages,
    required this.isStreaming,
    required this.onSuggestionTap,
    required this.starterSuggestions,
  });

  final ScrollController controller;
  final List<ChatMessage> messages;
  final bool isStreaming;
  final ValueChanged<String> onSuggestionTap;
  final List<_Suggestion> starterSuggestions;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return _EmptyState(
        suggestions: starterSuggestions,
        onSuggestionTap: onSuggestionTap,
      );
    }
    final children = <Widget>[];
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      final showDateHeader = i == 0 ||
          !_isSameDay(messages[i - 1].createdAt, message.createdAt);
      if (showDateHeader) {
        children.add(_DayHeader(date: message.createdAt));
      }
      children.add(_MessageBubble(message: message));
    }
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date});
  final DateTime date;
  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final label = _labelFor(date, today);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: ScholarBirdColors.background,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ScholarBirdColors.body,
            ),
          ),
        ),
      ),
    );
  }

  static String _labelFor(DateTime date, DateTime today) {
    if (_isSameDay(date, today)) return 'Today';
    final yesterday = today.subtract(const Duration(days: 1));
    if (_isSameDay(date, yesterday)) return 'Yesterday';
    return DateFormat('EEEE, MMM d').format(date);
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final isEmpty = message.content.trim().isEmpty;
    final showTyping = isEmpty && message.role == ChatRole.assistant;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final theme = Theme.of(context);
    final bubbleColor = isUser
        ? ScholarBirdColors.primary
        : ScholarBirdColors.surface;
    final textColor = isUser ? Colors.white : ScholarBirdColors.ink;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isUser ? 18 : 4),
      bottomRight: Radius.circular(isUser ? 4 : 18),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82,
          ),
          child: Column(
            crossAxisAlignment: isUser
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: <Widget>[
              if (!isUser)
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.auto_awesome,
                        size: 12,
                        color: ScholarBirdColors.primary,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'ScholarBird AI',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: ScholarBirdColors.body,
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: radius,
                  border: isUser
                      ? null
                      : Border.all(color: ScholarBirdColors.border),
                  boxShadow: isUser
                      ? null
                      : <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: showTyping
                    ? const _TypingDots()
                    : SelectableText(
                        message.content,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: textColor,
                          height: 1.45,
                        ),
                      ),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('HH:mm').format(message.createdAt),
                style: const TextStyle(
                  fontSize: 10,
                  color: ScholarBirdColors.body,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dots = <Widget>[];
    for (var i = 0; i < 3; i++) {
      final interval = Interval(i * 0.2, 0.6 + i * 0.2, curve: Curves.easeInOut);
      dots.add(
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final scale = 0.6 +
                (0.4 *
                    (interval.transform(_controller.value).clamp(0.0, 1.0)));
            return Opacity(
              opacity: scale,
              child: child,
            );
          },
          child: Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: const BoxDecoration(
              color: ScholarBirdColors.body,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: dots);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.suggestions,
    required this.onSuggestionTap,
  });
  final List<_Suggestion> suggestions;
  final ValueChanged<String> onSuggestionTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: ScholarBirdColors.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: ScholarBirdColors.primary,
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Hi, I am ScholarBird AI',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: ScholarBirdColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Ask me about scholarships, admissions, SOP, CV, visa, funding, '
            'research, IELTS, applications, recommendation letters, or study '
            'abroad. I already have your profile, documents and references in '
            'context.',
            style: TextStyle(
              fontSize: 13,
              color: ScholarBirdColors.body,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Try asking',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ScholarBirdColors.body,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions
                .map(
                  (s) => _SuggestionChip(
                    suggestion: s,
                    onTap: () => onSuggestionTap(s.text),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.suggestion, required this.onTap});
  final _Suggestion suggestion;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: ScholarBirdColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: ScholarBirdColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(suggestion.icon, size: 14, color: ScholarBirdColors.primary),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 230),
                child: Text(
                  suggestion.text,
                  style: const TextStyle(
                    fontSize: 12,
                    color: ScholarBirdColors.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.isStreaming,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isStreaming;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      decoration: const BoxDecoration(
        color: ScholarBirdColors.surface,
        border: Border(top: BorderSide(color: ScholarBirdColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 140),
                decoration: BoxDecoration(
                  color: ScholarBirdColors.background,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: ScholarBirdColors.border),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !isStreaming,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    hintText: 'Ask ScholarBird AI…',
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: ScholarBirdColors.muted,
                    ),
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _SendButton(
              isStreaming: isStreaming,
              hasText: controller.text.trim().isNotEmpty,
              onSend: () => onSend(controller.text),
              onStop: onStop,
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.isStreaming,
    required this.hasText,
    required this.onSend,
    required this.onStop,
  });

  final bool isStreaming;
  final bool hasText;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    if (isStreaming) {
      return Material(
        color: ScholarBirdColors.background,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onStop,
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ScholarBirdColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ScholarBirdColors.border),
            ),
            child: const Icon(
              Icons.stop_rounded,
              color: ScholarBirdColors.primary,
            ),
          ),
        ),
      );
    }
    final enabled = hasText;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Send message',
      child: Material(
        color:
            enabled ? ScholarBirdColors.primary : ScholarBirdColors.background,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onSend : null,
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  enabled
                  ? ScholarBirdColors.primary
                  : ScholarBirdColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: enabled
                    ? ScholarBirdColors.primary
                    : ScholarBirdColors.border,
              ),
            ),
            child: Icon(
              Icons.arrow_upward_rounded,
              color: enabled ? Colors.white : ScholarBirdColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFEE2E2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFB91C1C),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ChatLoadingScaffold extends StatelessWidget {
  const _ChatLoadingScaffold();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ScholarBirdColors.background,
      appBar: AppBar(
        backgroundColor: ScholarBirdColors.surface,
        elevation: 0,
        shape: const Border(
          bottom: BorderSide(color: ScholarBirdColors.border),
        ),
        title: const Text(
          'ScholarBird AI',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ScholarBirdColors.ink,
          ),
        ),
      ),
      body: const Center(
        child: CircularProgressIndicator(color: ScholarBirdColors.primary),
      ),
    );
  }
}

class _ChatMessageScaffold extends StatelessWidget {
  const _ChatMessageScaffold({required this.title, required this.message});
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ScholarBirdColors.background,
      appBar: AppBar(
        backgroundColor: ScholarBirdColors.surface,
        elevation: 0,
        shape: const Border(
          bottom: BorderSide(color: ScholarBirdColors.border),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ScholarBirdColors.ink,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: ScholarBirdColors.body),
          ),
        ),
      ),
    );
  }
}

class _Suggestion {
  const _Suggestion(this.text, this.icon);
  final String text;
  final IconData icon;
}
