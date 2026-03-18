import 'package:flutter/material.dart';

import '../models/conversation_search_result.dart';
import '../theme/app_theme.dart';

class ConversationSearchSheet extends StatefulWidget {
  const ConversationSearchSheet({
    super.key,
    required this.onSearch,
    required this.onResultSelected,
  });

  final List<ConversationSearchResult> Function(String query) onSearch;
  final Future<void> Function(ConversationSearchResult result) onResultSelected;

  @override
  State<ConversationSearchSheet> createState() =>
      _ConversationSearchSheetState();
}

class _ConversationSearchSheetState extends State<ConversationSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<ConversationSearchResult> _results = const <ConversationSearchResult>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.openChatPalette.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: context.openChatPalette.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Search conversations',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close search',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                focusNode: _focusNode,
                textInputAction: TextInputAction.search,
                onChanged: (String value) {
                  setState(() {
                    _results = widget.onSearch(value);
                  });
                },
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search titles and messages',
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _results = const <ConversationSearchResult>[];
                            });
                          },
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(child: _buildBody(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final String trimmedQuery = _searchController.text.trim();

    if (trimmedQuery.isEmpty) {
      return const _EmptySearchState(
        icon: Icons.travel_explore_outlined,
        title: 'Search your saved chats',
        message: 'Find conversations by title or message text.',
      );
    }

    if (_results.isEmpty) {
      return const _EmptySearchState(
        icon: Icons.search_off_rounded,
        title: 'No matches found',
        message: 'Try a different phrase or fewer keywords.',
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final ConversationSearchResult result = _results[index];
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            onTap: () async {
              await widget.onResultSelected(result);
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            title: Row(
              children: <Widget>[
                if (result.isPinned) ...<Widget>[
                  Icon(
                    Icons.push_pin_rounded,
                    size: 16,
                    color: context.openChatPalette.accent,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    result.threadTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    result.matchLabel,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: context.openChatPalette.mutedText,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    result.preview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
          ),
        );
      },
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 40,
              color: context.openChatPalette.mutedText,
            ),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.openChatPalette.mutedText,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
