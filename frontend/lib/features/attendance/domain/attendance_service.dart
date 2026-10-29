
import 'package:uuid/uuid.dart';

import '../../../core/time/company_clock.dart';
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
  // Injectable so tests can move time across midnight during the GPS wait.
  final DateTime Function() _clock;

  AttendanceService({
    required AttendanceLocalDataSource localDataSource,
    required DeviceLocationService locationService,
    AttendancePolicy attendancePolicy = const AttendancePolicy(),
    GeofencePolicy geofencePolicy = const GeofencePolicy(),
    Uuid uuid = const Uuid(),
    DateTime Function() clock = DateTime.now,
  })  : _localDataSource = localDataSource,
        _locationService = locationService,
        _attendancePolicy = attendancePolicy,
        _geofencePolicy = geofencePolicy,
        _uuid = uuid,
        _clock = clock;

  Future<AttendanceEvent> recordAttendance({
    required String employeeId,
    required AttendanceEventType type,
    required OfficeLocation office,
  }) async
  {
    // Checked before the GPS wait so a repeated tap fails straight away.
    final dateBeforeLocation = CompanyClock.today(now: _clock());
    await _validateAction(type, dateBeforeLocation);

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

    // The event's time and company date come from one instant, taken after
    // the GPS fix, so a fix that arrives after midnight is dated the new day.
    // The server derives the date from occurredAt the same way.
    final occurredAt = _clock().toUtc();
    final companyDate = CompanyClock.dateOf(occurredAt);

    if (companyDate != dateBeforeLocation) {
      await _validateAction(type, companyDate);
    }

    final event = AttendanceEvent(
      eventId: _uuid.v4(),
      employeeId: employeeId,
      type: type,
      occurredAt: occurredAt,
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

  Future<void> _validateAction(AttendanceEventType type, String companyDate) async {
    final dayEvents = await _localDataSource.getEventsForDate(companyDate);

    final validationMessage = _attendancePolicy.validateAction(
      requestedType: type,
      todayEvents: dayEvents,
    );

    if (validationMessage != null) {
      throw AttendanceValidationException(validationMessage);
    }
  }
}

class AttendanceValidationException implements Exception {
  final String message;

  const AttendanceValidationException(this.message);

  @override
  String toString() => message;
}
