import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openchat/src/utils/localized_timestamp_formatter.dart';

Widget _wrap(Widget child, {Locale? locale}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const <Locale>[
      Locale('en', 'US'),
      Locale('de', 'DE'),
    ],
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('compact timestamp uses time for the current local day', (
    WidgetTester tester,
  ) async {
    late String formatted;
    final DateTime timestamp = DateTime(2026, 3, 18, 9, 15);
    final DateTime now = DateTime(2026, 3, 18, 12, 30);

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (BuildContext context) {
            formatted = LocalizedTimestampFormatter.formatCompactTimestamp(
              context,
              timestamp,
              now: now,
            );
            return const SizedBox.shrink();
          },
        ),
        locale: const Locale('de', 'DE'),
      ),
    );

    final BuildContext context = tester.element(find.byType(SizedBox));
    final String expected = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(timestamp),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

    expect(formatted, expected);
  });

  testWidgets('compact timestamp uses a localized short date for older items', (
    WidgetTester tester,
  ) async {
    late String formatted;
    final DateTime timestamp = DateTime(2001, 1, 2, 9, 15);
    final DateTime now = DateTime(2026, 3, 18, 12, 30);

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (BuildContext context) {
            formatted = LocalizedTimestampFormatter.formatCompactTimestamp(
              context,
              timestamp,
              now: now,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final BuildContext context = tester.element(find.byType(SizedBox));
    final String expected =
        MaterialLocalizations.of(context).formatCompactDate(timestamp);

    expect(formatted, expected);
  });
}
