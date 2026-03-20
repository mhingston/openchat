import 'chat_message.dart';

class ChatThread {
  const ChatThread({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
    this.isPinned = false,
    this.promptTemplateId,
    this.promptTemplateName,
    this.systemPromptOverride,
    this.modelOverride,
    this.temperatureOverride,
  });

  factory ChatThread.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawMessages =
        json['messages'] as List<dynamic>? ?? <dynamic>[];

    return ChatThread(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'New chat',
      messages: rawMessages
          .whereType<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      isPinned: json['isPinned'] as bool? ?? false,
      promptTemplateId: json['promptTemplateId'] as String?,
      promptTemplateName: json['promptTemplateName'] as String?,
      systemPromptOverride: json['systemPromptOverride'] as String?,
      modelOverride: json['modelOverride'] as String?,
      temperatureOverride: (json['temperatureOverride'] as num?)?.toDouble(),
    );
  }

  final String id;
  final String title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isPinned;
  final String? promptTemplateId;
  final String? promptTemplateName;
  final String? systemPromptOverride;
  final String? modelOverride;
  final double? temperatureOverride;

  String get previewText {
    if (messages.isEmpty) {
      return 'No messages yet';
    }

    final ChatMessage latest = messages.last;
    if (latest.text.trim().isNotEmpty) {
      return latest.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    }
    if (latest.attachments.isNotEmpty) {
      return '${latest.attachments.length} attachment(s)';
    }
    return 'Empty reply';
  }

  ChatThread copyWith({
    String? id,
    String? title,
    List<ChatMessage>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isPinned,
    String? promptTemplateId,
    String? promptTemplateName,
    String? systemPromptOverride,
    String? modelOverride,
    double? temperatureOverride,
  }) {
    return ChatThread(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
      promptTemplateId: promptTemplateId ?? this.promptTemplateId,
      promptTemplateName: promptTemplateName ?? this.promptTemplateName,
      systemPromptOverride: systemPromptOverride ?? this.systemPromptOverride,
      modelOverride: modelOverride ?? this.modelOverride,
      temperatureOverride: temperatureOverride ?? this.temperatureOverride,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'messages':
          messages.map((ChatMessage message) => message.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isPinned': isPinned,
      if (promptTemplateId != null) 'promptTemplateId': promptTemplateId,
      if (promptTemplateName != null) 'promptTemplateName': promptTemplateName,
      if (systemPromptOverride != null)
        'systemPromptOverride': systemPromptOverride,
      if (modelOverride != null) 'modelOverride': modelOverride,
      if (temperatureOverride != null) 'temperatureOverride': temperatureOverride,
    };
  }
}
