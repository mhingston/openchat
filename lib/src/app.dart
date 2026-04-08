import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'controllers/settings_controller.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

class OpenChatApp extends StatelessWidget {
  const OpenChatApp({super.key});

  static const Locale _fallbackLocale = Locale('en', 'US');

  @override
  Widget build(BuildContext context) {
    final SettingsController settingsController =
        context.watch<SettingsController>();

    return MaterialApp(
      title: 'OpenChat',
      debugShowCheckedModeBanner: false,
      themeMode: settingsController.themeMode,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: _supportedLocales(),
      home: const HomeScreen(),
    );
  }

  Iterable<Locale> _supportedLocales() sync* {
    final Set<String> seenLocales = <String>{};
    for (final Locale locale
        in WidgetsBinding.instance.platformDispatcher.locales) {
      if (GlobalMaterialLocalizations.delegate.isSupported(locale) &&
          seenLocales.add(locale.toString())) {
        yield locale;
      }
    }

    if (seenLocales.add(_fallbackLocale.toString())) {
      yield _fallbackLocale;
    }
  }
}
