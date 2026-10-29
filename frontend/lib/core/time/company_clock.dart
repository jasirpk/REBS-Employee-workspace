
import 'package:intl/intl.dart';

// Company dates and times, independent of the device's timezone.
//
// The company timezone is a fixed UTC offset, set at build time:
//   --dart-define=COMPANY_UTC_OFFSET_MINUTES=330   (default, UTC+05:30)
// It must match the backend's employee.timezone (Asia/Kolkata), which the
// server uses to validate each event's company date. A fixed offset does not
// follow daylight-saving changes; see README.
class CompanyClock {
  CompanyClock._();

  static const int utcOffsetMinutes = int.fromEnvironment('COMPANY_UTC_OFFSET_MINUTES', defaultValue: 330);

  // Company date (YYYY-MM-DD) for now, or for [now] when given.
  static String today({DateTime? now, int offsetMinutes = utcOffsetMinutes}) {
    return dateOf(now ?? DateTime.now(), offsetMinutes: offsetMinutes);
  }

  // Company date (YYYY-MM-DD) of an instant.
  static String dateOf(DateTime instant, {int offsetMinutes = utcOffsetMinutes}) {
    final companyTime = _wallClock(instant, offsetMinutes);

    final year = companyTime.year.toString().padLeft(4, '0');
    final month = companyTime.month.toString().padLeft(2, '0');
    final day = companyTime.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  // Formats an instant as company wall-clock time, e.g. pattern 'hh:mm a'.
  static String format(DateTime instant, String pattern, {int offsetMinutes = utcOffsetMinutes}) {
    return DateFormat(pattern).format(_wallClock(instant, offsetMinutes));
  }

  // The instant shifted into company time. Its fields (hour, day...) are the
  // company's wall clock; DateFormat prints them without converting again.
  static DateTime _wallClock(DateTime instant, int offsetMinutes) {
    return instant.toUtc().add(Duration(minutes: offsetMinutes));
  }
}
