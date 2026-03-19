import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

class ChatMarkdown extends StatelessWidget {
  const ChatMarkdown({
    super.key,
    required this.data,
  });

  final String data;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final OpenChatPalette palette = context.openChatPalette;
    final List<_MarkdownSegment> segments = _splitSegments(data);

    if (segments.length == 1 && segments.first is _MarkdownTextSegment) {
      return _MarkdownText(
        data: (segments.first as _MarkdownTextSegment).text,
        theme: theme,
        palette: palette,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: segments.map((_MarkdownSegment segment) {
        if (segment is _MarkdownCodeSegment) {
          return _MarkdownCodeBlock(
            code: segment.code,
            language: _normalizeLanguageLabel(segment.language),
            palette: palette,
            colorScheme: theme.colorScheme,
            textTheme: theme.textTheme,
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _MarkdownText(
            data: (segment as _MarkdownTextSegment).text,
            theme: theme,
            palette: palette,
          ),
        );
      }).toList(),
    );
  }

  List<_MarkdownSegment> _splitSegments(String source) {
    final RegExp fencePattern = RegExp(
      r'```([^\n`]*)\n([\s\S]*?)```',
      multiLine: true,
    );
    final List<_MarkdownSegment> segments = <_MarkdownSegment>[];
    int cursor = 0;

    for (final RegExpMatch match in fencePattern.allMatches(source)) {
      if (match.start > cursor) {
        final String text = source.substring(cursor, match.start).trim();
        if (text.isNotEmpty) {
          segments.add(_MarkdownTextSegment(text));
        }
      }

      final String language = (match.group(1) ?? '').trim();
      final String code = (match.group(2) ?? '').trimRight();
      segments.add(_MarkdownCodeSegment(code: code, language: language));
      cursor = match.end;
    }

    if (cursor < source.length) {
      final String text = source.substring(cursor).trim();
      if (text.isNotEmpty) {
        segments.add(_MarkdownTextSegment(text));
      }
    }

    if (segments.isEmpty) {
      segments.add(_MarkdownTextSegment(source));
    }

    return segments;
  }

  String? _normalizeLanguageLabel(String? language) {
    if (language == null) {
      return null;
    }

    final String trimmed = language.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    return trimmed.toUpperCase();
  }
}

class _MarkdownText extends StatelessWidget {
  const _MarkdownText({
    required this.data,
    required this.theme,
    required this.palette,
  });

  final String data;
  final ThemeData theme;
  final OpenChatPalette palette;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: data,
      selectable: false,
      softLineBreak: true,
      onTapLink: (String text, String? href, String title) {
        if (href == null || href.isEmpty) return;
        final Uri? uri = Uri.tryParse(href);
        if (uri != null) {
          unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
        }
      },
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
        h1: theme.textTheme.headlineMedium?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
        h2: theme.textTheme.titleLarge?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
        h3: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
        h4: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        h5: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        h6: theme.textTheme.bodyMedium?.copyWith(
          color: palette.mutedText,
          fontWeight: FontWeight.w700,
        ),
        blockSpacing: 12,
        listBullet: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
        blockquote: theme.textTheme.bodyMedium?.copyWith(
          color: palette.mutedText,
          fontStyle: FontStyle.italic,
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        blockquoteDecoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(16),
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.primary,
              width: 3,
            ),
          ),
        ),
        code: theme.textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          color: theme.colorScheme.primary,
          backgroundColor: palette.surfaceRaised,
        ),
        codeblockPadding: EdgeInsets.zero,
        codeblockDecoration: const BoxDecoration(),
        a: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: theme.colorScheme.primary,
        ),
        tableHead: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
        ),
        tableBody: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
        tableBorder: TableBorder.all(color: palette.border),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
      ),
    );
  }
}

sealed class _MarkdownSegment {
  const _MarkdownSegment();
}

class _MarkdownTextSegment extends _MarkdownSegment {
  const _MarkdownTextSegment(this.text);

  final String text;
}

class _MarkdownCodeSegment extends _MarkdownSegment {
  const _MarkdownCodeSegment({
    required this.code,
    required this.language,
  });

  final String code;
  final String language;
}

class _MarkdownCodeBlock extends StatelessWidget {
  const _MarkdownCodeBlock({
    required this.code,
    required this.language,
    required this.palette,
    required this.colorScheme,
    required this.textTheme,
  });

  final String code;
  final String? language;
  final OpenChatPalette palette;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double minimumWidth;
        if (constraints.maxWidth.isFinite && constraints.maxWidth > 28) {
          minimumWidth = constraints.maxWidth - 28;
        } else {
          minimumWidth = 0;
        }

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  border: Border(bottom: BorderSide(color: palette.border)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                  child: Row(
                    children: <Widget>[
                      if (language != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            language!,
                            style: textTheme.labelSmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        )
                      else
                        Text(
                          'CODE',
                          style: textTheme.labelSmall?.copyWith(
                            color: palette.mutedText,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      const Spacer(),
                      _CodeBlockCopyButton(code: code),
                    ],
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(14),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: minimumWidth),
                  child: SelectableText(
                    code,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontFamily: 'monospace',
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CodeBlockCopyButton extends StatefulWidget {
  const _CodeBlockCopyButton({required this.code});

  final String code;

  @override
  State<_CodeBlockCopyButton> createState() => _CodeBlockCopyButtonState();
}

class _CodeBlockCopyButtonState extends State<_CodeBlockCopyButton> {
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
      key: const Key('markdown-code-copy-button'),
      onPressed: _copyCode,
      icon: Icon(
        _copied ? Icons.check_rounded : Icons.content_copy_outlined,
        size: 16,
      ),
      label: Text(_copied ? 'Copied' : 'Copy'),
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) {
      return;
    }

    _resetTimer?.cancel();
    setState(() => _copied = true);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Code copied.')));

    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }
}
