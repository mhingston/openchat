import 'package:flutter/material.dart';

class LocalizedTimestampFormatter {
  const LocalizedTimestampFormatter._();

  static String formatMessageTime(BuildContext context, DateTime timestamp) {
    return _formatTime(context, timestamp);
  }

  static String formatCompactTimestamp(
    BuildContext context,
    DateTime timestamp, {
    DateTime? now,
  }) {
    final DateTime localTimestamp = timestamp.toLocal();
    final DateTime localNow = (now ?? DateTime.now()).toLocal();
    if (_isSameLocalDay(localTimestamp, localNow)) {
      return _formatTime(context, localTimestamp);
    }
    return MaterialLocalizations.of(context).formatCompactDate(localTimestamp);
  }

  static String formatFullDateTime(BuildContext context, DateTime timestamp) {
    final DateTime localTimestamp = timestamp.toLocal();
    final MaterialLocalizations localizations =
        MaterialLocalizations.of(context);
    return '${localizations.formatFullDate(localTimestamp)}\n'
        '${_formatTime(context, localTimestamp)}';
  }

  static String _formatTime(BuildContext context, DateTime timestamp) {
    final DateTime localTimestamp = timestamp.toLocal();
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(localTimestamp),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }

  static bool _isSameLocalDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
