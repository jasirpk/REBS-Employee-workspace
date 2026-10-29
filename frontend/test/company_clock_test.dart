
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/time/company_clock.dart';

void main() {
  group('CompanyClock.today', () {
    test('uses the company date rather than the UTC date', () {
      final result = CompanyClock.today(
        now: DateTime.utc(2026, 10, 28, 20, 0),
      );

      expect(result, '2026-10-29');
    });

    test('formats month and day with leading zeros', () {
      final result = CompanyClock.today(
        now: DateTime.utc(2026, 1, 1, 0, 0),
      );

      expect(result, '2026-01-01');
    });
  });

  group('CompanyClock.dateOf', () {
    test('defaults to UTC+05:30', () {
      expect(CompanyClock.utcOffsetMinutes, 330);
    });

    test('the company day changes exactly at 18:30:00Z for UTC+05:30', () {
      expect(CompanyClock.dateOf(DateTime.utc(2026, 10, 28, 18, 29, 59)), '2026-10-28');
      expect(CompanyClock.dateOf(DateTime.utc(2026, 10, 28, 18, 29, 59, 999, 999)), '2026-10-28');
      expect(CompanyClock.dateOf(DateTime.utc(2026, 10, 28, 18, 30, 0)), '2026-10-29');
    });

    test('follows a configured non-default offset', () {
      // UTC-05:00: the day changes at 05:00Z.
      expect(CompanyClock.dateOf(DateTime.utc(2026, 10, 29, 4, 59, 59), offsetMinutes: -300), '2026-10-28');
      expect(CompanyClock.dateOf(DateTime.utc(2026, 10, 29, 5, 0, 0), offsetMinutes: -300), '2026-10-29');

      // UTC+09:00: the day changes at 15:00Z, and a new year starts early.
      expect(CompanyClock.dateOf(DateTime.utc(2026, 12, 31, 14, 59, 59), offsetMinutes: 540), '2026-12-31');
      expect(CompanyClock.dateOf(DateTime.utc(2026, 12, 31, 15, 0, 0), offsetMinutes: 540), '2027-01-01');
    });

    test('gives the same date for a UTC and a device-local copy of an instant', () {
      final utc = DateTime.utc(2026, 10, 28, 18, 30);
      final deviceLocal = DateTime.fromMillisecondsSinceEpoch(utc.millisecondsSinceEpoch);

      expect(CompanyClock.dateOf(deviceLocal), CompanyClock.dateOf(utc));
    });
  });

  group('CompanyClock.format', () {
    test('shows company wall-clock time', () {
      final instant = DateTime.utc(2026, 10, 28, 19, 9, 21);

      expect(CompanyClock.format(instant, 'hh:mm a'), '12:39 AM');
      expect(CompanyClock.format(instant, 'EEE, d MMM yyyy'), 'Thu, 29 Oct 2026');
      expect(CompanyClock.format(instant, 'hh:mm a', offsetMinutes: -300), '02:09 PM');
    });

    test('does not depend on the device timezone of the DateTime', () {
      final utc = DateTime.utc(2026, 10, 28, 19, 9, 21);
      // The same instant, as a device-local DateTime (whatever the device zone is).
      final deviceLocal = DateTime.fromMillisecondsSinceEpoch(utc.millisecondsSinceEpoch);

      expect(deviceLocal.isUtc, isFalse);
      expect(CompanyClock.format(deviceLocal, 'd MMM, hh:mm a'), CompanyClock.format(utc, 'd MMM, hh:mm a'));
      expect(CompanyClock.format(deviceLocal, 'd MMM, hh:mm a'), '29 Oct, 12:39 AM');
    });
  });
}
