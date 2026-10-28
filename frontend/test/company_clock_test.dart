
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
}
