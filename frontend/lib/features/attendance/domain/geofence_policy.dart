
import 'dart:math' as math;

import 'attendance_location.dart';
import 'office_location.dart';

class GeofencePolicy {
  const GeofencePolicy();

  double distanceInMeters({
    required double latitude1,
    required double longitude1,
    required double latitude2,
    required double longitude2,
  }) {
    const earthRadiusMeters = 6371000.0;

    final lat1 = _toRadians(latitude1);
    final lat2 = _toRadians(latitude2);
    final deltaLat = _toRadians(latitude2 - latitude1);
    final deltaLon = _toRadians(longitude2 - longitude1);

    final a = math.pow(math.sin(deltaLat / 2), 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.pow(math.sin(deltaLon / 2), 2);

    final boundedA = a.clamp(0.0, 1.0);
    final centralAngle = 2 * math.atan2(
      math.sqrt(boundedA),
      math.sqrt(1 - boundedA),
    );

    return earthRadiusMeters * centralAngle;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;

  bool isWithinOfficeRadius({
    required AttendanceLocation location,
    required OfficeLocation office,
  }) {
    if (!location.latitude.isFinite ||
        !location.longitude.isFinite ||
        !location.accuracyMeters.isFinite ||
        location.latitude < -90 ||
        location.latitude > 90 ||
        location.longitude < -180 ||
        location.longitude > 180 ||
        location.accuracyMeters < 0) {
      return false;
    }

    final distance = distanceInMeters(
      latitude1: location.latitude,
      longitude1: location.longitude,
      latitude2: office.latitude,
      longitude2: office.longitude,
    );

    return distance <= office.radiusMeters;
  }
}
