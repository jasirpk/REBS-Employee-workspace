# REBS Employee Workspace (Flutter app)

The Flutter app for the REBS Employee Workspace. See the
[root README](../README.md) for setup, build-time configuration
(`frontend/.env`: `API_BASE_URL`, `COMPANY_UTC_OFFSET_MINUTES`), architecture,
offline sync, mock scenarios and known limitations.

Quick reference, run from this folder:

```bash
cp .env.example .env    # first time only; set API_BASE_URL for your machine
fvm flutter pub get
fvm flutter run --dart-define-from-file=.env
fvm flutter build apk --debug --dart-define-from-file=.env
fvm flutter analyze
fvm flutter test        # needs no .env
```

`.env` is read by the Flutter tool at build time and compiled into the app;
it is git-ignored and not packaged as a file. Without a valid `API_BASE_URL`
the app shows an "App configuration error" screen.
