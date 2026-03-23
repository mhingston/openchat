import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/attachment.dart';
import '../models/chat_message.dart';
import '../services/tts_service.dart';
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

    final Widget bubble = Align(
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
                              HapticFeedback.lightImpact();
                              onCopy?.call();
                              return;
                            case _MessageAction.edit:
                              onEdit?.call();
                              return;
                            case _MessageAction.fork:
                              onFork?.call();
                              return;
                            case _MessageAction.retry:
                              HapticFeedback.lightImpact();
                              onRetry?.call();
                              return;
                            case _MessageAction.delete:
                              HapticFeedback.mediumImpact();
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
                if (!message.isStreaming &&
                    message.role == ChatRole.assistant &&
                    message.text.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _InlineCopyButton(text: message.text),
                      _InlineSpeakerButton(message: message),
                    ],
                  ),
                ],
                if (message.sources.isNotEmpty && !message.isStreaming) ...<Widget>[
                  const SizedBox(height: 8),
                  Divider(height: 1, color: context.openChatPalette.border),
                  const SizedBox(height: 8),
                  _SourcesFooter(sources: message.sources),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (message.isStreaming) return bubble;

    return Slidable(
      key: ValueKey(message.id),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.22,
        children: <Widget>[
          SlidableAction(
            onPressed: (_) {
              HapticFeedback.lightImpact();
              onCopy?.call();
            },
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            icon: Icons.content_copy_rounded,
            label: 'Copy',
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              bottomLeft: Radius.circular(24),
            ),
          ),
        ],
      ),
      endActionPane: onRetry != null
          ? ActionPane(
              motion: const DrawerMotion(),
              extentRatio: 0.22,
              children: <Widget>[
                SlidableAction(
                  onPressed: (_) {
                    HapticFeedback.lightImpact();
                    onRetry?.call();
                  },
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.white,
                  icon: Icons.refresh_rounded,
                  label: 'Retry',
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
              ],
            )
          : null,
      child: bubble,
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

class _InlineCopyButton extends StatefulWidget {
  const _InlineCopyButton({required this.text});

  final String text;

  @override
  State<_InlineCopyButton> createState() => _InlineCopyButtonState();
}

class _InlineCopyButtonState extends State<_InlineCopyButton> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color color = _copied
        ? context.openChatPalette.success
        : context.openChatPalette.mutedText;

    return TextButton.icon(
      onPressed: _copy,
      icon: Icon(
        _copied ? Icons.check_rounded : Icons.content_copy_outlined,
        size: 14,
      ),
      label: Text(_copied ? 'Copied' : 'Copy'),
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    _resetTimer?.cancel();
    setState(() => _copied = true);
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }
}

class _InlineSpeakerButton extends StatelessWidget {
  const _InlineSpeakerButton({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final TtsService ttsService = context.watch<TtsService>();
    final bool isThisSpeaking = ttsService.speakingMessageId == message.id;

    return TextButton.icon(
      onPressed: () =>
          ttsService.speak(message.text, messageId: message.id),
      icon: Icon(
        isThisSpeaking
            ? Icons.stop_circle_outlined
            : Icons.volume_up_outlined,
        size: 14,
      ),
      label: Text(isThisSpeaking ? 'Stop' : 'Speak'),
      style: TextButton.styleFrom(
        foregroundColor: context.openChatPalette.mutedText,
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}

class _SourcesFooter extends StatelessWidget {
  const _SourcesFooter({required this.sources});

  final List<String> sources;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Sources',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.openChatPalette.mutedText,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
        ),
        const SizedBox(height: 4),
        ...sources.asMap().entries.map(
          (MapEntry<int, String> entry) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '[${entry.key + 1}] ',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.openChatPalette.mutedText,
                      ),
                ),
                Expanded(
                  child: SelectableText(
                    entry.value,
                    onTap: () {
                      final Uri? uri = Uri.tryParse(entry.value);
                      if (uri != null) {
                        unawaited(
                          launchUrl(uri, mode: LaunchMode.externalApplication),
                        );
                      }
                    },
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                          decorationColor:
                              Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

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
        errorBuilder: (_, __, ___) => _buildThumbnailOrFallback(context),
      ),
    );
  }

  Widget _buildThumbnailOrFallback(BuildContext context) {
    if (attachment.hasThumbnail) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image(
            image: MemoryImage(base64Decode(attachment.thumbnailBase64!)),
            height: 120,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallback(context),
          ),
        );
      } on FormatException {
        // Fall through to placeholder fallback.
      }
    }
    return _buildFallback(context);
  }

  ImageProvider<Object>? _resolveImageProvider() {
    if (attachment.hasBase64Data) {
      try {
        return MemoryImage(base64Decode(attachment.base64Data!));
      } on FormatException {
        // Fall through to next option.
      }
    }

    if (!kIsWeb && attachment.hasLocalPath) {
      return attachmentFileImageProvider(attachment.localPath!);
    }

    if (attachment.hasThumbnail) {
      try {
        return MemoryImage(base64Decode(attachment.thumbnailBase64!));
      } on FormatException {
        return null;
      }
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
