# REBS Employee Workspace (Flutter app)

The Flutter app for the REBS Employee Workspace. See the
[root README](../README.md) for setup, configuration, architecture, offline
sync, mock scenarios and known limitations.

Quick reference, run from this folder:

```bash
cp .env.example .env    # required after cloning; set API_BASE_URL for your target
fvm flutter pub get
fvm flutter run
fvm flutter build apk --debug
fvm flutter analyze
fvm flutter test        # does not need .env
```

`frontend/.env` holds the mock API address, e.g.
`API_BASE_URL=http://192.168.1.2:3000/api/`. That IP is an example: use the
Mac's LAN IP for a physical phone, `http://localhost:3000/api/` for the iOS
Simulator, or `http://10.0.2.2:3000/api/` for the Android Emulator.

`flutter_dotenv` loads the file at app start. It is git-ignored, and it is
bundled into the app as an asset (declared in `pubspec.yaml`), so it must
exist before building and must never contain secrets. Without a valid
`API_BASE_URL`, the app shows an "App configuration error" screen.

`COMPANY_UTC_OFFSET_MINUTES` is separate: a `--dart-define` flag
(default `330`), not a `.env` value.
