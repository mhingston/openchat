import 'attachment.dart';

enum ChatRole { system, user, assistant }

ChatRole chatRoleFromValue(String value) {
  return ChatRole.values.firstWhere(
    (ChatRole role) => role.name == value,
    orElse: () => ChatRole.user,
  );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    required this.attachments,
    required this.isStreaming,
    required this.isError,
    this.sources = const <String>[],
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawAttachments =
        json['attachments'] as List<dynamic>? ?? <dynamic>[];
    final String? legacyErrorText = json['errorText'] as String?;
    final String text = json['text'] as String? ?? '';
    final List<String> sources = (json['sources'] as List<dynamic>?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];

    return ChatMessage(
      id: json['id'] as String? ?? '',
      role: chatRoleFromValue(json['role'] as String? ?? 'user'),
      text:
          text.isEmpty && legacyErrorText != null && legacyErrorText.isNotEmpty
              ? legacyErrorText
              : text,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      attachments: rawAttachments
          .whereType<Map<String, dynamic>>()
          .map(ChatAttachment.fromJson)
          .toList(),
      isStreaming: json['isStreaming'] as bool? ?? false,
      isError: json['isError'] as bool? ??
          (legacyErrorText != null && legacyErrorText.isNotEmpty),
      sources: sources,
    );
  }

  final String id;
  final ChatRole role;
  final String text;
  final DateTime createdAt;
  final List<ChatAttachment> attachments;
  final bool isStreaming;
  final bool isError;
  final List<String> sources;

  bool get hasContent => text.trim().isNotEmpty || attachments.isNotEmpty;

  ChatMessage copyWith({
    String? id,
    ChatRole? role,
    String? text,
    DateTime? createdAt,
    List<ChatAttachment>? attachments,
    bool? isStreaming,
    bool? isError,
    List<String>? sources,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      attachments: attachments ?? this.attachments,
      isStreaming: isStreaming ?? this.isStreaming,
      isError: isError ?? this.isError,
      sources: sources ?? this.sources,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'role': role.name,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'attachments':
          attachments.map((ChatAttachment item) => item.toJson()).toList(),
      'isStreaming': isStreaming,
      'isError': isError,
      if (sources.isNotEmpty) 'sources': sources,
    };
  }
}
