# Assignment checklist

Status of each requirement in the *Flutter Developer Assignment — REBS HRMS*
brief, based on the code and the automated tests in this repository.

Validation when this was written: `fvm flutter analyze`: no issues;
`fvm flutter test`: **145 passed**; `npm run typecheck` (backend): no errors.
The mock API was not running, so its health endpoint was not called.

**Statuses**
- **Tested:** implemented and covered by automated tests.
- **Not device-verified:** implemented (and tested where noted), but not
  checked on a device or simulator.
- **Partial:** partially implemented.
- **Missing:** not implemented.
- **Developer to confirm:** needs the developer to confirm or supply.

Paths are relative to `frontend/` unless they start with `backend/`. Unless a
row says otherwise, nothing has been re-verified on a device after the latest
changes.

## 1. Employee dashboard

| Requirement | Status | Evidence / gap |
|---|---|---|
| Name, ID, department | Tested | `DashboardPage` `_DashboardContent`; `test/dashboard_page_test.dart` |
| Today's status (3 states) | Partial | `_AttendanceCard` derives it from non-rejected events. No widget test asserts the three labels. Not device-verified. |
| Check-in / check-out times | Tested | Company-time formatting through `CompanyClock.format`; `dashboard_page_test` "the attendance card and history show the same company time" |
| Elapsed working duration | Tested; not device-verified | `domain/working_duration.dart`, `WorkedDurationText` (single minute timer, stopped after checkout, cancelled on dispose); `test/working_duration_test.dart`, `test/worked_duration_text_test.dart` |
| Leave balance | Tested | `_LeaveBalanceCard`, cached in `dashboard_cache`; `test/dashboard_repository_test.dart`, `test/dashboard_cubit_test.dart` |
| Latest five attendance records | Tested; not device-verified | `AttendanceLocalDataSource.getRecentEvents`, `AttendanceSyncCoordinator.pullRecentHistory`, `_RecentAttendance`; tests in `attendance_local_data_source_test`, `attendance_sync_coordinator_test`, `attendance_cubit_test`, `dashboard_page_test`. Fetches at most two months. |
| Loading / empty / error / offline states | Tested | `DashboardLoading`, history empty and loading text, `DashboardError(noSavedProfileMessage)`, the offline banner; cubit and widget tests |

## 2. Attendance

| Requirement | Status | Evidence / gap |
|---|---|---|
| One check-in per working day | Tested | `AttendancePolicy`, unique index, server 409; `attendance_policy_test`, `attendance_reliability_test` |
| Check-out only after check-in | Tested | Policy + server 422; reliability test "checkout without check-in…" |
| Repeated taps create no duplicates | Tested | `isActionInProgress` guard, policy, index, `eventId`; reliability "repeated check-in taps…" |
| Timestamp + GPS captured | Tested | `AttendanceService.recordAttendance`; `test/attendance_service_test.dart` |
| 200 m geofence | Partial (tests) | Client `GeofencePolicy` and server `OUTSIDE_GEOFENCE`. `geofence_policy_test` covers "at the office" and "well outside" only: **no test near the 200 m boundary**. |
| Permission denied / permanently denied / unavailable | Partial (tests) | All handled in `DeviceLocationService`. Tested: permanently denied and the GPS timeout. **Untested:** denied, and location services off. |
| Outside-area message | Tested (client) | "You must be within 200 metres of the office."; the server's text is fixed at "200 metres". |
| Office coordinates configurable | Tested | `employee.office` in `backend/src/server.ts`, delivered via `/employee/me`. Configured by editing code; documented in the README. |
| Documented location simulation | Developer to confirm | README "Simulating a location": standard platform tools, **not run in this project's verification**. |
| Configurable company timezone | Tested | `COMPANY_UTC_OFFSET_MINUTES` in `CompanyClock`; `company_clock_test` (18:29:59Z/18:30:00Z, other offsets). Fixed offset, no daylight saving (documented). |
| Midnight during the GPS wait | Tested | Date taken from `occurredAt` after the fix; `attendance_service_test` |
| Server repeats the checks | Partial | The server repeats date, geofence, once-per-day, check-in-before-checkout and idempotency. **Not repeated:** GPS accuracy and a timestamp window. Documented in the README; changing this means changing the backend. |

## 3. Offline storage and synchronization

| Requirement | Status | Evidence / gap |
|---|---|---|
| Dashboard + history cached for offline viewing | Tested | `dashboard_cache`, `attendance_events`; cubit tests "uses the cached employee…" and "keeps cached history…" |
| Actions saved offline | Tested; not device-verified | Saved locally before any network call; reliability and cubit tests |
| Pending / Synced / Rejected shown clearly | Tested | History labels, pending banner, rejection lines; `dashboard_page_test` "lists events with their type, date and sync status" |
| Pending events survive a restart | Tested | Reliability "pending events survive closing the database…" (file-backed SQLite) |
| Manual Sync Now | Partial | `AttendanceCubit.retrySync`. The banner appears only when **today's** events are pending; older pending events still sync automatically. Next step: show the banner for any pending event. |
| Sync when connectivity returns | Tested; not device-verified | `startAutoSync` + `connectivity_plus`; cubit "syncs when connectivity returns…" with a fake connectivity stream |
| Event order kept | Tested | `local_id ASC`, stops at the first temporary error; reliability tests |
| "Attendance already exists" rejection | Tested | Coordinator → REJECTED, then a history pull; cubit "pulls history and shows the server check-in" |
| Timeout after server acceptance | Tested | Same `eventId` and millisecond payload; reliability "retrying after a timeout…", `attendance_service_test` |
| Event identity / idempotency explained | Tested | README "Offline storage and synchronization" |
| Offline start with no saved profile | Tested | Clear "connect once" message (`DashboardCubit.noSavedProfileMessage`), no invented office location |

## 4. Leave application

| Requirement | Status | Evidence / gap |
|---|---|---|
| Form: type, start, end, reason | Tested | `LeavePage`; `test/features/leave/presentation/leave_page_test.dart` |
| Start not before company date | Tested | `LeavePolicy`; `leave_policy_test` |
| End not before start | Tested | `leave_policy_test` |
| Reason at least 10 non-whitespace characters | Tested | `leave_policy_test` |
| Days within balance | Tested | `leave_policy_test`. Pending requests do not reserve balance, matching the backend. |
| No overlap with Pending/Approved | Tested | `leave_policy_test`, `leave_cubit_test` |
| Pending/Approved/Rejected list | Tested | `leave_page_test`. There is no approval workflow; the brief only asks to display these statuses. |
| Viewable offline; submit needs a connection | Tested | `LeaveRepository.loadLeaveRequests` cache fallback; `leave_repository_test` |
| Server validation errors shown | Tested | `LeaveSubmissionException` with the server message; repository and cubit tests |

## 5. API integration

| Requirement | Status | Evidence / gap |
|---|---|---|
| Suggested endpoints | Tested | All six in `backend/src/server.ts`, used through Dio. Exercised by Flutter tests with stubbed HTTP. There are no backend tests. |
| Mock scenarios (success, slow/timeout, 500, duplicate, leave rejection) | Developer to confirm | `/api/__admin/scenario` with `normal`, `slow`, `error500`, `timeout_before`, `timeout_after`, `duplicate`, `leave_rejection`; documented in the README. Not exercised against the running server in this pass. |
| HTTP client, not hardcoded widgets | Tested | Dio `ApiClient` |

## 6. Technical expectations

| Requirement | Status | Evidence / gap |
|---|---|---|
| Null safety, Flutter/Dart | Tested | Dart `>=3.11.5`; analyzer clean |
| State management justified | Tested | Cubit, explained in the README |
| Layers separated | Tested | `data/`, `domain/`, `presentation/` per feature |
| Persistent storage | Tested | SQLite schema v3, migration tests |
| No business logic in `build` | Partial | `_AttendanceCard.build` works out `canCheckIn` and `canCheckOut` from events. A small amount; could move to state getters. |
| Reasonable dependencies | Tested | flutter_bloc, equatable, dio, sqflite, path, uuid, geolocator, connectivity_plus, intl; dev: bloc_test, mocktail, sqflite_common_ffi, flutter_native_splash |
| Usable on different Android screen sizes | Developer to confirm | Scrolling layouts; not checked on several screen sizes |
| No credentials or secrets | Tested | A keyword scan found none; the mock API has no authentication |

## 7. Required tests

| Test | Status | Where |
|---|---|---|
| Check-out without check-in rejected | Tested | `attendance_policy_test`, `attendance_reliability_test` |
| Repeat or retry, no duplicate | Tested | `attendance_reliability_test` |
| Pending survives persistence and syncs in order | Tested | `attendance_reliability_test` (file-backed) |
| Overlapping leave dates rejected | Tested | `leave_policy_test` |
| Widget test: loading/error/pending-sync | Tested | `dashboard_page_test` (error state, history loading, sync labels) |

Test gaps worth closing: the geofence boundary (199 m / 201 m), the
permission-denied and location-off messages, the dashboard status labels, and
backend tests.

## 8. Deliverables

| Deliverable | Status | Next action |
|---|---|---|
| Repository | Partial | Commit the work; stop tracking `backend/node_modules`, `frontend/frontend/`, `.DS_Store`, `.idea`; add `.gitignore` files |
| Installable debug APK | Missing | No `app-debug.apk` in `build/`. The `app-release.apk` there was built before the latest changes. Build the debug APK (README command) and install-test it. |
| Mock API + setup instructions | Tested | `backend/`, README |
| README | Tested | `README.md` (AI disclosure and time spent need the developer) |
| Demo video (3–5 min) | Missing | Record the six required scenes |
| AI-use disclosure | Developer to confirm | Draft in the README |
| Time spent | Developer to confirm | Placeholder in the README |
| Device verification of the latest build | Developer to confirm | Recent history, worked time, company-time display, auto-sync, offline cold start and the leave flow, on the phone and simulator |
