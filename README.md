# REBS Employee Workspace

An offline-capable Flutter app for one preconfigured employee: a dashboard,
GPS-geofenced check-in/check-out that works offline and syncs reliably, and
leave applications. A local TypeScript/Express mock API in `backend/` plays
the server.

- `frontend/`: Flutter app (Android and iOS)
- `backend/`: mock HTTP API (Node.js, Express, TypeScript, in-memory data)
- [`ASSIGNMENT_CHECKLIST.md`](ASSIGNMENT_CHECKLIST.md): requirement-by-requirement status, with evidence and known gaps

## Features

**Dashboard**
- Employee name, ID and department.
- Today's attendance: Not Checked In / Checked In / Checked Out, check-in and
  check-out times, and worked time ("Worked: 2h 35m") that updates every
  minute while checked in and stops at checkout.
- Recent Attendance: the latest five events across dates, each labelled
  Synced, Pending Sync or Rejected, with an empty state.
- Casual and sick leave balance.
- Loading, error and offline states. After one successful load, the
  dashboard opens from its cache when offline, with an "Offline. Showing data
  saved on …" banner.

**Attendance**
- One check-in and one check-out per company day; check-out only after
  check-in.
- GPS location with an accuracy limit of 50 m and a 200 m office geofence.
- Clear messages for location services off, permission denied, permission
  permanently denied, GPS timeout and being outside the office area.
- Saved on the device first, then synced. Works offline.

**Leave**
- Form: Casual/Sick, start date, end date, reason.
- Local validation, repeated by the server.
- Request list with Pending/Approved/Rejected labels, viewable offline after
  one online load. Submitting needs a connection.

## Architecture

State management uses **Cubit** (`flutter_bloc`): one Cubit per feature
holds immutable state and calls repositories or services. It keeps widgets
free of data access and makes each feature testable with plain unit tests.

```
frontend/lib/
  core/
    config/api_config.dart         API_BASE_URL from frontend/.env (flutter_dotenv) + validation
    database/app_database.dart     SQLite (sqflite), schema version 3 + migrations
    network/api_client.dart        Dio client (10 s connect/receive timeouts)
    time/company_clock.dart        company date/time from COMPANY_UTC_OFFSET_MINUTES
  features/
    attendance/
      domain/        AttendanceEvent, AttendancePolicy, GeofencePolicy,
                     AttendanceService, working_duration.dart
      data/          AttendanceLocalDataSource (SQLite), AttendanceSyncCoordinator
                     (push/pull with the API), DeviceLocationService (geolocator)
      presentation/  AttendanceCubit/State, WorkedDurationText
    dashboard/
      domain/        Employee
      data/          DashboardRepository, DashboardLocalDataSource (response cache)
      presentaion/   DashboardCubit/State, DashboardPage   (folder name as in the code)
    leave/
      domain/        LeaveRequest, LeavePolicy
      data/          LeaveRepository, LeaveLocalDataSource (SQLite cache)
      presentation/  LeaveCubit/State, LeavePage
  main.dart          wiring (manual dependency injection), app start, auto-sync start
```

SQLite tables: `attendance_events` (local events and synced history),
`leave_requests` (cache), `dashboard_cache` (last employee and leave-balance
responses). Version 1 to 3 migrations only add tables, and existing data is
kept (`test/app_database_test.dart`).

## Prerequisites

Versions used during development:

- Flutter 3.41.8 (Dart SDK constraint `>=3.11.5 <4.0.0`), run through
  [FVM](https://fvm.app). The repository has no `.fvmrc`; select the version
  with FVM, or use `flutter` directly with a 3.41.x SDK.
- Node.js 22 and npm 10 for the mock API.
- Xcode (iOS) and/or the Android SDK.

## Run the mock API

```bash
cd backend
npm ci          # installs from package-lock.json
npm run dev     # tsx watch src/server.ts, listening on port 3000
```

Check it:

```bash
curl http://localhost:3000/api/health
# {"status":"ok","message":"REBS Employee Workspace API is running"}
```

The server listens on all network interfaces, so a phone on the same Wi-Fi
can reach it at `http://<Mac LAN IP>:3000`. macOS may ask to allow incoming
connections for `node`.

## Run the Flutter app

```bash
cd frontend
cp .env.example .env      # required after cloning; then set API_BASE_URL (see below)
fvm flutter pub get
fvm flutter run
```

### API address (`frontend/.env`)

The app reads the mock API address from `frontend/.env`, in normal `.env`
syntax (`#` starts a comment):

```dotenv
API_BASE_URL=http://192.168.1.2:3000/api/
```

- **Create it after cloning.** `frontend/.env` is git-ignored, so it is not
  in the repository; copy it from the committed template
  `frontend/.env.example`. The build fails with *"No file or variants found
  for asset: .env"* if the file does not exist, because `pubspec.yaml`
  declares it as an asset.
- **Use an address the device can reach.** `192.168.1.2` is only an example.
  `localhost` means the device or emulator itself in most contexts, not the
  Mac, so choose by target:

| Target | `API_BASE_URL` | Verified |
|---|---|---|
| iOS Simulator | `http://localhost:3000/api/` (the simulator shares the Mac's network) | Used during development |
| Android physical phone | `http://<Mac LAN IP>:3000/api/` (find it with `ipconfig getifaddr en0`; same Wi-Fi as the Mac) | Used during development |
| Android Emulator | `http://10.0.2.2:3000/api/` (the emulator's alias for the Mac) | Not verified here |

**How it is loaded.** The `flutter_dotenv` package reads `.env` at app start
(`dotenv.load()` in `main.dart`), before the API client is created, and
`ApiConfig.baseUrl` takes `API_BASE_URL` from it. The file is declared under
`flutter: assets:` in `pubspec.yaml`, so it is **bundled into the app as an
asset**. In a built APK it is the plain-text file
`assets/flutter_assets/.env`, and anyone with the APK can read it. Put
configuration there, never secrets. Edits take effect after a rebuild; no
extra build flags are needed.

If `API_BASE_URL` is missing or empty, is not an `http(s)` URL, contains an
unreplaced placeholder such as `<Mac LAN IP>`, or lacks the trailing `/`, the
app opens an **"App configuration error"** screen explaining what to fix,
rather than guessing an address.

### Company timezone offset

`COMPANY_UTC_OFFSET_MINUTES` is **not** read from `.env`. It is a build-time
constant (`int.fromEnvironment`), default `330` (UTC+05:30). Override it with
a flag, for example
`fvm flutter run --dart-define=COMPANY_UTC_OFFSET_MINUTES=330`.
See [Company timezone](#company-timezone).

Android networking notes:
- `android.permission.INTERNET` is declared in
  `android/app/src/main/AndroidManifest.xml`, so release builds can reach the
  network.
- The mock API is plain HTTP. No cleartext or network-security setting is
  configured. Dio uses Dart's own `HttpClient`, which does not apply Android's
  cleartext policy, and a debug build reached the LAN IP over HTTP during
  development.
- The phone and the Mac must be on the same network.

### Build an APK

```bash
cd frontend
# Debug APK (assignment deliverable)
fvm flutter build apk --debug
# -> build/app/outputs/flutter-apk/app-debug.apk

# Release APK (signed with the debug key, from the Flutter template)
fvm flutter build apk --release
# -> build/app/outputs/flutter-apk/app-release.apk
```

The APK contains the `.env` present at build time, so set `API_BASE_URL` for
the target device first, and rebuild when the Mac's IP changes.

## Company timezone

The app never uses the device timezone for attendance. `CompanyClock`
applies `COMPANY_UTC_OFFSET_MINUTES` to:
- each event's company date (which working day it belongs to);
- "today" for the dashboard and leave validation;
- every time shown on the dashboard.

An event's company date comes from the same timestamp stored as its
`occurredAt`, taken after the GPS fix. An action that finishes just after
midnight therefore belongs to the new day.

Keep the offset consistent with the backend's `employee.timezone`
(`backend/src/server.ts`, currently `Asia/Kolkata`). The server checks each
event's company date in that timezone and rejects mismatches with
`COMPANY_DATE_MISMATCH`.

A fixed offset does not follow daylight saving. Asia/Kolkata has none, so
`330` is exact. A daylight-saving timezone would need an IANA timezone
database in the app, which is not included. `timezone` from `/employee/me` is
parsed but not used.

## Offline storage and synchronization

**Event identity and idempotency.** Each check-in or check-out gets a UUID v4
`eventId` on the device, before anything else happens. It is saved to SQLite
as **Pending Sync** first, then sent to `POST /api/attendance/events`.
- Retries always resend the same `eventId` with an identical payload.
  `occurredAt` is sent with millisecond precision, matching what the server
  stores.
- For a repeated `eventId` with the same payload, the server returns the
  stored record instead of creating a new one.
- A different payload under a known `eventId` gets `409
  IDEMPOTENCY_KEY_REUSED`.
- A timeout after the server already accepted an event is therefore safe:
  the retry is confirmed and becomes **Synced**.

**When sync runs**
- After each check-in/check-out.
- At app start.
- When connectivity changes from offline to online (`connectivity_plus`).
  Being connected does not guarantee the server is reachable; the request
  itself decides.
- On **Sync Now**.

Only one sync or attendance action runs at a time.

**Order and outcomes**
- Pending events are sent oldest first.
- A network error or 5xx stops the run and leaves events **Pending Sync**.
- A 409/422 marks the event **Rejected** with the server's reason, shown on
  the dashboard. A checkout queued behind a rejected check-in is rejected too.

**Server history**
- On load, the app pulls the current month's history, plus the previous month
  if the current one has fewer than five records.
- It imports those records by `eventId` without duplicating anything. This is
  how a check-in made on another device appears.
- When a check-in is rejected because the day already has one, the app pulls
  that day's history so the existing check-in is shown.

**Offline start**
- The employee profile, office location and leave balance come from the
  dashboard cache.
- On a first-ever start with no connection, there is nothing to use. The app
  explains that it must connect once, rather than inventing an office
  location.

Clearing the app's data removes only local data. Server records are
downloaded again on the next online start.

## Attendance rules

| Rule | Client | Mock server |
|---|---|---|
| One check-in per company day | `AttendancePolicy` + SQLite unique index | 409 `ATTENDANCE_ALREADY_EXISTS` |
| Check-out only after check-in, once | `AttendancePolicy` | 422 `CHECK_IN_REQUIRED` / 409 |
| Within the office radius | `GeofencePolicy` (haversine, `<= radiusMeters`) | 422 `OUTSIDE_GEOFENCE` |
| Company date matches the timestamp | `CompanyClock.dateOf(occurredAt)` | 422 `COMPANY_DATE_MISMATCH` |
| Repeated or retried event | one `eventId` per action | idempotent by `eventId` |
| GPS accuracy at most 50 m | `AttendanceService` | **not checked** |
| Field validation | typed model | 400 `INVALID_ATTENDANCE_EVENT` |

A production server must repeat every rule it relies on, because a modified
client can skip any device-side check. In particular, it should add:
- authentication, and taking the employee from it (the mock trusts a fixed
  employee);
- the GPS accuracy limit;
- a timestamp window against the server clock (the mock accepts back-dated
  events whose company date matches);
- persistent storage.

## Mock office location and radius

The office comes from the backend, `backend/src/server.ts`:

```ts
const employee = {
  // ...
  office: { latitude: 11.190723, longitude: 75.950761, radiusMeters: 200 },
  timezone: "Asia/Kolkata"
};
```

The app downloads it from `GET /api/employee/me` and caches it. To move the
office, edit these fields and restart the server, then refresh the app.
The server's `OUTSIDE_GEOFENCE` message says "200 metres" as fixed text even
if `radiusMeters` changes. The app's own message uses the real radius.

## Simulating a location

These are standard platform tools. They were **not run as part of this
project's verification**.

- **iOS Simulator:** Features > Location > Custom Location, or
  `xcrun simctl location booted set 11.190723,75.950761`.
- **Android Emulator:** Extended Controls (…) > Location, or
  `adb emu geo fix 75.950761 11.190723` (longitude first).
- **Physical phone:** set `office.latitude`/`office.longitude` in
  `backend/src/server.ts` to where the phone is, restart the server, and
  refresh the app.

## Mock scenarios

All data is **in memory**. Restarting the server restores the seed data:
two attendance records on 2026-10-27, one approved leave request, and the
balance.

```bash
curl -X POST http://localhost:3000/api/__admin/scenario \
  -H 'Content-Type: application/json' -d '{"scenario":"timeout_after"}'
```

| Scenario | Effect (stays active until changed) |
|---|---|
| `normal` | Normal behaviour. |
| `slow` | Attendance submissions wait 3 s, then are processed. |
| `error500` | Attendance submissions return 500; nothing is stored. |
| `timeout_before` | Attendance submissions wait 10 s, then return 504 without storing. The app's 10 s timeout usually fires first. |
| `timeout_after` | The event **is stored**, and the response is delayed 10 s, so the app times out. The retry is confirmed by `eventId`. |
| `duplicate` | Every attendance submission returns 409 `ATTENDANCE_ALREADY_EXISTS`. |
| `leave_rejection` | Leave submissions that pass the field, date and reason checks return 422 `LEAVE_VALIDATION_REJECTED`. |

Scenarios affect only `POST /api/attendance/events` and
`POST /api/leave/requests`; GET endpoints are unaffected.

`POST /api/__admin/reset` restores **attendance records only** to the seed
data and sets the scenario to `normal`. It does **not** reset leave requests
or the leave balance; only a server restart does that.

## Tests and static analysis

```bash
cd frontend
fvm flutter analyze
fvm flutter test        # 145 tests at the time of writing

cd ../backend
npm run typecheck       # tsc --noEmit; the backend has no automated tests
```

The tests use an in-memory SQLite database, plus a file-backed one for the
restart test. A fake Dio server copies the backend's attendance rules, and
the clock and connectivity are fakes. They do not need the mock API to be
running.

## Known limitations and assumptions

- **Not verified on a device:** the full flows have not been checked end to
  end on devices as part of this documentation, and features added since the
  last device session have not been tried on one: recent history, worked
  time, company-time display and auto-sync. See the checklist.
- **One preconfigured employee, no login,** as the assignment allows. The mock
  API has no authentication.
- **Timezone:** a fixed UTC offset with no daylight saving (see above).
- **No background sync** while the app is closed (out of scope). Sync runs at
  start, on reconnect, after actions and on Sync Now. There is no periodic
  retry while connected but the server is down.
- **Sync Now banner:** appears only when **today's** events are pending.
  Older pending events still sync automatically and through Sync Now.
- **History depth:** the current month, plus the previous month when there
  are fewer than five records.
- **First offline start:** attendance needs one successful online load.
- **Leave submissions are not idempotent.** A timed-out submission may have
  been saved, and the app says to refresh before retrying.
- **Leave balance:** the balance never decreases, and pending requests do not
  reserve days. There is no approval workflow; statuses only change in the
  mock data.
- **Midnight on an open screen:** the dashboard does not roll over to the new
  day while open; it updates on the next load, refresh or action.
- **Repository hygiene:** `backend/node_modules`, a stray `frontend/frontend/`
  project, `.DS_Store` and `.idea` files are tracked in git, and there is no
  root or backend `.gitignore`. They should be cleaned up before submission.

## Deliverables

| Deliverable | Status |
|---|---|
| Source repository | This repository (clean up the tracked files listed above first) |
| Installable debug APK | **To do:** build with the command above and install-test it |
| Mock API + setup instructions | `backend/` + this README |
| README | This file |
| Demo video (3–5 min) | **To do.** Show dashboard loading, an online check-in, an offline action, an app restart with the pending action kept, sync after reconnecting, and leave validation and submission. |

## AI-use disclosure

> **Developer to confirm and edit.** AI-assisted tools (Claude Code) were used
> during development: investigation, implementation, tests and documentation.
> All submitted code has been reviewed by the developer, who can explain and
> modify it.

## Time spent

> **Developer to fill in:** _N hours_ (not recorded by the AI tools).
