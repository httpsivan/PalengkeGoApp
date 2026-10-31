import 'day_schedule.dart';

List<DaySchedule>? findOperatingSchedule(
  Map<String, List<DaySchedule>> schedules,
  String stallId,
) {
  final id = stallId.trim().toLowerCase();
  for (final entry in schedules.entries) {
    if (entry.key.trim().toLowerCase() == id) return entry.value;
  }
  return null;
}

String closingWarning(int minutes) => minutes >= 60
    ? 'Only 1 hour left'
    : 'Only $minutes min left';

bool isScheduleOpenNow(List<DaySchedule> schedule, DateTime now) {
  final local = now.toUtc().add(const Duration(hours: 8));
  final midnight = DateTime.utc(local.year, local.month, local.day);
  const days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  int? parse(String value) {
    final match = RegExp(r'^(\d{2}):(\d{2})(?::00)?$').firstMatch(value);
    if (match == null) return null;
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    return hour < 24 && minute < 60 ? hour * 60 + minute : null;
  }

  for (final offset in [0, -1]) {
    final date = midnight.add(Duration(days: offset));
    for (final day in schedule.where(
      (entry) =>
          entry.name.trim().toLowerCase() ==
              days[date.weekday - 1].toLowerCase() &&
          entry.isOpen,
    )) {
      final start = parse(day.openTime);
      final end = parse(day.closeTime);
      if (start == null || end == null || start == end) continue;
      final opens = date.add(Duration(minutes: start));
      final closes = date.add(Duration(minutes: end + (end < start ? 1440 : 0)));
      if (!local.isBefore(opens) && local.isBefore(closes)) return true;
    }
  }
  return false;
}

/// Saved market hours are Philippine time, regardless of the customer's timezone.
int? minutesUntilClosing(
  List<DaySchedule> schedule,
  DateTime now, {
  required bool isOpen,
}) {
  if (!isOpen) return null;
  final local = now.toUtc().add(const Duration(hours: 8));
  final midnight = DateTime.utc(local.year, local.month, local.day);
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  int? parseTime(String value) {
    final match = RegExp(r'^(\d{2}):(\d{2})(?::00)?$').firstMatch(value);
    if (match == null) return null;
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    return hour < 24 && minute < 60 ? hour * 60 + minute : null;
  }

  // Yesterday covers an overnight shift ending this morning.
  for (final offset in [0, -1]) {
    final date = midnight.add(Duration(days: offset));
    for (final day in schedule.where(
      (d) =>
          d.name.trim().toLowerCase() ==
              days[date.weekday - 1].toLowerCase() &&
          d.isOpen,
    )) {
      final start = parseTime(day.openTime);
      final end = parseTime(day.closeTime);
      if (start == null || end == null || start == end) continue;
      final opens = date.add(Duration(minutes: start));
      final closes = date.add(
        Duration(minutes: end + (end < start ? 1440 : 0)),
      );
      if (local.isBefore(opens) || !local.isBefore(closes)) continue;
      final remaining = closes.difference(local);
      if (remaining <= const Duration(hours: 1)) {
        return (remaining.inMilliseconds / Duration.millisecondsPerMinute)
            .ceil();
      }
    }
  }
  return null;
}
class NextOpeningTime {
  final String dayLabel;
  final String formattedTime;
  final bool isToday;
  final bool isTomorrow;

  const NextOpeningTime({
    required this.dayLabel,
    required this.formattedTime,
    required this.isToday,
    required this.isTomorrow,
  });

  String get shortText {
    if (isToday) return 'Opens $formattedTime';
    if (isTomorrow) return 'Opens tomorrow $formattedTime';
    return 'Opens $dayLabel $formattedTime';
  }

  String get fullText {
    if (isToday) return 'Opens today at $formattedTime';
    if (isTomorrow) return 'Opens tomorrow at $formattedTime';
    return 'Opens $dayLabel at $formattedTime';
  }
}

String formatTime12Hour(String timeStr) {
  final match =
      RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(timeStr.trim());
  if (match == null) return timeStr;
  int hour = int.parse(match[1]!);
  final minute = match[2]!;
  final period = hour >= 12 ? 'PM' : 'AM';
  if (hour == 0) {
    hour = 12;
  } else if (hour > 12) {
    hour -= 12;
  }
  return '$hour:$minute $period';
}

NextOpeningTime? findNextOpeningTime(
  List<DaySchedule>? schedule,
  DateTime now,
) {
  if (schedule == null || schedule.isEmpty) return null;
  final local = now.toUtc().add(const Duration(hours: 8));
  final midnight = DateTime.utc(local.year, local.month, local.day);
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  int? parseTime(String value) {
    final match =
        RegExp(r'^(\d{1,2}):(\d{2})(?::00)?$').firstMatch(value.trim());
    if (match == null) return null;
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    return hour < 24 && minute < 60 ? hour * 60 + minute : null;
  }

  for (int offset = 0; offset <= 7; offset++) {
    final targetDate = midnight.add(Duration(days: offset));
    final targetDayName = days[targetDate.weekday - 1];

    final matchingDays = schedule.where(
      (entry) =>
          entry.name.trim().toLowerCase() == targetDayName.toLowerCase() &&
          entry.isOpen,
    );

    for (final day in matchingDays) {
      final startMin = parseTime(day.openTime);
      if (startMin == null) continue;
      final openingMoment = targetDate.add(Duration(minutes: startMin));

      // If checking today (offset == 0), only accept if opening moment is in the future
      if (offset == 0 && !local.isBefore(openingMoment)) {
        continue;
      }

      final isToday = offset == 0;
      final isTomorrow = offset == 1;
      final label =
          isToday ? 'today' : (isTomorrow ? 'tomorrow' : targetDayName);

      return NextOpeningTime(
        dayLabel: label,
        formattedTime: formatTime12Hour(day.openTime),
        isToday: isToday,
        isTomorrow: isTomorrow,
      );
    }
  }

  return null;
}
