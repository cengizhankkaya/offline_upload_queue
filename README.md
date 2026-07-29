# Offline Upload Queue

**An enterprise-grade, offline-first image and file upload queue for Flutter.** 
Built for durability, this package ensures your uploads survive app terminations, network outages, and background restrictions.

[![pub.dev](https://img.shields.io/pub/v/offline_upload_queue.svg?style=flat-square)](https://pub.dev/packages/offline_upload_queue)
[![pub points](https://img.shields.io/pub/points/offline_upload_queue?style=flat-square)](https://pub.dev/packages/offline_upload_queue/score)
[![CI](https://github.com/cengizhankkaya/offline_upload_queue/actions/workflows/ci.yml/badge.svg?style=flat-square)](https://github.com/cengizhankkaya/offline_upload_queue/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-blue.svg?style=flat-square)](https://pub.dev/packages/offline_upload_queue)

Whether your users are deep in the subway, switching between Wi-Fi and Cellular, or force-closing your app during an upload, `offline_upload_queue` guarantees their data is safely queued and automatically uploaded the moment conditions allow. 

Powered by **Sembast** (for pure-Dart durability), **Dio** (for robust networking), and **Workmanager / BGTaskScheduler** (for OS-level background sync).

---

## 🌟 Why `offline_upload_queue`?

* **True Offline-First:** Enqueue files instantly without waiting for a network connection.
* **Crash & Reboot Resilient:** Tasks are persisted to a local Sembast database. If the app is killed mid-upload, it resumes on the next launch.
* **OS-Level Background Sync:** Native integrations wake up your app in the background to drain the queue silently.
* **Pluggable Architecture:** Bring your own `UploadAdapter` (REST, GraphQL, AWS S3, Firebase).
* **Reactive UI:** Full stream-based API for rendering live progress bars and queue summaries.

---

## 📦 Features

- 💾 **Persistent Queue** — Data survives process kills and device reboots.
- 🔁 **Smart Retries** — Configurable exponential backoff with jitter.
- 📶 **Network Constraints** — Wi-Fi only mode with `forceUploadOnce()` cellular override.
- 🔄 **Reactive Streams** — Listen to `watchSummary()`, `watchTasks()`, and `watchProgress()`.
- 🛡️ **Data Integrity** — End-to-end SHA-256 checksum verification.
- 🔐 **Token Refresh** — Built-in `onAuthExpired` hook for seamless 401/403 recovery.
- 📊 **Storage Management** — Disk usage tracking and warning thresholds.
- 🗂️ **Multi-Queue Support** — Isolated databases via `boxName`.

---

## ⚙️ Installation

```bash
flutter pub add offline_upload_queue
```

---

## 🚀 Quick Start

```dart
import 'package:offline_upload_queue/offline_upload_queue.dart';

// 1. Initialize the queue
final queue = UploadQueue(
  adapter: RestUploadAdapter(
    baseUrl: 'https://api.example.com',
    authHeaderProvider: () async => 'Bearer ${await tokenStore.getToken()}',
  ),
);
await queue.init();

// 2. Enqueue a file
final taskId = await queue.enqueue(
  filePath: photo.path,
  metadata: {'albumId': '42', 'userId': 'u1'},
);

// 3. Listen to live queue summary
queue.watchSummary().listen((summary) {
  print('${summary.pending} pending, ${summary.completed} completed');
});

// 4. Clean up when done (e.g., on app termination)
await queue.dispose();
```

---

## 🏗️ Architecture & Core Concepts

### Task State Machine

Tasks flow sequentially through a strictly defined state machine. **Only one file is uploaded at a time** to prevent bandwidth saturation.

| State | Description |
|---|---|
| 🟡 `pending` | In the queue, waiting to be processed by the worker. |
| 🔵 `uploading` | Worker is actively uploading the file. |
| 🟢 `completed` | Successfully uploaded; sandbox copy is cleaned up. |
| 🟠 `failed` | Temporary error (e.g., Network loss). Will automatically retry. |
| 🔴 `permanentlyFailed`| Fatal error (e.g., 400 Bad Request, max attempts reached). Auto-retry is disabled. |
| ⚪ `cancelled` | Manually cancelled via `cancel(taskId)`. Auto-retry is disabled. |

*(Note: `permanentlyFailed` and `cancelled` tasks can be manually re-enqueued via `queue.retry(taskId)`).*

### ⚠️ Storage Cost & Sandboxing

By default, the queue operates with `copyToSandbox: true`. This means every enqueued file is copied to an internal, private directory. 

* **Advantage:** If the user deletes the original photo from their gallery before the upload finishes, the upload still succeeds.
* **Trade-off:** Disk usage is roughly **doubled** for pending tasks.

> **Pro-Tip:** Monitor disk usage by providing an `UploadQueueAdvancedOptions(diskUsageWarningBytes: ...)` to warn users if the offline queue is taking up too much space.

---

## 🌐 Background Sync Setup

For uploads to continue when your app is completely terminated, you must configure platform-specific background handlers.

### 🍏 iOS (`BGTaskScheduler`)

**1. Update `Info.plist`**
```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>com.example.app.upload_refresh</string>
  <string>com.example.app.upload_processing</string>
</array>
```

**2. Enable Background Modes**
In Xcode, go to **Signing & Capabilities -> Background Modes** and check **Background fetch** and **Background processing**. *(If missed, tasks will silently fail).*

**3. Register in `AppDelegate.swift`**
```swift
import BackgroundTasks

// Inside application(_:didFinishLaunchingWithOptions:):
BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.example.app.upload_refresh", using: nil) { task in
  self.handleAppRefresh(task: task as! BGAppRefreshTask)
}
BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.example.app.upload_processing", using: nil) { task in
  self.handleProcessing(task: task as! BGProcessingTask)
}
```

**4. Hook up in Dart**
```dart
IosBackgroundChannel.instance.setMethodCallHandler(
  onAppRefresh: () => BackgroundTaskRunner.run(queue),
  onProcessing: () => BackgroundTaskRunner.run(queue),
  onExpiration: () { queue.dispose(); },
);
```

### 🤖 Android (`Workmanager`)

**1. Update `AndroidManifest.xml`**
```xml
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
```

**2. Configure the Dispatcher in Dart**
Ensure this is defined as a top-level function.

```dart
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (taskName == AndroidBackgroundRunner.taskName) {
      final queue = UploadQueue(adapter: MyAdapter());
      final hasPending = await BackgroundTaskRunner.run(queue);
      if (hasPending) await AndroidBackgroundRunner.scheduleNextRun();
      return true;
    }
    return false;
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().initialize(callbackDispatcher);
  runApp(const MyApp());
}
```

> **Important:** Background execution is **best-effort**. iOS uses opportunistic scheduling, and Android is subject to Doze mode. Guaranteed instant execution is not possible on modern mobile OS.

---

## 📖 API Reference Highlights

### Queue Controls
* `queue.init()` — Initializes the Sembast database and starts the worker loop.
* `queue.pause()` / `queue.resume()` — Temporarily suspends the worker (resets on app restart).
* `queue.forceUploadOnce()` — Bypasses `wifiOnly` rules to process the current snapshot of pending tasks over cellular.
* `queue.dispose()` — Safely cancels active requests and gracefully shuts down the worker.

### Task Management
* `queue.cancel(taskId)` — Stops an active upload immediately.
* `queue.retry(taskId)` — Resets backoff state and re-enqueues a failed/cancelled task.
* `queue.purgeAllCompleted()` — Cleans up database records for finished uploads (sandbox files are deleted automatically).

### Streams
* `watchSummary()` — Emits total counts for all states (e.g. `pending`, `uploading`, `failed`).
* `watchTasks({statuses})` — Emits the actual list of tasks. **Always use the list index for UI counters**, as `sequenceNumber` can have gaps.
* `watchProgress(taskId)` — Emits a `double` from `0.0` to `1.0`.

---

## ⚠️ Important Caveats & Best Practices

1. **`copyToSandbox: false` Risks:** If you disable sandboxing, you are responsible for keeping the source file alive. Providing an Android `content://` URI or an iOS `PHAsset` directly will fail. You must resolve them to absolute physical file paths.
2. **Checksum Timing:** Checksums are computed right before the upload begins, **not** when enqueued. If a file is altered between enqueueing and uploading, it will be uploaded with the new content seamlessly.
3. **Stale Lock Calibration:** The worker uses a mutex lock to prevent concurrent uploads of the same file. The `staleLockThreshold` defaults to 5 minutes. If your uploads typically take 10 minutes, you **must** increase this threshold in `UploadQueueAdvancedOptions`, otherwise another worker might steal the lock mid-upload.

---

## 🔒 Security & Privacy

* **Encryption:** If you provide an `encryptionKey`, the local Sembast database encrypts metadata using a Salsa20+SHA256 codec. **Note:** This codec has not undergone independent security audits. For strict GDPR/KVKK/HIPAA compliance, do not store PII in the metadata, or use OS-level encryption (iOS Data Protection / Android FBE).
* **Connectivity Check:** By default, the package checks network reachability by pinging `https://connectivitycheck.gstatic.com/generate_204`. You can override this with your own infrastructure via `DefaultConnectivityMonitor(reachabilityUrl: '...')`.

---

## 🤝 Contributing

We welcome contributions! 
* 🐛 **Bug Reports:** [Open an Issue](https://github.com/cengizhankkaya/offline_upload_queue/issues)
* 💡 **Feature Requests:** [Discussions](https://github.com/cengizhankkaya/offline_upload_queue/discussions)
* 🔀 **Pull Requests:** Ensure all tests pass (`flutter test`) and code is formatted (`dart format .`).

## 📄 License

Distributed under the MIT License. See [LICENSE](LICENSE) for more information.
