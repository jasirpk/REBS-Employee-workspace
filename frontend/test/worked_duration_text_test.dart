import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/attendance/presentation/worked_duration_text.dart';

void main() {
  final checkIn = DateTime.utc(2026, 10, 29, 4, 0);
  late DateTime now;

  setUp(() {
    now = checkIn.add(const Duration(hours: 1));
  });

  Future<void> pumpDuration(WidgetTester tester, {DateTime? checkIn, DateTime? checkOut}) {
    return tester.pumpWidget(
      MaterialApp(
        home: WorkedDurationText(checkIn: checkIn, checkOut: checkOut, clock: () => now),
      ),
    );
  }

  testWidgets('shows nothing before check-in', (tester) async {
    await pumpDuration(tester);

    expect(find.textContaining('Worked:'), findsNothing);
  });

  testWidgets('updates every minute while checked in', (tester) async {
    await pumpDuration(tester, checkIn: checkIn);
    expect(find.text('Worked: 1h 0m'), findsOneWidget);

    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('Worked: 1h 1m'), findsOneWidget);

    // Rebuilding with the same values keeps the minute updates going.
    await pumpDuration(tester, checkIn: checkIn);
    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('Worked: 1h 2m'), findsOneWidget);
  });

  testWidgets('stays fixed after checkout and stops the timer', (tester) async {
    await pumpDuration(tester, checkIn: checkIn);

    final checkOut = checkIn.add(const Duration(hours: 2, minutes: 35));
    now = checkOut;
    await pumpDuration(tester, checkIn: checkIn, checkOut: checkOut);
    expect(find.text('Worked: 2h 35m'), findsOneWidget);

    now = now.add(const Duration(hours: 3));
    await tester.pump(const Duration(minutes: 5));
    expect(find.text('Worked: 2h 35m'), findsOneWidget);
  });

  testWidgets('removing the widget cancels its timer', (tester) async {
    await pumpDuration(tester, checkIn: checkIn);

    await tester.pumpWidget(const SizedBox());

    // flutter_test fails the test if a timer is still pending here.
    expect(find.textContaining('Worked:'), findsNothing);
  });
}
