class ConversationSearchResult {
  const ConversationSearchResult({
    required this.threadId,
    required this.threadTitle,
    required this.preview,
    required this.matchLabel,
    required this.updatedAt,
    required this.isPinned,
    this.messageId,
  });

  final String threadId;
  final String threadTitle;
  final String preview;
  final String matchLabel;
  final DateTime updatedAt;
  final bool isPinned;
  final String? messageId;

  bool get matchesTitle => messageId == null;
}
