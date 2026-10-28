
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/attendance/domain/attendance_location.dart';
import 'package:frontend/features/attendance/domain/geofence_policy.dart';
import 'package:frontend/features/attendance/domain/office_location.dart';

void main() {
  const policy = GeofencePolicy();

  const office = OfficeLocation(
    latitude: 12.9716,
    longitude: 77.5946,
    radiusMeters: 200,
  );

  test('accepts a location at the office coordinates', () {
    expect(
      policy.isWithinOfficeRadius(
        location: const AttendanceLocation(
          latitude: 12.9716,
          longitude: 77.5946,
          accuracyMeters: 5,
        ),
        office: office,
      ),
      isTrue,
    );
  });

  test('rejects a location well outside the office radius', () {
    expect(
      policy.isWithinOfficeRadius(
        location: const AttendanceLocation(
          latitude: 12.9816,
          longitude: 77.5946,
          accuracyMeters: 5,
        ),
        office: office,
      ),
      isFalse,
    );
  });

  test('rejects invalid GPS coordinates', () {
    expect(
      policy.isWithinOfficeRadius(
        location: const AttendanceLocation(
          latitude: 200,
          longitude: 77.5946,
          accuracyMeters: 5,
        ),
        office: office,
      ),
      isFalse,
    );
  });
}
