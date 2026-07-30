# offline_upload_queue example

Demo app for the package public API and platform background setup.

## Run

```bash
# Optional: mock server for ExampleRestAdapter
dart run tool/mock_server.dart

cd example
flutter run
```

## Tabs

| Tab | What it demos |
|---|---|
| Queue | enqueue, progress, cancel, summary streams |
| Cellular | `wifiOnly` + `forceUploadOnce` |
| Errors | permanent / transient failure and retry |
| Disk | sandbox usage and warning threshold |
| Debug | logs, pause/resume signals |

## Platform setup

- **iOS:** `Info.plist` BGTask IDs + `AppDelegate.swift` MethodChannel
- **Android:** Workmanager `callbackDispatcher` + `RECEIVE_BOOT_COMPLETED`

See the root [README.md](../README.md) Background Sync section for details.
