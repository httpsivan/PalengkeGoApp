import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:palengkego/features/vendors/domain/closing_time.dart';
import 'package:palengkego/features/vendors/domain/day_schedule.dart';
import 'package:palengkego/features/vendors/presentation/widgets/stall_operating_hours_sheet.dart';

void main() {
  testWidgets('StallOperatingHoursSheet renders weekly schedule and next opening', (
    tester,
  ) async {
    const schedule = [
      DaySchedule(name: 'Monday', openTime: '06:00', closeTime: '18:00'),
      DaySchedule(name: 'Tuesday', openTime: '07:00', closeTime: '17:00'),
      DaySchedule(name: 'Wednesday', isOpen: false),
    ];

    const nextOpening = NextOpeningTime(
      dayLabel: 'tomorrow',
      formattedTime: '6:00 AM',
      isToday: false,
      isTomorrow: true,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StallOperatingHoursSheet(
            stallName: 'Britanico Store',
            schedule: schedule,
            isCurrentlyOpen: false,
            nextOpening: nextOpening,
          ),
        ),
      ),
    );

    expect(find.text('Britanico Store'), findsOneWidget);
    expect(find.text('Store Operating Hours'), findsOneWidget);
    expect(find.text('Opens tomorrow at 6:00 AM'), findsOneWidget);
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('6:00 AM - 6:00 PM'), findsOneWidget);
    expect(find.text('Closed'), findsWidgets);
    expect(find.text('Got It'), findsOneWidget);

    await tester.tap(find.text('Got It'));
    await tester.pumpAndSettle();
  });
}
