
import 'package:uuid/uuid.dart';

import '../data/attendance_local_data_source.dart';
import '../data/device_location_service.dart';
import 'attendance_event.dart';
import 'attendance_policy.dart';
import 'geofence_policy.dart';
import 'office_location.dart';

class AttendanceService {
  final AttendanceLocalDataSource _localDataSource;
  final DeviceLocationService _locationService;
  final AttendancePolicy _attendancePolicy;
  final GeofencePolicy _geofencePolicy;
  final Uuid _uuid;

  AttendanceService({
    required AttendanceLocalDataSource localDataSource,
    required DeviceLocationService locationService,
    AttendancePolicy attendancePolicy = const AttendancePolicy(),
    GeofencePolicy geofencePolicy = const GeofencePolicy(),
    Uuid uuid = const Uuid(),
  })  : _localDataSource = localDataSource,
        _locationService = locationService,
        _attendancePolicy = attendancePolicy,
        _geofencePolicy = geofencePolicy,
        _uuid = uuid;

  Future<AttendanceEvent> recordAttendance({
    required String employeeId,
    required AttendanceEventType type,
    required String companyDate,
    required OfficeLocation office,
  }) async
  {
    final todayEvents =
    await _localDataSource.getEventsForDate(companyDate);

    final validationMessage = _attendancePolicy.validateAction(
      requestedType: type,
      todayEvents: todayEvents,
    );

    if (validationMessage != null) {
      throw AttendanceValidationException(validationMessage);
    }

    final location = await _locationService.getCurrentLocation();

    if (location.accuracyMeters > 50) {
      throw AttendanceValidationException(
        'GPS accuracy is too low. Please try again in a clearer location.',
      );
    }

    final isInside = _geofencePolicy.isWithinOfficeRadius(
      location: location,
      office: office,
    );

    if (!isInside) {
      throw AttendanceValidationException(
        'You must be within ${office.radiusMeters.toInt()} metres of the office.',
      );
    }

    final event = AttendanceEvent(
      eventId: _uuid.v4(),
      employeeId: employeeId,
      type: type,
      occurredAt: DateTime.now().toUtc(),
      companyDate: companyDate,
      latitude: location.latitude,
      longitude: location.longitude,
      accuracyMeters: location.accuracyMeters,
    );

    // Persist first. Network sync will be triggered only after this succeeds.
    final localId = await _localDataSource.saveEvent(event);

    return AttendanceEvent(
      localId: localId,
      eventId: event.eventId,
      employeeId: event.employeeId,
      type: event.type,
      occurredAt: event.occurredAt,
      companyDate: event.companyDate,
      latitude: event.latitude,
      longitude: event.longitude,
      accuracyMeters: event.accuracyMeters,
      status: event.status,
    );
  }
}

class AttendanceValidationException implements Exception {
  final String message;

  const AttendanceValidationException(this.message);

  @override
  String toString() => message;
}
