
class OfficeLocation {
  final double latitude;
  final double longitude;
  final double radiusMeters;

  const OfficeLocation({
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 200,
  });
}
