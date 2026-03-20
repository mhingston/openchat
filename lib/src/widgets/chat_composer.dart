import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/attachment.dart';
import '../services/attachment_store.dart';
import '../services/voice_input_service.dart';
import '../theme/app_theme.dart';
import '../utils/keyboard_shortcuts.dart';

const String _kWebSearchEnabledKey = 'web_search_enabled';

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.enabled,
    required this.busy,
    required this.onSend,
    this.draftText,
    this.draftVersion = 0,
    this.editingLabel,
    this.onCancelEdit,
    this.voiceService,
  });

  final bool enabled;
  final bool busy;
  final Future<bool> Function(
    String text,
    List<ChatAttachment> attachments,
    bool useWebSearch,
  ) onSend;
  final String? draftText;
  final int draftVersion;
  final String? editingLabel;
  final VoidCallback? onCancelEdit;

  /// Optional voice input service. When non-null and available, a microphone
  /// button is shown when the text field is empty. Pass [null] to disable the
  /// feature entirely (e.g. in tests or on unsupported platforms).
  final VoiceInputService? voiceService;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final TextEditingController _textController = TextEditingController();
  final List<ChatAttachment> _attachments = <ChatAttachment>[];
  AttachmentStore? _attachmentStore;
  Future<AttachmentStore>? _attachmentStoreFuture;
  final FocusNode _focusNode = FocusNode();
  bool _attaching = false;
  bool _webSearchEnabled = false;
  late int _appliedDraftVersion;

  @override
  void initState() {
    super.initState();
    _appliedDraftVersion = widget.draftVersion;
    _applyExternalDraft(widget.draftText ?? '');
    widget.voiceService?.addListener(_onVoiceServiceChanged);
    unawaited(_loadWebSearchPreference());
  }

  @override
  void didUpdateWidget(covariant ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.draftVersion != _appliedDraftVersion) {
      _appliedDraftVersion = widget.draftVersion;
      _applyExternalDraft(widget.draftText ?? '');
    }
    if (widget.voiceService != oldWidget.voiceService) {
      oldWidget.voiceService?.removeListener(_onVoiceServiceChanged);
      widget.voiceService?.addListener(_onVoiceServiceChanged);
    }
  }

  @override
  void dispose() {
    widget.voiceService?.removeListener(_onVoiceServiceChanged);
    for (final ChatAttachment attachment in _attachments) {
      unawaited(_attachmentStore?.deleteAttachment(attachment) ??
          Future<void>.value());
    }
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _onVoiceServiceChanged() {
    final VoiceInputService? service = widget.voiceService;
    if (service == null) return;

    // Push partial/final transcription into the text field in real time.
    final String transcript = service.state.transcribedText;
    if (transcript.isNotEmpty && _textController.text != transcript) {
      _textController
        ..text = transcript
        ..selection = TextSelection.collapsed(offset: transcript.length);
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bool canSend = widget.enabled &&
        !_attaching &&
        (_textController.text.trim().isNotEmpty || _attachments.isNotEmpty);
    final bool canClear = widget.enabled &&
        !_attaching &&
        (_textController.text.trim().isNotEmpty || _attachments.isNotEmpty);
    final bool isDesktopOrWeb = OpenChatKeyboardShortcuts.isDesktopOrWeb;

    final Widget child = DecoratedBox(
      decoration: BoxDecoration(
        color: context.openChatPalette.composerBackground,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: context.openChatPalette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool compact = constraints.maxWidth < 430;
            final bool ultraCompact = constraints.maxWidth < 360;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_buildVoiceStatusBanner(context)
                    case final Widget banner) ...<Widget>[
                  banner,
                  const SizedBox(height: 12),
                ],
                if (widget.editingLabel != null) ...<Widget>[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    decoration: BoxDecoration(
                      color: context.openChatPalette.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: context.openChatPalette.border),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: context.openChatPalette.mutedText,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.editingLabel!,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: context.openChatPalette.mutedText,
                                    ),
                          ),
                        ),
                        TextButton(
                          onPressed: widget.onCancelEdit,
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _attachments
                            .map(
                              (ChatAttachment attachment) => InputChip(
                                avatar: Icon(
                                  attachment.kind == AttachmentKind.image
                                      ? Icons.image_outlined
                                      : Icons.insert_drive_file_outlined,
                                  size: 18,
                                ),
                                label: Text(attachment.name),
                                onDeleted: widget.enabled
                                    ? () => _removeAttachment(attachment)
                                    : null,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                _buildComposerInputSurface(
                  context: context,
                  canSend: canSend,
                  canClear: canClear,
                  isDesktopOrWeb: isDesktopOrWeb,
                  compact: compact,
                  ultraCompact: ultraCompact,
                ),
              ],
            );
          },
        ),
      ),
    );

    if (!isDesktopOrWeb) {
      return child;
    }

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        OpenChatKeyboardShortcuts.primaryActivator(LogicalKeyboardKey.enter):
            const SendMessageIntent(),
        OpenChatKeyboardShortcuts.escapeActivator: const ClearDraftIntent(),
        OpenChatKeyboardShortcuts.primaryActivator(LogicalKeyboardKey.slash):
            const ToggleWebSearchIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          SendMessageIntent: CallbackAction<SendMessageIntent>(
            onInvoke: (SendMessageIntent intent) {
              if (canSend) {
                unawaited(_submit());
              }
              return null;
            },
          ),
          ClearDraftIntent: CallbackAction<ClearDraftIntent>(
            onInvoke: (ClearDraftIntent intent) {
              if (canClear) {
                _clearDraft();
              }
              return null;
            },
          ),
          ToggleWebSearchIntent: CallbackAction<ToggleWebSearchIntent>(
            onInvoke: (ToggleWebSearchIntent intent) {
              _toggleWebSearch();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }

  Widget _buildComposerInputSurface({
    required BuildContext context,
    required bool canSend,
    required bool canClear,
    required bool isDesktopOrWeb,
    required bool compact,
    required bool ultraCompact,
  }) {
    final Widget trailingButton = _buildTrailingButton(
      context: context,
      canSend: canSend,
      isDesktopOrWeb: isDesktopOrWeb,
      compact: compact,
    );

    final List<Widget> leadingActions = <Widget>[
      _buildAttachmentButton(compact: compact, ultraCompact: ultraCompact),
      _buildWebSearchButton(
        context,
        compact: compact,
        ultraCompact: ultraCompact,
      ),
      _buildClearDraftButton(
        canClear: canClear,
        isDesktopOrWeb: isDesktopOrWeb,
        compact: compact,
        ultraCompact: ultraCompact,
      ),
    ];

    return Column(
      key: compact ? const Key('chat-composer-compact-layout') : null,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildTextField(
          isDesktopOrWeb: isDesktopOrWeb,
          compact: compact,
          ultraCompact: ultraCompact,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _joinWithGap(
                    leadingActions,
                    gap: compact ? 6 : 8,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            trailingButton,
          ],
        ),
      ],
    );
  }

  Widget _buildTextField({
    required bool isDesktopOrWeb,
    required bool compact,
    bool ultraCompact = false,
  }) {
    return TextField(
      controller: _textController,
      focusNode: _focusNode,
      enabled: widget.enabled,
      keyboardType: TextInputType.multiline,
      minLines: 1,
      maxLines: isDesktopOrWeb ? 10 : (compact ? (ultraCompact ? 3 : 4) : 6),
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.newline,
      decoration: InputDecoration(
        hintText: compact ? 'Message' : 'Message OpenChat',
        alignLabelWithHint: isDesktopOrWeb || compact,
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: compact
            ? EdgeInsets.symmetric(
                horizontal: 4,
                vertical: ultraCompact ? 8 : 10,
              )
            : const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      ),
      textAlignVertical:
          isDesktopOrWeb ? TextAlignVertical.top : TextAlignVertical.center,
      onChanged: (String value) {
        if (widget.voiceService?.isListening == true) {
          unawaited(widget.voiceService!.cancelListening());
        }
        setState(() {});
      },
    );
  }

  Widget _buildAttachmentButton({
    bool compact = false,
    bool ultraCompact = false,
  }) {
    final double buttonSize = ultraCompact ? 40 : (compact ? 44 : 48);
    final double iconSize = ultraCompact ? 20 : (compact ? 22 : 24);
    return SizedBox(
      height: buttonSize,
      width: buttonSize,
      child: IconButton(
        style: _inlineActionStyle(context),
        onPressed: widget.enabled && !_attaching ? _addAttachment : null,
        icon: _attaching
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                Icons.attach_file_rounded,
                size: iconSize,
              ),
        tooltip: 'Add attachment',
      ),
    );
  }

  Widget _buildWebSearchButton(
    BuildContext context, {
    bool compact = false,
    bool ultraCompact = false,
  }) {
    final double buttonSize = ultraCompact ? 40 : (compact ? 44 : 48);
    final double iconSize = ultraCompact ? 20 : (compact ? 22 : 24);
    return SizedBox(
      height: buttonSize,
      width: buttonSize,
      child: IconButton(
        key: const Key('chat-composer-web-search-toggle'),
        style: _webSearchEnabled
            ? _inlineActionStyle(
                context,
                highlighted: true,
              )
            : _inlineActionStyle(context),
        onPressed: widget.enabled ? _toggleWebSearch : null,
        tooltip: _webSearchEnabled ? 'Web search on' : 'Use web search',
        icon: Icon(
          _webSearchEnabled ? Icons.public_rounded : Icons.public_off_rounded,
          size: iconSize,
        ),
      ),
    );
  }

  Widget _buildClearDraftButton({
    required bool canClear,
    required bool isDesktopOrWeb,
    bool compact = false,
    bool ultraCompact = false,
  }) {
    final double buttonSize = ultraCompact ? 40 : (compact ? 44 : 48);
    final double iconSize = ultraCompact ? 20 : (compact ? 22 : 24);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: canClear
          ? SizedBox(
              key: const ValueKey<String>('clear-draft'),
              height: buttonSize,
              width: buttonSize,
              child: IconButton(
                key: const Key('chat-composer-clear-draft'),
                style: _inlineActionStyle(context),
                onPressed: _clearDraft,
                icon: Icon(
                  Icons.clear_rounded,
                  size: iconSize,
                ),
                tooltip: isDesktopOrWeb ? 'Clear draft (Esc)' : 'Clear draft',
              ),
            )
          : SizedBox(
              width: compact ? 0 : 0,
              height: compact ? 0 : 0,
            ),
    );
  }

  /// Builds the trailing action button.
  ///
  /// Shows the send button when there is content to send, or a mic button when
  /// the text field is empty and a [VoiceInputService] is available.
  Widget _buildTrailingButton({
    required BuildContext context,
    required bool canSend,
    required bool isDesktopOrWeb,
    bool compact = false,
  }) {
    final VoiceInputService? voice = widget.voiceService;
    final bool voiceAvailable = voice != null && voice.isAvailable;
    final bool isListening = voice?.isListening ?? false;
    final bool textEmpty =
        _textController.text.trim().isEmpty && _attachments.isEmpty;
    final double buttonSize = compact ? 44 : 48;

    // Keep the stop button visible for the full listening session, even once
    // partial transcription has populated the draft.
    if ((isListening || (voiceAvailable && textEmpty)) && !widget.busy) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: SizedBox(
          key: ValueKey<bool>(isListening),
          height: buttonSize,
          width: buttonSize,
          child: Tooltip(
            message: isListening ? 'Stop listening' : 'Speak',
            child: IconButton(
              key: const Key('chat-composer-mic-button'),
              onPressed: widget.enabled ? _toggleVoice : null,
              style: isListening
                  ? _inlineActionStyle(context, danger: true)
                  : _inlineActionStyle(context),
              icon: Icon(
                isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
              ),
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: isDesktopOrWeb
          ? 'Send (${OpenChatKeyboardShortcuts.primaryModifierLabel}+Enter)'
          : 'Send',
      child: SizedBox(
        height: buttonSize,
        width: buttonSize,
        child: FilledButton(
          key: const Key('chat-composer-send-button'),
          onPressed: canSend ? _submit : null,
          style: FilledButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: widget.busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.arrow_upward_rounded),
        ),
      ),
    );
  }

  List<Widget> _joinWithGap(List<Widget> widgets, {required double gap}) {
    final List<Widget> joined = <Widget>[];
    for (int index = 0; index < widgets.length; index += 1) {
      final Widget widget = widgets[index];
      if (widget is SizedBox && widget.height == 0 && widget.width == 0) {
        continue;
      }
      if (joined.isNotEmpty) {
        joined.add(SizedBox(width: gap));
      }
      joined.add(widget);
    }
    return joined;
  }

  ButtonStyle _inlineActionStyle(
    BuildContext context, {
    bool highlighted = false,
    bool danger = false,
  }) {
    final Color foregroundColor = danger
        ? Theme.of(context).colorScheme.error
        : highlighted
            ? Theme.of(context).colorScheme.primary
            : context.openChatPalette.mutedText;
    final Color backgroundColor = danger
        ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4)
        : highlighted
            ? Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.45)
            : context.openChatPalette.surface;

    return IconButton.styleFrom(
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Widget? _buildVoiceStatusBanner(BuildContext context) {
    final VoiceInputService? voice = widget.voiceService;
    if (voice == null) {
      return null;
    }

    final VoiceInputState state = voice.state;
    if (state.isListening) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .errorContainer
              .withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.graphic_eq_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Listening… click the mic again to stop and insert your transcript.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    if (state.hasError && (state.errorMessage?.trim().isNotEmpty ?? false)) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .errorContainer
              .withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.mic_off_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                state.errorMessage!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    return null;
  }

  Future<void> _toggleVoice() async {
    final VoiceInputService? voice = widget.voiceService;
    if (voice == null) return;

    if (voice.isListening) {
      await voice.stopListening();
    } else {
      final bool started = await voice.startListening();
      if (!started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice input is not available.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _addAttachment() async {
    final _AttachmentChoice? choice =
        await showModalBottomSheet<_AttachmentChoice>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => const _AttachmentChooserSheet(),
    );

    if (choice == null || !mounted) {
      return;
    }

    setState(() {
      _attaching = true;
    });

    try {
      final AttachmentStore store = await _ensureAttachmentStore();
      final ChatAttachment? attachment = switch (choice) {
        _AttachmentChoice.camera => await store.pickImageFromCamera(),
        _AttachmentChoice.photos => await store.pickImageFromGallery(),
        _AttachmentChoice.files => await store.pickFile(),
      };
      if (attachment == null || !mounted) {
        return;
      }

      setState(() {
        _attachments.add(attachment);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _attaching = false;
        });
      }
    }
  }

  Future<void> _removeAttachment(ChatAttachment attachment) async {
    setState(() {
      _attachments
          .removeWhere((ChatAttachment item) => item.id == attachment.id);
    });

    try {
      await _attachmentStore?.deleteAttachment(attachment);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error);
    }
  }

  Future<void> _submit() async {
    final String text = _textController.text;
    final List<ChatAttachment> attachments =
        List<ChatAttachment>.from(_attachments);
    final bool sent = await widget.onSend(text, attachments, _webSearchEnabled);
    if (!mounted || !sent) {
      return;
    }

    // Ownership of attachment files transfers to the saved message — do NOT
    // delete the files here. Only clear the in-memory list.
    _clearDraftAfterSend();
  }

  /// Clears the composer after a successful send WITHOUT deleting attachment
  /// files (they are now owned by the saved message).
  void _clearDraftAfterSend() {
    if (widget.voiceService?.isListening == true) {
      unawaited(widget.voiceService!.cancelListening());
    }
    setState(() {
      _textController.clear();
      _attachments.clear();
    });
    widget.onCancelEdit?.call();
  }

  void _clearDraft() {
    // Cancel any active voice session when the draft is explicitly cleared.
    if (widget.voiceService?.isListening == true) {
      unawaited(widget.voiceService!.cancelListening());
    }
    _clearDraftInternal();
    widget.onCancelEdit?.call();
  }

  Future<void> _loadWebSearchPreference() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _webSearchEnabled = prefs.getBool(_kWebSearchEnabledKey) ?? false;
    });
  }

  void _toggleWebSearch() {
    final bool newValue = !_webSearchEnabled;
    setState(() {
      _webSearchEnabled = newValue;
    });
    unawaited(SharedPreferences.getInstance().then(
      (SharedPreferences prefs) => prefs.setBool(_kWebSearchEnabledKey, newValue),
    ));
  }

  void _clearDraftInternal() {
    final List<ChatAttachment> attachmentsToDelete =
        List<ChatAttachment>.from(_attachments);
    setState(() {
      _textController.clear();
      _attachments.clear();
    });
    for (final ChatAttachment attachment in attachmentsToDelete) {
      unawaited(
        _attachmentStore?.deleteAttachment(attachment) ?? Future<void>.value(),
      );
    }
  }

  void _applyExternalDraft(String text) {
    final List<ChatAttachment> attachmentsToDelete =
        List<ChatAttachment>.from(_attachments);
    _textController
      ..text = text
      ..selection = TextSelection.collapsed(offset: text.length);
    _attachments.clear();
    for (final ChatAttachment attachment in attachmentsToDelete) {
      unawaited(
        _attachmentStore?.deleteAttachment(attachment) ?? Future<void>.value(),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        setState(() {});
      }
    });
  }

  Future<AttachmentStore> _ensureAttachmentStore() {
    final AttachmentStore? existingStore = _attachmentStore;
    if (existingStore != null) {
      return Future<AttachmentStore>.value(existingStore);
    }

    return _attachmentStoreFuture ??= AttachmentStore.create().then(
      (AttachmentStore store) {
        _attachmentStore = store;
        return store;
      },
    );
  }

  void _showError(Object error) {
    final String message = error
        .toString()
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceFirst(RegExp(r'^Bad state:\s*'), '')
        .trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.isEmpty ? 'Attachment failed.' : message)),
    );
  }
}

enum _AttachmentChoice { camera, photos, files }

class _AttachmentChooserSheet extends StatelessWidget {
  const _AttachmentChooserSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Add attachment',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a source for your message attachment.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.openChatPalette.mutedText,
                  ),
            ),
            const SizedBox(height: 16),
            _AttachmentOptionTile(
              icon: Icons.photo_camera_outlined,
              label: 'Camera',
              subtitle: 'Capture a new image where supported',
              onTap: () => Navigator.of(context).pop(_AttachmentChoice.camera),
            ),
            _AttachmentOptionTile(
              icon: Icons.photo_library_outlined,
              label: 'Photos',
              subtitle: 'Pick an image from your library',
              onTap: () => Navigator.of(context).pop(_AttachmentChoice.photos),
            ),
            _AttachmentOptionTile(
              icon: Icons.folder_open_outlined,
              label: 'Files',
              subtitle: 'Attach a document or other file',
              onTap: () => Navigator.of(context).pop(_AttachmentChoice.files),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentOptionTile extends StatelessWidget {
  const _AttachmentOptionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: context.openChatPalette.surfaceRaised,
        child: Icon(icon, color: context.openChatPalette.accent),
      ),
      title: Text(label),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}
