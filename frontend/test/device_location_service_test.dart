import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:frontend/features/attendance/data/device_location_service.dart';

// Stands in for the native plugin. [position] null means no fix arrives
// before the time limit.
class FakeGeolocatorPlatform extends GeolocatorPlatform {
  LocationPermission permission = LocationPermission.whileInUse;
  Position? position;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    final current = position;
    if (current == null) {
      throw TimeoutException('Time limit reached while waiting for position update.', locationSettings?.timeLimit);
    }
    return current;
  }
}

void main() {
  late FakeGeolocatorPlatform platform;
  late GeolocatorPlatform originalPlatform;
  final service = DeviceLocationService();

  setUp(() {
    originalPlatform = GeolocatorPlatform.instance;
    platform = FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = platform;
  });

  tearDown(() {
    GeolocatorPlatform.instance = originalPlatform;
  });

  test('a GPS timeout becomes a clear location error', () async {
    platform.position = null;

    await expectLater(
      service.getCurrentLocation(),
      throwsA(
        isA<LocationUnavailableException>().having(
          (error) => error.toString(),
          'message',
          'Could not get your location. Move to an open area and try again.',
        ),
      ),
    );
  });

  test('returns the position and its accuracy when a fix arrives', () async {
    platform.position = Position(
      latitude: 11.190723,
      longitude: 75.950761,
      timestamp: DateTime.utc(2026, 10, 29, 4),
      accuracy: 12,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

    final location = await service.getCurrentLocation();

    expect(location.latitude, 11.190723);
    expect(location.longitude, 75.950761);
    expect(location.accuracyMeters, 12);
  });

  test('permanently denied permission is still reported as before', () async {
    platform.permission = LocationPermission.deniedForever;

    await expectLater(service.getCurrentLocation(), throwsA(isA<LocationPermissionPermanentlyDeniedException>()));
  });
}
