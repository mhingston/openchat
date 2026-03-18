import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/attachment.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';
import 'attachment_file_image_provider.dart';
import 'chat_markdown.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    this.onCopy,
    this.onRetry,
    this.onDelete,
    this.onEdit,
    this.onFork,
  });

  final ChatMessage message;
  final VoidCallback? onCopy;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onFork;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.role == ChatRole.user;
    final Alignment alignment =
        isUser ? Alignment.centerRight : Alignment.centerLeft;
    final Color bubbleColor = isUser
        ? context.openChatPalette.userBubble
        : context.openChatPalette.assistantBubble;

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: message.isError
                  ? context.openChatPalette.danger
                  : context.openChatPalette.border,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _roleLabel(message.role),
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: context.openChatPalette.mutedText,
                                  ),
                        ),
                      ),
                    ),
                    if (_actions.isNotEmpty)
                      PopupMenuButton<_MessageAction>(
                        tooltip: 'Message actions',
                        icon: const Icon(Icons.more_horiz),
                        onSelected: (_MessageAction action) {
                          switch (action) {
                            case _MessageAction.copy:
                              onCopy?.call();
                              return;
                            case _MessageAction.edit:
                              onEdit?.call();
                              return;
                            case _MessageAction.fork:
                              onFork?.call();
                              return;
                            case _MessageAction.retry:
                              onRetry?.call();
                              return;
                            case _MessageAction.delete:
                              onDelete?.call();
                              return;
                          }
                        },
                        itemBuilder: (BuildContext context) =>
                            _actions.map(((_MessageAction, String) item) {
                          final _MessageAction action = item.$1;
                          final String label = item.$2;
                          final bool isDelete = action == _MessageAction.delete;
                          final Color? actionColor =
                              isDelete ? context.openChatPalette.danger : null;
                          return PopupMenuItem<_MessageAction>(
                            value: action,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                _iconForAction(action),
                                color: actionColor,
                              ),
                              title: Text(
                                label,
                                style: actionColor == null
                                    ? null
                                    : TextStyle(color: actionColor),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
                if (message.attachments.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: message.attachments
                        .map(
                          (ChatAttachment attachment) => _AttachmentCard(
                            attachment: attachment,
                          ),
                        )
                        .toList(),
                  ),
                ],
                if (message.text.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  _MessageBody(message: message),
                ],
                if (message.isStreaming) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    message.text.trim().isEmpty ? 'Thinking…' : 'Streaming…',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.openChatPalette.mutedText,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
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

  List<(_MessageAction, String)> get _actions {
    final List<(_MessageAction, String)> actions = <(_MessageAction, String)>[];
    final bool isUserMessage = message.role == ChatRole.user;
    if (onCopy != null &&
        message.text.trim().isNotEmpty &&
        !message.isStreaming) {
      actions.add((_MessageAction.copy, 'Copy'));
    }
    if (isUserMessage && onEdit != null && !message.isStreaming) {
      actions.add((_MessageAction.edit, 'Edit'));
    }
    if (isUserMessage && onFork != null && !message.isStreaming) {
      actions.add((_MessageAction.fork, 'Fork'));
    }
    if (onRetry != null && !message.isStreaming) {
      actions.add((_MessageAction.retry, 'Retry'));
    }
    if (onDelete != null && !message.isStreaming) {
      actions.add((_MessageAction.delete, 'Delete'));
    }
    return actions;
  }

  IconData _iconForAction(_MessageAction action) {
    switch (action) {
      case _MessageAction.copy:
        return Icons.content_copy_outlined;
      case _MessageAction.edit:
        return Icons.edit_outlined;
      case _MessageAction.fork:
        return Icons.call_split_rounded;
      case _MessageAction.retry:
        return Icons.refresh_rounded;
      case _MessageAction.delete:
        return Icons.delete_outline;
    }
  }
}

enum _MessageAction { copy, edit, fork, retry, delete }

class _MessageBody extends StatelessWidget {
  const _MessageBody({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.role == ChatRole.assistant) {
      return ChatMarkdown(data: message.text);
    }

    return SelectableText(message.text);
  }
}

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.openChatPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.openChatPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (attachment.kind == AttachmentKind.image) ...<Widget>[
            _AttachmentImage(attachment: attachment),
            const SizedBox(height: 10),
          ] else
            Icon(
              Icons.insert_drive_file_outlined,
              color: context.openChatPalette.mutedText,
            ),
          Text(
            attachment.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            attachment.previewText.isEmpty
                ? attachment.mimeType
                : attachment.previewText,
            maxLines: attachment.kind == AttachmentKind.image ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.openChatPalette.mutedText,
                ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentImage extends StatelessWidget {
  const _AttachmentImage({required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final ImageProvider<Object>? imageProvider = _resolveImageProvider();
    if (imageProvider == null) {
      return _buildFallback(context);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image(
        image: imageProvider,
        height: 120,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallback(context),
      ),
    );
  }

  ImageProvider<Object>? _resolveImageProvider() {
    if (attachment.hasBase64Data) {
      try {
        return MemoryImage(base64Decode(attachment.base64Data!));
      } on FormatException {
        return null;
      }
    }

    if (!kIsWeb && attachment.hasLocalPath) {
      return attachmentFileImageProvider(attachment.localPath!);
    }

    return null;
  }

  Widget _buildFallback(BuildContext context) {
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.openChatPalette.composerBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        color: context.openChatPalette.mutedText,
      ),
    );
  }
}
