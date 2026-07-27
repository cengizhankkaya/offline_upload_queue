# offline_upload_queue

**Offline-first, sequential image upload queue for Flutter** — persistent, retry-capable, background-aware.

[![pub.dev](https://img.shields.io/pub/v/offline_upload_queue.svg)](https://pub.dev/packages/offline_upload_queue)
[![pub points](https://img.shields.io/pub/points/offline_upload_queue)](https://pub.dev/packages/offline_upload_queue/score)
[![CI](https://github.com/cengizhankkaya/offline_upload_queue/actions/workflows/ci.yml/badge.svg)](https://github.com/cengizhankkaya/offline_upload_queue/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-blue.svg)](https://pub.dev/packages/offline_upload_queue)

Uploads survive app restarts, network interruptions, and background termination.
Built on **SQLite/Drift** for durability, **Dio** for networking, and **BGTaskScheduler / Workmanager** for background sync.

---

<!-- Replace with an animated GIF captured from the example app:
     flutter run example/ → record with Xcode/Android Studio → convert with ffmpeg
     Suggested: 600px wide, 15fps, ~4s loop showing enqueue → uploading → completed -->
<!-- ![Queue demo](docs/screenshots/demo_queue.gif) -->

---

## Features

- 📦 **Persistent queue** — SQLite-backed; tasks survive process kills and reboots
- 🔁 **Automatic retry** with exponential backoff + jitter (configurable attempts & strategy)
- 📶 **Wi-Fi only mode** + `forceUploadOnce()` for on-demand cellular override
- 🔄 **Reactive streams** — `watchSummary()` / `watchTasks()` / `watchProgress()`
- 💾 **Disk usage tracking** — `estimatedDiskUsageBytes` + configurable warning threshold
- 🛡️ **Checksum verification** — SHA-256 end-to-end integrity check
- 🌐 **Background sync** — iOS `BGTaskScheduler` + Android Workmanager (best-effort)
- 🔌 **Pluggable adapter** — bring your own `UploadAdapter` implementation
- 🔑 **Token refresh** — `onAuthExpired` callback for seamless 401/403 recovery
- 📋 **Structured logging** — `onLog` hook for routing events to Sentry / Crashlytics
- 🗂️ **Multiple queues** — independent SQLite databases per `boxName`

---

## Installation

```bash
flutter pub add offline_upload_queue
```

Or add manually to `pubspec.yaml`:

```yaml
dependencies:
  offline_upload_queue: ^0.1.0
```

---

## Quick Start

```dart
import 'package:offline_upload_queue/offline_upload_queue.dart';

final queue = UploadQueue(
  adapter: RestUploadAdapter(
    baseUrl: 'https://api.example.com',
    authHeaderProvider: () async => 'Bearer ${await tokenStore.getToken()}',
  ),
);
await queue.init();

// Add a file to the queue
final taskId = await queue.enqueue(
  filePath: photo.path,
  metadata: {'albumId': '42', 'userId': 'u1'},
);

// Listen to live summary
queue.watchSummary().listen((s) {
  print('${s.pending} pending, ${s.completed} completed');
  print('Disk usage: ${s.estimatedDiskUsageBytes} bytes');
});

// Clean up when done
await queue.dispose();
```

> [!WARNING]
> **Storage cost (~2× disk usage):** By default, `copyToSandbox: true` copies every
> enqueued file into the package's sandbox directory. This means disk usage is roughly
> **doubled** for pending files. See [Storage Cost](#️-storage-cost-2-disk-usage) below.

---

## ⚠️ Storage Cost (~2× Disk Usage)

By default, `copyToSandbox: true` copies every enqueued file into the package's
private sandbox directory (`ApplicationSupportDirectory/<boxName>/sandbox/`), so
uploads survive even if the **original file is deleted** between `enqueue()` and upload.

This means:
- **Disk usage is roughly doubled** for all pending/failed/cancelled tasks.
- Sandbox copies are **automatically deleted** when a task reaches `completed`.
- Cancelled or permanently-failed tasks keep their sandbox copy until you call `purge()`.

**Monitor disk usage:**
```dart
UploadQueue(
  adapter: ...,
  advanced: UploadQueueAdvancedOptions(
    diskUsageWarningBytes: 200 * 1024 * 1024, // 200 MB
    onDiskUsageWarning: (current, limit) {
      showStorageWarningBanner(current, limit);
    },
  ),
)
```

**If disk cost is a concern:** Set `copyToSandbox: false` — but read
[copyToSandbox: false Risks](#copytosandbox-false-risks) first.

---

## Platform Setup

### iOS

**1. `Info.plist`** — register BGTask identifiers:

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>com.example.app.upload_refresh</string>
  <string>com.example.app.upload_processing</string>
</array>
```

**2. Xcode → Signing & Capabilities → Background Modes**

Check **both**:
- ✅ Background fetch
- ✅ Background processing

> [!CAUTION]
> If Background Modes are **not** checked in Xcode, `BGTaskScheduler` will
> **silently never fire** — no error, no log. CI cannot catch this. Always verify
> on a real device before release.

**3. `AppDelegate.swift`** — register task handlers:

```swift
import BackgroundTasks

// Inside application(_:didFinishLaunchingWithOptions:):
BGTaskScheduler.shared.register(
  forTaskWithIdentifier: "com.example.app.upload_refresh",
  using: nil
) { task in
  self.handleAppRefresh(task: task as! BGAppRefreshTask)
}

BGTaskScheduler.shared.register(
  forTaskWithIdentifier: "com.example.app.upload_processing",
  using: nil
) { task in
  self.handleProcessing(task: task as! BGProcessingTask)
}
```

**4. Dart side:**

```dart
IosBackgroundChannel.instance.setMethodCallHandler(
  onAppRefresh: () => BackgroundTaskRunner.run(queue),
  onProcessing:  () => BackgroundTaskRunner.run(queue),
  onExpiration:  ()  { queue.dispose(); },
);

await IosBackgroundChannel.instance.scheduleAppRefresh(
  refreshIdentifier: 'com.example.app.upload_refresh',
);
await IosBackgroundChannel.instance.scheduleProcessing(
  processingIdentifier: 'com.example.app.upload_processing',
  requiresNetworkConnectivity: true,
);
```

---

### Android

**`AndroidManifest.xml`** — add Workmanager initialization and permissions
(see [workmanager setup](https://pub.dev/packages/workmanager)):

```xml
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
```

**`main.dart`:**

```dart
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == AndroidBackgroundRunner.taskName) {
      final queue = UploadQueue(adapter: MyAdapter());
      final hasPending = await BackgroundTaskRunner.run(queue);
      // Chain: re-schedule if work remains
      if (hasPending) await AndroidBackgroundRunner.scheduleNextRun();
      return true;
    }
    return false;
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().initialize(callbackDispatcher, isInDebugMode: kDebugMode);
  runApp(const MyApp());
}
```

---

## Task State Machine

![UploadStatus state machine](docs/screenshots/state_machine.png)

| State | Meaning |
|---|---|
| `pending` | In queue, waiting to be picked up by the worker |
| `uploading` | Worker is actively sending the file |
| `completed` | Successfully uploaded; sandbox copy deleted |
| `failed` | Temporary error; will retry after backoff delay |
| `permanentlyFailed` | Permanent error or `maxAttempts` reached; no auto-retry |
| `cancelled` | Cancelled by `cancel()`; no auto-retry |

**Recovery:** Both `permanentlyFailed` and `cancelled` tasks can be re-queued via `retry(taskId)`.

---

## API Reference

### `UploadQueue` — Methods

| Method | Description |
|---|---|
| `init()` | Initialize the queue. **Must be called before any other method.** |
| `enqueue({filePath, metadata})` | Add a file; returns `taskId` (UUID) |
| `cancel(taskId)` | Cancel a task; stops active HTTP request immediately |
| `retry(taskId)` | Re-queue a `permanentlyFailed` or `cancelled` task |
| `purge(taskId)` | Delete a task and its sandbox copy permanently |
| `purgeAllFailed()` | Delete all `permanentlyFailed` tasks and sandbox copies |
| `purgeAllCancelled()` | Delete all `cancelled` tasks and sandbox copies |
| `purgeAllCompleted()` | Delete `completed` DB rows (sandbox already cleaned up) |
| `pause()` | Pause the worker — in-memory, resets on restart |
| `resume()` | Resume a paused worker |
| `forceUploadOnce()` | Drain queue now over current connection (bypasses `wifiOnly`) |
| `watchSummary()` | Reactive `Stream<QueueSummary>` |
| `watchTasks({statuses, limit, offset})` | Reactive `Stream<List<UploadTask>>` |
| `watchProgress(taskId)` | Reactive `Stream<double>` (0.0–1.0) |
| `dispose()` | Release resources — active upload reverts to `pending`, not `cancelled` |

### `UploadQueue` — Constructor Parameters

| Parameter | Default | Description |
|---|---|---|
| `adapter` | **required** | `UploadAdapter` implementation |
| `maxAttempts` | `6` | Total attempts including first try |
| `backoff` | exponential(2s, 10min) | `BackoffStrategy` (exponential or fixed) |
| `verifyChecksum` | `true` | Compare remote checksum with local SHA-256 |
| `boxName` | `'default'` | Unique name per independent queue |
| `copyToSandbox` | `true` | Copy file to package sandbox on enqueue |
| `wifiOnly` | `false` | Only upload on Wi-Fi |
| `connectivityMonitor` | `DefaultConnectivityMonitor()` | Override for custom reachability or tests |
| `onAuthExpired` | `null` | Async callback for token refresh on 401/403 |
| `authTimeout` | 30 seconds | Max wait for `onAuthExpired` to complete |
| `advanced` | `UploadQueueAdvancedOptions()` | Heartbeat, disk warning, logging |

### `UploadQueueAdvancedOptions`

| Parameter | Default | Description |
|---|---|---|
| `staleLockThreshold` | 5 minutes | How long before a silent worker's lock is considered stale. **Requires calibration** — see [staleLockThreshold Calibration](#staleLockThreshold-requires-calibration). |
| `heartbeatInterval` | 30 seconds | How often the worker writes a heartbeat to the DB |
| `diskUsageWarningBytes` | `null` | Trigger `onDiskUsageWarning` when total pending size exceeds this |
| `onDiskUsageWarning` | `null` | `(currentBytes, warningBytes)` callback |
| `onLog` | `null` | Hook for internal events (lock takeover, auth timeout, corrupt file) |

### `FailureType` Reference

| FailureType | HTTP Code | Permanent? | Cause |
|---|---|---|---|
| `network` | — | No | Timeout, DNS failure, connection reset |
| `serverError` | 5xx | No | Temporary server-side error |
| `rateLimited` | 429 | No | Respects `Retry-After` header |
| `authExpired` | 401 / 403 | No | Triggers `onAuthExpired` callback |
| `fileNotFound` | — | **Yes** | File deleted or moved before upload |
| `corruptFile` | — | **Yes** | File unreadable after 3 attempts |
| `payloadTooLarge` | 413 | **Yes** | Exceeds backend size limit |
| `badRequest` | 4xx (other) | **Yes** | Invalid request parameters |
| `unknown` | — | No | Unclassified error |

**Permanent failures** go directly to `permanentlyFailed` — no backoff, no auto-retry.
Use `retry(taskId)` to manually re-queue.

---

## Common Patterns

### Multiple independent queues

```dart
final photoQueue = UploadQueue(adapter: ..., boxName: 'photos');
final docQueue   = UploadQueue(adapter: ..., boxName: 'documents');
```

Each `boxName` uses its own SQLite database file and worker lock.

---

### Wi-Fi only + cellular override

```dart
final queue = UploadQueue(adapter: ..., wifiOnly: true);
await queue.init();

// User taps "Upload now" on cellular:
await queue.forceUploadOnce(); // processes all current pending tasks once
```

> [!NOTE]
> `forceUploadOnce()` takes a snapshot of the current `pending` tasks at call time.
> New tasks added afterward still require Wi-Fi (unless `forceUploadOnce()` is called again).

---

### Handle permanently failed tasks

```dart
queue.watchSummary().listen((s) {
  if (s.permanentlyFailed > 0) {
    showRetryDialog(count: s.permanentlyFailed);
  }
});

// User confirms retry:
await queue.retry(taskId);  // resets retryCount, re-queues at front

// Or bulk delete:
await queue.purgeAllFailed();
```

---

### Live upload progress bar

```dart
// Show progress only for the actively uploading task
queue.watchTasks(statuses: {UploadStatus.uploading}).listen((tasks) {
  if (tasks.isNotEmpty) {
    final taskId = tasks.first.taskId;
    queue.watchProgress(taskId).listen((ratio) {
      updateProgressBar(ratio); // 0.0 → 1.0
    });
  }
});
```

---

### Display queue position (correct way)

```dart
// ✅ Use list index — not sequenceNumber
queue.watchTasks(statuses: {UploadStatus.pending}).listen((tasks) {
  for (final (i, task) in tasks.indexed) {
    print('Photo ${i + 1} of ${tasks.length}: ${task.taskId}');
  }
});

// ❌ Do NOT use task.sequenceNumber for UI display
// sequenceNumber has gaps after deletions/retries
```

---

### Token refresh on 401/403

```dart
final queue = UploadQueue(
  adapter: RestUploadAdapter(
    baseUrl: 'https://api.example.com',
    authHeaderProvider: () async => 'Bearer ${await tokenStore.getToken()}',
  ),
  onAuthExpired: () async {
    // Refresh the token — adapter will pick it up on the next attempt
    await tokenStore.refresh();
  },
  authTimeout: const Duration(seconds: 30),
);
```

The worker automatically re-queues the task after a successful refresh.
If the callback throws or times out, the task falls into the normal `failed` / backoff cycle.

---

### Structured logging (Sentry / Crashlytics)

```dart
UploadQueue(
  adapter: ...,
  advanced: UploadQueueAdvancedOptions(
    onLog: (message, {required level}) {
      if (level == LogLevel.warning || level == LogLevel.error) {
        Sentry.captureMessage(message, level: SentryLevel.warning);
      }
    },
  ),
)
```

`onLog` is called only for **unexpected internal events** (lock takeover, auth timeout,
`corruptFile` downgrade, sandbox delete failure). Routine upload flow is not logged —
use `watchSummary()` and `watchTasks()` for that.

---

### Custom adapter (S3, GCS, custom REST)

```dart
class MyS3Adapter implements UploadAdapter {
  @override
  Future<UploadResult> uploadFile({
    required String taskId,
    required String filePath,
    required Map<String, dynamic> metadata,
    required String checksum,
    void Function(int sent, int total)? onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    // cancelToken: register your cancellation hook
    cancelToken?.registerOnCancel(() { /* abort S3 multipart */ });

    // ... your upload logic ...

    return const UploadResult.success(remoteChecksum: 'sha256-from-server');
  }
}
```

---

### Testing with mocks

```dart
import 'package:offline_upload_queue/src/queue/queue_controller.dart';
import 'test/helpers/in_memory_persistence_repository.dart'; // copy from package

class MockConnectivityMonitor implements ConnectivityMonitor {
  @override
  Future<ConnectivityStatus> checkStatus() async => ConnectivityStatus.wifi;
  @override
  Stream<ConnectivityStatus> get statusStream => const Stream.empty();
}

class MockAdapter implements UploadAdapter {
  @override
  Future<UploadResult> uploadFile({...}) async {
    return const UploadResult.success();
  }
}

// Test QueueController directly — no real SQLite needed
final controller = QueueController(
  repository: InMemoryPersistenceRepository(),
  adapter: MockAdapter(),
  connectivityMonitor: MockConnectivityMonitor(),
  // ...
);
await controller.init();
```

See [`test/helpers/in_memory_persistence_repository.dart`](test/helpers/in_memory_persistence_repository.dart)
for the full in-memory implementation.

---

## Important Caveats

### Background sync is best-effort, not guaranteed

> [!IMPORTANT]
> **iOS:** `BGTaskScheduler` uses *opportunistic* scheduling — the system may not
> fire background tasks for days depending on app usage patterns and battery. Do
> not market this package as "always syncs in the background."
>
> **Android:** `Workmanager` is subject to OS Doze mode, App Standby, and
> OEM-specific battery optimizations. Guaranteed background execution is not possible.
>
> **The reliable sync path on both platforms is the foreground:** the worker starts
> automatically on `init()` and drains the queue as long as the app is running.

---

### `copyToSandbox: false` risks

When `copyToSandbox: false`, the `filePath` you provide is **entirely your
responsibility** until the upload completes:

- **Android `content://` URIs** (Storage Access Framework) — the package opens files
  with `File(filePath)`, which cannot handle SAF URIs. Resolve them to a real file path first.
- **iOS `PHAsset` references** — same issue; export to a temp file before enqueueing.
- If the file is **deleted or moved** before upload, the task fails with
  `FailureType.fileNotFound` (permanent — no retry).

---

### `checksum` timing

`checksum` is computed when the task transitions to `uploading`, **not** at
`enqueue()` time. A file that changes between `enqueue()` and upload will be
sent with the **modified content** — it will **not** be flagged as `corruptFile`.

If you need immutability guarantees, keep your own reference checksum at `enqueue()` time.

---

### `sequenceNumber` is not a UI counter

`sequenceNumber` determines worker processing order internally. It has gaps after
deletions and retries. For "photo #N in queue" display, **use the list index**
from `watchTasks()` instead.

---

### `retry()` resets retry state

`retry(taskId)` resets both `retryCount` and `nextRetryAt` to zero — the task is
treated as if it were freshly enqueued. This means it may be processed **before**
other pending tasks that were added later (sequence ordering takes precedence).

---

### `dispose()` reverts active upload to `pending`

If `dispose()` is called while a task is uploading, the active HTTP request is
cancelled and the task is moved back to **`pending`** (not `cancelled`). This ensures
the upload is retried on the next `init()` without losing the task permanently.

---

### `staleLockThreshold` requires calibration

The default **5-minute** stale lock threshold is an estimate, not a measured value.
Calibrate based on your typical upload durations:

- **Too short** → a slow-but-alive worker's lock may be stolen by a new instance.
- **Too long** → a crashed worker's tasks remain stuck until the threshold expires.

Constraint: `staleLockThreshold` must be at least `heartbeatInterval × 3`
(enforced by `init()` — throws `ArgumentError` otherwise).

---

### `DefaultConnectivityMonitor` privacy note

The default reachability URL (`https://connectivitycheck.gstatic.com/generate_204`)
is a Google endpoint. For GDPR/KVKK-sensitive applications, point it at your own
infrastructure:

```dart
UploadQueue(
  adapter: ...,
  connectivityMonitor: DefaultConnectivityMonitor(
    reachabilityUrl: 'https://api.myapp.com/health',
  ),
)
```

---

## Security / Sensitive Data

> [!WARNING]
> **No encryption is provided.** Upload queue data (file paths, metadata, task
> status) is stored in **plaintext SQLite** on the device. If your app handles
> sensitive personal data under GDPR/KVKK/HIPAA regulations, you must:
>
> 1. **Avoid storing sensitive PII in `metadata`** — it is persisted as a plain
>    JSON string in SQLite.
> 2. **Enable OS-level encryption** — Android File-Based Encryption (FBE) or
>    iOS Data Protection class (files encrypted at rest when device is locked).
> 3. **Implement an encrypted `PersistenceRepository`** — the
>    [`PersistenceRepository`](lib/src/database/persistence_repository.dart)
>    abstract interface is designed to accept alternative storage backends
>    (e.g., SQLCipher-backed Drift).

---

## Contributing

Issues and pull requests are welcome!

- 🐛 **Bug reports:** [GitHub Issues](https://github.com/cengizhankkaya/offline_upload_queue/issues)
- 💡 **Feature requests:** [GitHub Discussions](https://github.com/cengizhankkaya/offline_upload_queue/discussions)
- 🔀 **Pull requests:** Please open an issue first to discuss the change.

When contributing, please:
- Run `flutter test` and ensure all tests pass.
- Run `dart format .` and `flutter analyze` before submitting.
- Follow the existing code style and documentation conventions.

---

## License

MIT — see [LICENSE](LICENSE).
