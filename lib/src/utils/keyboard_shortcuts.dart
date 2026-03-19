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
