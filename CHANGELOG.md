## 0.4.0

### Security
- **Encryption Support**: Added `encryptionKey` option to `UploadQueue` allowing the database to be fully encrypted at rest (typically requires a federated SQLCipher package like `sqlcipher_flutter_libs`).
- **Metadata Encryption**: Added `MetadataCodec` interface to `UploadQueue` for encrypting only PII data inside `metadata` fields without encrypting the entire database.

## 0.3.0

### Performance
- **Event-Based Lock Takeover**: `QueueController` now listens to SQLite lock table updates (`tableUpdates`) to immediately resume uploads when a worker releases a lock, eliminating the default 30s polling delay in multi-isolate setups.
- **Adaptive Polling**: In background execution contexts with short deadlines (e.g. iOS `BGTaskScheduler`), the polling interval is adaptively reduced to prevent missing the execution window.

## 0.2.0

### Performance
- **Zero-Copy Sandbox**: `copyToSandbox` now attempts to use hardlinks (`ln`) first on compatible filesystems to eliminate disk I/O and duplication overhead.
- **Streaming Copy**: Introduced `sandboxCopyThresholdBytes` in `UploadQueueAdvancedOptions`. Files larger than this threshold fallback to an asynchronous chunked streaming copy instead of blocking `File.copy()`, saving memory on large files.

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
