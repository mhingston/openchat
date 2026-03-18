import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../models/chat_thread.dart';
import '../models/conversation_search_result.dart';

class ChatStore {
  ChatStore(this._preferences);

  static const String _storageKey = 'openchat.chatThreads';

  final SharedPreferences _preferences;

  Future<List<ChatThread>> loadThreads() async {
    final String? rawValue = _preferences.getString(_storageKey);
    if (rawValue == null || rawValue.isEmpty) {
      return <ChatThread>[];
    }

    final Object? decoded = jsonDecode(rawValue);
    if (decoded is! List<dynamic>) {
      return <ChatThread>[];
    }

    final List<ChatThread> threads = decoded
        .whereType<Map<String, dynamic>>()
        .map(ChatThread.fromJson)
        .toList();

    threads.sort((ChatThread a, ChatThread b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return threads;
  }

  Future<void> saveThreads(List<ChatThread> threads) async {
    final List<Map<String, dynamic>> serialized =
        threads.map((ChatThread thread) => thread.toJson()).toList();
    await _preferences.setString(_storageKey, jsonEncode(serialized));
  }

  List<ConversationSearchResult> searchThreads({
    required List<ChatThread> threads,
    required String query,
    int maxResults = 50,
  }) {
    final String normalizedQuery = _normalizeSearchQuery(query);
    if (normalizedQuery.isEmpty) {
      return const <ConversationSearchResult>[];
    }

    final List<ConversationSearchResult> results = <ConversationSearchResult>[];

    for (final ChatThread thread in threads) {
      final int titleMatchIndex =
          thread.title.toLowerCase().indexOf(normalizedQuery);
      if (titleMatchIndex >= 0) {
        results.add(
          ConversationSearchResult(
            threadId: thread.id,
            threadTitle: thread.title,
            preview: _buildSnippet(
              source: thread.title,
              matchIndex: titleMatchIndex,
              matchLength: normalizedQuery.length,
            ),
            matchLabel: 'Title',
            updatedAt: thread.updatedAt,
            isPinned: thread.isPinned,
          ),
        );
      }

      for (final ChatMessage message in thread.messages.reversed) {
        final String messageText = message.text.trim();
        if (messageText.isEmpty) {
          continue;
        }

        final int messageMatchIndex =
            messageText.toLowerCase().indexOf(normalizedQuery);
        if (messageMatchIndex < 0) {
          continue;
        }

        results.add(
          ConversationSearchResult(
            threadId: thread.id,
            threadTitle: thread.title,
            messageId: message.id,
            preview: _buildSnippet(
              source: messageText,
              matchIndex: messageMatchIndex,
              matchLength: normalizedQuery.length,
            ),
            matchLabel: '${_roleLabel(message.role)} message',
            updatedAt: message.createdAt,
            isPinned: thread.isPinned,
          ),
        );
        if (results.length >= maxResults) {
          break;
        }
      }

      if (results.length >= maxResults) {
        break;
      }
    }

    results.sort((ConversationSearchResult a, ConversationSearchResult b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      if (a.updatedAt != b.updatedAt) {
        return b.updatedAt.compareTo(a.updatedAt);
      }
      if (a.matchesTitle != b.matchesTitle) {
        return a.matchesTitle ? -1 : 1;
      }
      return a.threadTitle.compareTo(b.threadTitle);
    });

    return results.take(maxResults).toList(growable: false);
  }

  String _normalizeSearchQuery(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  String _roleLabel(ChatRole role) {
    switch (role) {
      case ChatRole.system:
        return 'System';
      case ChatRole.user:
        return 'You';
      case ChatRole.assistant:
        return 'Assistant';
    }
  }

  String _buildSnippet({
    required String source,
    required int matchIndex,
    required int matchLength,
  }) {
    const int contextRadius = 36;
    final int start = (matchIndex - contextRadius).clamp(0, source.length);
    final int end =
        (matchIndex + matchLength + contextRadius).clamp(0, source.length);
    final String snippet = source.substring(start, end).replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
    final String prefix = start > 0 ? '…' : '';
    final String suffix = end < source.length ? '…' : '';
    return '$prefix$snippet$suffix';
  }
}
