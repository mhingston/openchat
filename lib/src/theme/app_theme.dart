import 'package:flutter/material.dart';

class OpenChatPalette extends ThemeExtension<OpenChatPalette> {
  const OpenChatPalette({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.accent,
    required this.userBubble,
    required this.assistantBubble,
    required this.mutedText,
    required this.headerBackground,
    required this.composerBackground,
    required this.danger,
    required this.success,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color accent;
  final Color userBubble;
  final Color assistantBubble;
  final Color mutedText;
  final Color headerBackground;
  final Color composerBackground;
  final Color danger;
  final Color success;

  @override
  OpenChatPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? border,
    Color? accent,
    Color? userBubble,
    Color? assistantBubble,
    Color? mutedText,
    Color? headerBackground,
    Color? composerBackground,
    Color? danger,
    Color? success,
  }) {
    return OpenChatPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      border: border ?? this.border,
      accent: accent ?? this.accent,
      userBubble: userBubble ?? this.userBubble,
      assistantBubble: assistantBubble ?? this.assistantBubble,
      mutedText: mutedText ?? this.mutedText,
      headerBackground: headerBackground ?? this.headerBackground,
      composerBackground: composerBackground ?? this.composerBackground,
      danger: danger ?? this.danger,
      success: success ?? this.success,
    );
  }

  @override
  OpenChatPalette lerp(ThemeExtension<OpenChatPalette>? other, double t) {
    if (other is! OpenChatPalette) {
      return this;
    }

    return OpenChatPalette(
      background: Color.lerp(background, other.background, t) ?? background,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceRaised:
          Color.lerp(surfaceRaised, other.surfaceRaised, t) ?? surfaceRaised,
      border: Color.lerp(border, other.border, t) ?? border,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      userBubble: Color.lerp(userBubble, other.userBubble, t) ?? userBubble,
      assistantBubble: Color.lerp(assistantBubble, other.assistantBubble, t) ??
          assistantBubble,
      mutedText: Color.lerp(mutedText, other.mutedText, t) ?? mutedText,
      headerBackground:
          Color.lerp(headerBackground, other.headerBackground, t) ??
              headerBackground,
      composerBackground:
          Color.lerp(composerBackground, other.composerBackground, t) ??
              composerBackground,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      success: Color.lerp(success, other.success, t) ?? success,
    );
  }
}

extension OpenChatThemeX on BuildContext {
  OpenChatPalette get openChatPalette {
    final OpenChatPalette? palette =
        Theme.of(this).extension<OpenChatPalette>();
    assert(palette != null, 'OpenChatPalette is required on ThemeData.');
    return palette!;
  }
}

class AppTheme {
  static const OpenChatPalette _darkPalette = OpenChatPalette(
    background: Color(0xFF0B0D12),
    surface: Color(0xFF11151C),
    surfaceRaised: Color(0xFF1A202A),
    border: Color(0xFF2A3240),
    accent: Color(0xFF8AB4F8),
    userBubble: Color(0xFF16314F),
    assistantBubble: Color(0xFF171C24),
    mutedText: Color(0xFF9AA3B2),
    headerBackground: Color(0xF20E131A),
    composerBackground: Color(0xFF11161F),
    danger: Color(0xFFFF8F8F),
    success: Color(0xFF7ED7A8),
  );

  static const OpenChatPalette _lightPalette = OpenChatPalette(
    background: Color(0xFFF4F7FB),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF1F5F9),
    border: Color(0xFFD8E0EA),
    accent: Color(0xFF245DFF),
    userBubble: Color(0xFFDCE8FF),
    assistantBubble: Color(0xFFFFFFFF),
    mutedText: Color(0xFF5A6472),
    headerBackground: Color(0xF2FFFFFF),
    composerBackground: Color(0xFFFFFFFF),
    danger: Color(0xFFB3261E),
    success: Color(0xFF166534),
  );

  static ThemeData darkTheme() {
    const ColorScheme colorScheme = ColorScheme.dark(
      primary: Color(0xFF8AB4F8),
      secondary: Color(0xFF8AB4F8),
      surface: Color(0xFF11151C),
      error: Color(0xFFFF8F8F),
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: Colors.white,
      outline: Color(0xFF2A3240),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _darkPalette.background,
      canvasColor: _darkPalette.background,
      splashFactory: NoSplash.splashFactory,
      extensions: const <ThemeExtension<dynamic>>[_darkPalette],
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      dividerColor: _darkPalette.border,
      drawerTheme: const DrawerThemeData(
        backgroundColor: Color(0xFF0E131A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(28),
            bottomRight: Radius.circular(28),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkPalette.surfaceRaised,
        hintStyle: TextStyle(color: _darkPalette.mutedText),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: _darkPalette.border),
          borderRadius: BorderRadius.circular(20),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: _darkPalette.border),
          borderRadius: BorderRadius.circular(20),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: _darkPalette.accent, width: 1.4),
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _darkPalette.accent,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: _darkPalette.surfaceRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _darkPalette.surfaceRaised,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      cardTheme: CardThemeData(
        color: _darkPalette.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: _darkPalette.border),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 1.5,
          color: Colors.white,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: Colors.white,
        ),
        bodySmall: TextStyle(
          fontSize: 13,
          height: 1.4,
          color: Color(0xFF9AA3B2),
        ),
      ),
    );
  }

  static ThemeData lightTheme() {
    const ColorScheme colorScheme = ColorScheme.light(
      primary: Color(0xFF245DFF),
      secondary: Color(0xFF245DFF),
      surface: Colors.white,
      error: Color(0xFFB3261E),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Color(0xFF101828),
      outline: Color(0xFFD8E0EA),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _lightPalette.background,
      canvasColor: _lightPalette.background,
      splashFactory: NoSplash.splashFactory,
      extensions: const <ThemeExtension<dynamic>>[_lightPalette],
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _lightPalette.surfaceRaised,
        hintStyle: TextStyle(color: _lightPalette.mutedText),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: _lightPalette.border),
          borderRadius: BorderRadius.circular(20),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: _lightPalette.border),
          borderRadius: BorderRadius.circular(20),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: _lightPalette.accent, width: 1.4),
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      cardTheme: CardThemeData(
        color: _lightPalette.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: _lightPalette.border),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
      ),
    );
  }
}
