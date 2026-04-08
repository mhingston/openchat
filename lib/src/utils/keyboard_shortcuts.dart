import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class OpenChatKeyboardShortcuts {
  const OpenChatKeyboardShortcuts._();

  static bool? debugIsDesktopOrWebOverride;
  static bool? debugIsApplePlatformOverride;

  static bool get isDesktopOrWeb {
    final bool? override = debugIsDesktopOrWebOverride;
    if (override != null) {
      return override;
    }

    if (kIsWeb) {
      return true;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  static bool get isApplePlatform {
    final bool? override = debugIsApplePlatformOverride;
    if (override != null) {
      return override;
    }

    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static String get primaryModifierLabel {
    return isApplePlatform ? '⌘' : 'Ctrl';
  }

  static SingleActivator primaryActivator(
    LogicalKeyboardKey key, {
    bool shift = false,
    bool alt = false,
  }) {
    return SingleActivator(
      key,
      meta: isApplePlatform,
      control: !isApplePlatform,
      shift: shift,
      alt: alt,
    );
  }

  static const SingleActivator escapeActivator =
      SingleActivator(LogicalKeyboardKey.escape);

  static SingleActivator get newChatActivator =>
      primaryActivator(LogicalKeyboardKey.keyN);

  static SingleActivator get alternateNewChatActivator =>
      primaryActivator(LogicalKeyboardKey.keyK);

  static SingleActivator get openSettingsActivator =>
      primaryActivator(LogicalKeyboardKey.comma);

  static SingleActivator get focusConversationSearchActivator =>
      primaryActivator(LogicalKeyboardKey.keyF);

  static SingleActivator get previousConversationActivator =>
      primaryActivator(LogicalKeyboardKey.bracketLeft);

  static SingleActivator get nextConversationActivator =>
      primaryActivator(LogicalKeyboardKey.bracketRight);

  static SingleActivator get sendMessageActivator =>
      primaryActivator(LogicalKeyboardKey.enter);

  static SingleActivator get toggleWebSearchActivator =>
      primaryActivator(LogicalKeyboardKey.slash);

  static Map<ShortcutActivator, Intent> homeScreenBindings() {
    return <ShortcutActivator, Intent>{
      newChatActivator: const NewChatIntent(),
      alternateNewChatActivator: const NewChatIntent(),
      openSettingsActivator: const OpenSettingsIntent(),
      focusConversationSearchActivator: const FocusConversationSearchIntent(),
      previousConversationActivator: const SelectPreviousConversationIntent(),
      nextConversationActivator: const SelectNextConversationIntent(),
    };
  }

  static Map<ShortcutActivator, Intent> composerBindings() {
    return <ShortcutActivator, Intent>{
      sendMessageActivator: const SendMessageIntent(),
      escapeActivator: const ClearDraftIntent(),
      toggleWebSearchActivator: const ToggleWebSearchIntent(),
    };
  }

  static List<KeyboardShortcutHelpSection> get helpSections {
    return <KeyboardShortcutHelpSection>[
      KeyboardShortcutHelpSection(
        title: 'Navigation',
        entries: <KeyboardShortcutHelpEntry>[
          KeyboardShortcutHelpEntry(
            label: 'New chat',
            activators: <SingleActivator>[
              newChatActivator,
              alternateNewChatActivator,
            ],
          ),
          KeyboardShortcutHelpEntry(
            label: 'Search conversations',
            activators: <SingleActivator>[focusConversationSearchActivator],
          ),
          KeyboardShortcutHelpEntry(
            label: 'Settings',
            activators: <SingleActivator>[openSettingsActivator],
          ),
          KeyboardShortcutHelpEntry(
            label: 'Previous conversation',
            activators: <SingleActivator>[previousConversationActivator],
          ),
          KeyboardShortcutHelpEntry(
            label: 'Next conversation',
            activators: <SingleActivator>[nextConversationActivator],
          ),
        ],
      ),
      KeyboardShortcutHelpSection(
        title: 'Composer',
        entries: <KeyboardShortcutHelpEntry>[
          KeyboardShortcutHelpEntry(
            label: 'Send message',
            activators: <SingleActivator>[sendMessageActivator],
          ),
          KeyboardShortcutHelpEntry(
            label: 'Toggle web search',
            activators: <SingleActivator>[toggleWebSearchActivator],
          ),
          const KeyboardShortcutHelpEntry(
            label: 'Clear draft',
            activators: <SingleActivator>[escapeActivator],
          ),
        ],
      ),
    ];
  }

  static String formatShortcutLabel(SingleActivator activator) {
    final List<String> modifiers = <String>[
      if (activator.meta || activator.control) primaryModifierLabel,
      if (activator.alt) isApplePlatform ? '⌥' : 'Alt',
      if (activator.shift) isApplePlatform ? '⇧' : 'Shift',
    ];
    final String keyLabel = _normalizedKeyLabel(activator.trigger);
    if (modifiers.isEmpty) {
      return keyLabel;
    }
    if (isApplePlatform) {
      return '${modifiers.join()}$keyLabel';
    }
    return '${modifiers.join('+')}+$keyLabel';
  }

  static String formatShortcutLabels(Iterable<SingleActivator> activators) {
    return activators.map(formatShortcutLabel).join(' / ');
  }

  static String _normalizedKeyLabel(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.enter) {
      return 'Enter';
    }
    if (key == LogicalKeyboardKey.escape) {
      return 'Esc';
    }
    final String label = key.keyLabel;
    if (label.isNotEmpty) {
      return label.length == 1 ? label.toUpperCase() : label;
    }
    return key.debugName ?? '';
  }
}

class KeyboardShortcutHelpSection {
  const KeyboardShortcutHelpSection({
    required this.title,
    required this.entries,
  });

  final String title;
  final List<KeyboardShortcutHelpEntry> entries;
}

class KeyboardShortcutHelpEntry {
  const KeyboardShortcutHelpEntry({
    required this.label,
    required this.activators,
  });

  final String label;
  final List<SingleActivator> activators;
}

class SendMessageIntent extends Intent {
  const SendMessageIntent();
}

class ClearDraftIntent extends Intent {
  const ClearDraftIntent();
}

class NewChatIntent extends Intent {
  const NewChatIntent();
}

class OpenSettingsIntent extends Intent {
  const OpenSettingsIntent();
}

class FocusConversationSearchIntent extends Intent {
  const FocusConversationSearchIntent();
}

class SelectPreviousConversationIntent extends Intent {
  const SelectPreviousConversationIntent();
}

class SelectNextConversationIntent extends Intent {
  const SelectNextConversationIntent();
}

class ToggleWebSearchIntent extends Intent {
  const ToggleWebSearchIntent();
}
