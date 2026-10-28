
class CompanyClock {
  CompanyClock._();

  static String today({DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();

    // Asia/Kolkata is UTC+05:30.
    final companyTime = current.add(const Duration(hours: 5, minutes: 30));

    final year = companyTime.year.toString().padLeft(4, '0');
    final month = companyTime.month.toString().padLeft(2, '0');
    final day = companyTime.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }
}
