import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/settings_controller.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

class OpenChatApp extends StatelessWidget {
  const OpenChatApp({super.key});

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
      home: const HomeScreen(),
    );
  }
}
