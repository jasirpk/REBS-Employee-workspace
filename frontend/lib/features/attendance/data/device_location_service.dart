
import 'package:geolocator/geolocator.dart';

import '../domain/attendance_location.dart';

class DeviceLocationService {
  Future<AttendanceLocation> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw const LocationServiceDisabledException();
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const LocationPermissionDeniedException();
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationPermissionPermanentlyDeniedException();
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );

    return AttendanceLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
    );
  }
}

class LocationServiceDisabledException implements Exception {
  const LocationServiceDisabledException();

  @override
  String toString() => 'Location services are disabled.';
}

class LocationPermissionDeniedException implements Exception {
  const LocationPermissionDeniedException();

  @override
  String toString() => 'Location permission was denied.';
}

class LocationPermissionPermanentlyDeniedException implements Exception {
  const LocationPermissionPermanentlyDeniedException();

  @override
  String toString() =>
      'Location permission is permanently denied. Enable it in Settings.';
}
