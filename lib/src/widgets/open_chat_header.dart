import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/keyboard_shortcuts.dart';

class OpenChatHeader extends StatelessWidget {
  const OpenChatHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onMenuPressed,
    required this.onExportPressed,
    required this.onSettingsPressed,
  });

  final String title;
  final String subtitle;
  final VoidCallback onMenuPressed;
  final VoidCallback? onExportPressed;
  final VoidCallback onSettingsPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.openChatPalette.headerBackground,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.openChatPalette.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool compact = constraints.maxWidth < 430;
              final bool ultraCompact = constraints.maxWidth < 360;
              final List<Widget> actions = <Widget>[
                _HeaderActionButton(
                  actionKey: const Key('header-export-current-button'),
                  onPressed: onExportPressed,
                  icon: Icons.ios_share_outlined,
                  tooltip: 'Export current chat',
                  compact: compact,
                  ultraCompact: ultraCompact,
                ),
                _HeaderActionButton(
                  onPressed: onSettingsPressed,
                  icon: Icons.tune,
                  tooltip: OpenChatKeyboardShortcuts.isDesktopOrWeb
                      ? 'Settings (${OpenChatKeyboardShortcuts.primaryModifierLabel}+,)'
                      : 'Settings',
                  compact: compact,
                  ultraCompact: ultraCompact,
                ),
              ];

              if (!compact) {
                return Row(
                  children: <Widget>[
                    IconButton(
                      onPressed: onMenuPressed,
                      icon: const Icon(Icons.menu_rounded),
                      tooltip: 'Open conversations',
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _HeaderTitleBlock(
                        title: title,
                        subtitle: subtitle,
                        compact: false,
                        ultraCompact: false,
                      ),
                    ),
                    ..._joinWithGap(actions, gap: 8),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  IconButton(
                    onPressed: onMenuPressed,
                    icon: const Icon(Icons.menu_rounded),
                    tooltip: 'Open conversations',
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _HeaderTitleBlock(
                        title: title,
                        subtitle: subtitle,
                        compact: true,
                        ultraCompact: ultraCompact,
                      ),
                    ),
                  ),
                  Row(
                    key: const Key('openchat-header-compact-actions'),
                    mainAxisSize: MainAxisSize.min,
                    children: _joinWithGap(actions, gap: 6),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _joinWithGap(List<Widget> widgets, {required double gap}) {
    if (widgets.isEmpty) {
      return const <Widget>[];
    }

    final List<Widget> joined = <Widget>[];
    for (int index = 0; index < widgets.length; index += 1) {
      if (index > 0) {
        joined.add(SizedBox(width: gap));
      }
      joined.add(widgets[index]);
    }
    return joined;
  }
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    this.actionKey,
    required this.onPressed,
    required this.icon,
    required this.tooltip,
    required this.compact,
    required this.ultraCompact,
  });

  final Key? actionKey;
  final VoidCallback? onPressed;
  final IconData icon;
  final String tooltip;
  final bool compact;
  final bool ultraCompact;

  @override
  Widget build(BuildContext context) {
    final double buttonSize = ultraCompact ? 40 : (compact ? 44 : 48);
    final double iconSize = ultraCompact ? 20 : (compact ? 22 : 24);
    return SizedBox(
      height: buttonSize,
      width: buttonSize,
      child: IconButton(
        key: actionKey,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: iconSize),
        tooltip: tooltip,
      ),
    );
  }
}

class _HeaderTitleBlock extends StatelessWidget {
  const _HeaderTitleBlock({
    required this.title,
    required this.subtitle,
    required this.compact,
    required this.ultraCompact,
  });

  final String title;
  final String subtitle;
  final bool compact;
  final bool ultraCompact;

  @override
  Widget build(BuildContext context) {
    final double titleFontSize = ultraCompact ? 18 : (compact ? 20 : 28);
    final TextStyle? titleStyle = Theme.of(context).textTheme.titleLarge;
    final String trimmedSubtitle = subtitle.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          softWrap: false,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleStyle?.copyWith(fontSize: titleFontSize),
        ),
        if (trimmedSubtitle.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            trimmedSubtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.openChatPalette.mutedText,
                ),
          ),
        ],
      ],
    );
  }
}
