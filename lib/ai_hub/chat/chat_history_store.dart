/// Persists chat history locally with SharedPreferences.
///
/// Storage layout (per signed-in user):
///   scholarbird_ai_chat:{uid} -> JSON-encoded list of [ChatMessage].
///
/// Chat history is intentionally kept out of Firestore per project policy —
/// only the on-device copy is read or written by this store.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'chat_message.dart';

/// Maximum number of messages retained per user. Older entries are dropped
/// on save so the SharedPreferences payload stays small and predictable.
const int kChatHistoryLimit = 200;

/// Key prefix used for every per-user chat thread.
const String _kKeyPrefix = 'scholarbird_ai_chat:';

/// Reads / writes the chat history for a single user.
class ChatHistoryStore {
  ChatHistoryStore({SharedPreferences? prefs}) : _injected = prefs;

  /// Lazily-resolved SharedPreferences handle. Tests can inject a synchronous
  /// instance via the constructor.
  final SharedPreferences? _injected;
  Future<SharedPreferences>? _future;

  Future<SharedPreferences> _prefs() {
    return _future ??= _injected != null
        ? Future<SharedPreferences>.value(_injected)
        : SharedPreferences.getInstance();
  }

  /// Returns the SharedPreferences key for the supplied [userId]. Sanitises
  /// the id so unusual characters cannot break the key namespace.
  static String keyFor(String userId) =>
      '$_kKeyPrefix${userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

  /// Loads the persisted history for [userId], newest last.
  Future<List<ChatMessage>> load(String userId) async {
    final prefs = await _prefs();
    final raw = prefs.getString(keyFor(userId));
    if (raw == null) return <ChatMessage>[];
    return ChatMessage.decode(raw);
  }

  /// Saves [messages] for [userId], trimming to the most recent
  /// [kChatHistoryLimit] entries.
  Future<void> save(String userId, List<ChatMessage> messages) async {
    final prefs = await _prefs();
    final trimmed = messages.length <= kChatHistoryLimit
        ? messages
        : messages.sublist(messages.length - kChatHistoryLimit);
    await prefs.setString(keyFor(userId), ChatMessage.encode(trimmed));
  }

  /// Wipes the chat history for [userId].
  Future<void> clear(String userId) async {
    final prefs = await _prefs();
    await prefs.remove(keyFor(userId));
  }
}