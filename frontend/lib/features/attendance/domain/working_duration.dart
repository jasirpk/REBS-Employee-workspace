
// Time worked today. Null before check-in. While checked in it runs up to
// [now]; after checkout it is fixed. Never negative: a checkout or clock
// time earlier than the check-in gives zero.
Duration? workedDuration({
  required DateTime? checkIn,
  required DateTime? checkOut,
  required DateTime now,
}) {
  if (checkIn == null) return null;

  final end = checkOut ?? now;
  if (end.isBefore(checkIn)) return Duration.zero;

  return end.difference(checkIn);
}

// "2h 35m"; whole minutes only.
String formatWorkedDuration(Duration duration) {
  final hours = duration.inMinutes ~/ 60;
  final minutes = duration.inMinutes % 60;

  return '${hours}h ${minutes}m';
}
