/// Domain model for a single message in the ScholarBird AI chat.
///
/// Stored locally only — chat history is intentionally kept out of Firestore
/// per project policy.
library;

import 'dart:convert';

/// Who produced the message.
enum ChatRole {
  /// The end user typing into the chat.
  user,

  /// ScholarBird AI (Gemini) replying.
  assistant,

  /// A synthetic message rendered when the model declines an off-topic
  /// question. This avoids making a network round-trip for the refusal text
  /// itself while still letting the UI show a coherent conversation.
  system,
}

/// Immutable representation of a single chat message.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  /// Stable identifier (timestamp + counter) used as the Flutter list key
  /// and when serialising to local storage.
  final String id;

  /// Author of the message.
  final ChatRole role;

  /// Plain-text content. Markdown is rendered as-is by the chat bubble — the
  /// model is instructed not to use markdown headings, but bold, italic and
  /// bullet lists are kept lightweight.
  final String content;

  /// When the message was created.
  final DateTime createdAt;

  /// True while an assistant message is still streaming in.
  bool get isAssistant => role == ChatRole.assistant;

  /// Returns a copy with [content] replaced. Used to grow an assistant
  /// message as the streaming response arrives.
  ChatMessage copyWith({String? content, DateTime? createdAt}) => ChatMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        createdAt: createdAt ?? this.createdAt,
      );

  /// Serialises to a JSON-friendly map for SharedPreferences storage.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'role': role.name,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
      };

  /// Hydrates from the JSON shape produced by [toJson]. Returns null when
  /// the payload is unreadable so callers can skip corrupt entries instead
  /// of crashing the whole chat history.
  static ChatMessage? tryFromJson(Map<String, dynamic> json) {
    final role = ChatRole.values.firstWhere(
      (value) => value.name == json['role'],
      orElse: () => ChatRole.user,
    );
    final content = (json['content'] as String?)?.trim() ?? '';
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now();
    final id = json['id']?.toString() ?? createdAt.microsecondsSinceEpoch.toString();
    if (content.isEmpty) return null;
    return ChatMessage(
      id: id,
      role: role,
      content: content,
      createdAt: createdAt,
    );
  }

  /// Convenience for batch (de)serialisation.
  static String encode(List<ChatMessage> messages) =>
      jsonEncode(messages.map((m) => m.toJson()).toList());

  static List<ChatMessage> decode(String raw) {
    if (raw.trim().isEmpty) return const <ChatMessage>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <ChatMessage>[];
      return decoded
          .whereType<Map>()
          .map((item) =>
              ChatMessage.tryFromJson(Map<String, dynamic>.from(item)))
          .whereType<ChatMessage>()
          .toList(growable: false);
    } catch (_) {
      // A corrupt entry should never block the user from opening the chat —
      // we drop the entire history and start fresh rather than crash.
      return const <ChatMessage>[];
    }
  }
}
