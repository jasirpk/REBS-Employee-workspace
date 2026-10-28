import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/attendance/domain/working_duration.dart';

void main() {
  final checkIn = DateTime.utc(2026, 10, 29, 4, 0);

  group('workedDuration', () {
    test('is absent before check-in', () {
      expect(workedDuration(checkIn: null, checkOut: null, now: checkIn), isNull);
    });

    test('is absent for a checkout without a check-in', () {
      expect(workedDuration(checkIn: null, checkOut: checkIn, now: checkIn), isNull);
    });

    test('grows with the current time while checked in', () {
      final early = workedDuration(checkIn: checkIn, checkOut: null, now: checkIn.add(const Duration(hours: 1)));
      final later = workedDuration(checkIn: checkIn, checkOut: null, now: checkIn.add(const Duration(hours: 2, minutes: 35)));

      expect(early, const Duration(hours: 1));
      expect(later, const Duration(hours: 2, minutes: 35));
    });

    test('stays fixed after checkout', () {
      final checkOut = checkIn.add(const Duration(hours: 8, minutes: 15));

      final atCheckout = workedDuration(checkIn: checkIn, checkOut: checkOut, now: checkOut);
      final nextDay = workedDuration(checkIn: checkIn, checkOut: checkOut, now: checkOut.add(const Duration(days: 1)));

      expect(atCheckout, const Duration(hours: 8, minutes: 15));
      expect(nextDay, const Duration(hours: 8, minutes: 15));
    });

    test('is never negative', () {
      final checkoutBeforeCheckIn = workedDuration(checkIn: checkIn, checkOut: checkIn.subtract(const Duration(minutes: 5)), now: checkIn);
      final clockBeforeCheckIn = workedDuration(checkIn: checkIn, checkOut: null, now: checkIn.subtract(const Duration(minutes: 5)));

      expect(checkoutBeforeCheckIn, Duration.zero);
      expect(clockBeforeCheckIn, Duration.zero);
    });
  });

  test('formats whole hours and minutes', () {
    expect(formatWorkedDuration(const Duration(hours: 2, minutes: 35, seconds: 59)), '2h 35m');
    expect(formatWorkedDuration(const Duration(minutes: 7)), '0h 7m');
    expect(formatWorkedDuration(Duration.zero), '0h 0m');
  });
}
