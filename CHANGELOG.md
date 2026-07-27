## 0.1.0

Initial public release.

### Features

- Offline-first persistent upload queue backed by SQLite (via Drift).
- Sequential processing with configurable `maxAttempts` and exponential
  backoff retry (`BackoffStrategy.exponential` / `BackoffStrategy.fixed`).
- Wi-Fi only mode (`wifiOnly: true`) with cellular override via
  `forceUploadOnce()`.
- Reactive streams: `watchSummary()`, `watchTasks()`, `watchProgress()`.
- Disk usage tracking: `estimatedDiskUsageBytes` and configurable
  `onDiskUsageWarning` callback.
- SHA-256 checksum verification against optional server-side checksum.
- `copyToSandbox: true` (default) — files are copied to a package-managed
  sandbox directory on enqueue so originals can be deleted safely.
- Stale-lock recovery: `uploading → pending` on restart after crash.
- Worker heartbeat and atomic lock acquisition (SQLite single-writer guarantee).
- iOS background sync via `BGTaskScheduler` (`IosBackgroundChannel`).
- Android background sync via Workmanager (`AndroidBackgroundRunner`).
- Pluggable `UploadAdapter` interface (default: `RestUploadAdapter` with Dio).
- Pluggable `ConnectivityMonitor` interface (default: `DefaultConnectivityMonitor`
  with reachability test).
- Pluggable `PersistenceRepository` interface for custom storage backends.
- `onAuthExpired` callback for token-refresh integration.
- `onLog` hook for routing internal events to Sentry / Crashlytics.
- Multiple independent queues via `boxName` parameter.
